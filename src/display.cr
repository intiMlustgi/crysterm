require "mutex"

require "event_handler"

require "./mixin/instances"

module Crysterm
  # A physical display managed by Crysterm. Can be created on anything that is an IO.
  #
  # If a `Display` object is not explicitly created, its creation will be
  # implicitly performed at the time of creation of first `Screen`.
  class Display
    include EventHandler

    include Mixin::Instances

    # Force Unicode (UTF-8) even if terminfo auto-detection did not find support for it?
    property? force_unicode = false

    # Input IO
    property input : IO = STDIN.dup

    # Output IO
    property output : IO = STDOUT.dup

    # Error IO. (Could be used for redirecting error output to a particular widget)
    property error : IO = STDERR.dup

    # Access to instance of `Tput`, used for generating term control sequences.
    getter tput : ::Tput

    # TODO make these check @output, not STDOUT which is probably used.
    # TODO Also see how urwid does the size check
    property width = ::Term::Screen.cols || 1
    property height = ::Term::Screen.rows || 1

    # Default application title, propagated as a default to contained `Screen`s
    property title : String? = nil

    # :nodoc: Pointer to Fiber which is listening for keys, if any
    private class Fibers
      property keys : Fiber?
    end

    protected property fibers = Fibers.new

    # `Display`'s general-purpose `Mutex`
    @mutex = Mutex.new

    def initialize(
      @input = @input,
      @output = @output,
      @error = @error,
      @title = @title,
      *,
      @width = @width,
      @height = @height,
      @use_buffer = false,
      @force_unicode = @force_unicode,
      terminfo : Bool | Unibilium::Terminfo = true,
      @term = ENV["TERM"]? || "{% if flag?(:windows) %}windows-ansi{% else %}xterm{% end %}"
    )
      terminfo = case terminfo
                 in true
                   Unibilium::Terminfo.from_env
                 in false, nil
                   nil
                 in Unibilium::Terminfo
                   terminfo.as Unibilium::Terminfo
                 end

      # XXX Should `error` fd be passed to tput as well?
      # (Probably not since we're not initializing anything on the error output?)
      @tput = ::Tput.new(
        terminfo: terminfo,
        input: @input,
        output: @output,
        # TODO activate these options if needed:
        # term: @term,
        # padding: @padding,
        # extended: @extended,
        # termcap: @termcap,
        use_buffer: @use_buffer,
        force_unicode: @force_unicode
      )

      @mutex.synchronize do
        unless @@instances.includes? self
          @@instances << self
          # NOTE Can do anything else here, which will execute for every
          # display created
        end
      end

      # Push resize event to screens assigned to this display. We choose this approach
      # because it results in less links between the components (as opposed to pull model).
      on(::Crysterm::Event::Resize) do |e|
        # XXX Display should have a list of Screens belonging to it. But until that happens
        # we'll find them manually.
        Screen.instances.select(&.display.==(self)).try { |screens|
          screens.each do |scr|
            scr.emit e
          end
        }
      end
    end

    # Displays the main screen, set up IO hooks, and starts the main loop.
    #
    # This is similar to how it is done in the Qt framework.
    #
    # This function will render the specified `screen` or the first `Screen` assigned to `Display`.
    def exec(screen : Crysterm::Screen? = nil)
      s = @mutex.synchronize do
        screen || Screen.instances.select(&.display.==(self)).try { |screens| screens.first }
      end

      if s.display != self
        raise Exception.new "Screen does not belong to this Display."
      end

      if s
        s.render
      else
        # XXX This part might be changed in the future, if we allow running line-
        # rather than screen-based apps, or if we allow something headless.
        raise Exception.new "No Screen exists, there is nothing to render and run."
      end

      listen

      # The main loop is currently just a sleep :)
      sleep
    end

    # Sets up IO listeners for keyboard (and mouse, but mouse is currently unsupported).
    def listen
      # D O:
      # Potentially reset screen title on exit:
      # if !tput.rxvt?
      #  if !tput.vte?
      #    tput.set_title_mode_feature 3
      #  end
      #  manipulate_window(21) { |err, data|
      #    return if err
      #    @_original_title = data.text
      #  }
      # end

      # Listen for keys/mouse on input
      # if (@tput.input._our_input == 0)
      #  @tput.input._out_input = 1
      listen_keys
      # listen_mouse # TODO
      # else
      #  @tput.input._our_input += 1
      # end

      # TODO Do this if it's possible to get resize events on individual IOs.
      # Listen for resize on output
      # if (@output._our_output==0)
      #  @output._our_output = 1
      #  listen_output
      # else
      #  @output._our_output += 1
      # end
    end

    # Starts emitting `Event::KeyPress` events on key presses.
    #
    # Keys are listened for in a separate `Fiber`. There should be at most 1.
    def listen_keys
      @mutex.synchronize {
        return if @fibers.keys
        @fibers.keys = spawn {
          tput.listen do |char, key, sequence|
            emit Crysterm::Event::KeyPress.new char, key, sequence
          end
        }
      }
    end

    # Destroys current `Display`.
    def destroy
      @mutex.synchronize do
        Screen.instances.select(&.display.==(self)).each do |s|
          # s.leave # No need, done as part of Screen#destroy
          s.destroy
        end

        super

        # TODO Don't do this unconditionally, but return to whatever
        # state it was in before.
        @input.try { |i|
          if i.responds_to? :"cooked!"
            i.cooked!
          end
        }
      end
    end
  end
end
