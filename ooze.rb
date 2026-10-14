require_relative "./ooze/patches/keyboard"
require_relative "./ooze/terminal"
require_relative "./ooze/ui"
require_relative "./patches/resolver"

PLUGIN_PATH = ENV["OOZE_PLUGIN_PATH"] || "assets/plugins"

module Ooze
  def self.register_plugin(name, block)
    if plugins[name]
      puts "Ooze Plugin: #{name} is already registered"
    else
      plugins[name] = block
    end
  end

  def self.plugins
    @plugins ||= {}
  end

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

Dir.glob("#{PLUGIN_PATH}/*").each do |dir|
  if File.exist?("#{dir}/manifest.rb")
    eval ruby_file("#{dir}/manifest.rb")
  else
    puts "Warning: Plugin #{dir} is not a Ooze plugin"
  end
end

Hokusai::Backend.run(Ooze::App) do |config|
  config.title = "Ooze"
  config.width = 600
  config.height = 500
  config.draw_fps = true if ENV["OOZE_DRAW_FPS"]
  config.after_load do
    Hokusai.fonts.register "default", Hokusai::Backend::Font.from_ext("assets/DejaVu.ttf", 30)
    Hokusai.fonts.activate "default"
  end
end