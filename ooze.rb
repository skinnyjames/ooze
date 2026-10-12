require_relative "./ooze/terminal"
require_relative "./ooze/patches/wrap_stream"

module Ooze
  module UI
  end
end

a = {one: 2}
a.transform_values! do |v|
  v + 1
end
p a
require_relative "./ooze/ui/session"

module Ooze
  class App < Hokusai::Block
    template <<-EOF
    [template]
      session
    EOF

    uses(session: UI::Session)

    provide :palette, :palette

    def palette
      @palette ||= Ooze::Terminal::Colors.rich_palette({black: [222,222,222]}) do |value|
        Hokusai::Color.convert(value)
      end
    end
  end
end

Hokusai::Backend.run(Ooze::App) do |config|
  config.title = "Ooze"
  config.width = 600
  config.height = 500
  config.draw_fps = true
  config.after_load do
    Hokusai.fonts.register "default", Hokusai::Backend::Font.from_ext("assets/DejaVu.ttf", 30)
    Hokusai.fonts.activate "default"
  end
end