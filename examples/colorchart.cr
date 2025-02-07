require "../src/crysterm"

include Crysterm

def draw(s : Screen)
  8.times do |x|
    8.times do |y|
      s.fill_region(Widget.sattr(Style.new, x, y), '0', x, x + 1, (y*2), (y*2) + 1)
      s.fill_region(Widget.sattr(Style.new, x + 8, y), '0', x + 8, x + 8 + 1, (y*2), (y*2) + 1)
      s.fill_region(Widget.sattr(Style.new, x, y + 8), '0', x, x + 1, (y*2) + 1, (y*2) + 2)
      s.fill_region(Widget.sattr(Style.new, x + 8, y + 8), '0', x + 8, x + 8 + 1, (y*2) + 1, (y*2) + 2)
    end
  end
end

# `Display` is a phyiscal device (terminal hardware or emulator).
# It can be instantiated manually as shown, or for quick coding it can be
# skipped and it will be created automatically when needed.
s = Screen.new

draw(s)

s.on(Event::Resize) do
  draw(s)
end

# When q is pressed, exit the demo.
s.on(Event::KeyPress) do |e|
  if e.char == 'q'
    exit
  end
end

spawn do
  loop do
    sleep 1
    s.render
  end
end

s.exec
