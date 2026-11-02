class Ooze::UI::Screen < Hokusai::Block
  template <<-EOF
  [template]
    empty
  EOF

  uses(empty: Hokusai::Blocks::Empty)
  
  computed :size, default: 18, convert: proc(&:to_i)
  computed :width, default: 18, convert: proc(&:to_f)
  computed :color, default: Hokusai::Color.new(222,222,222), convert: Hokusai::Color

  inject :palette
  inject :session
  inject :panel_height

  def cursor(canvas)
    cursor = session.screen.cursor

    x = canvas.x + [cursor.col, screen.cols - 1].min * width
    y = canvas.y + cursor.row * size
  
    [x, y]
  end

  def screen
    session.screen
  end

  def dirty?
    session.screen.lines.any?(&:dirty)
  end

  def render(canvas)
    @command_cache ||= []

    unless dirty?
      node.meta.commands.queue.concat  @command_cache
      yield canvas

      return
    end

    @command_cache.clear

    node.meta.set_prop(:height, panel_height)
    x = canvas.x
    y = canvas.y

    draw do
      screen&.runs do |payload|
        if payload == :newline
          y += size
          x = canvas.x
          next
        end

        content, style = payload

        text(content, x, y) do |command|
          command.color = style.foreground(palette) || color
          command.size = size

          @command_cache << command
        end

        # handle wide chars
        content_width = width * content.width(session.ambiguous_width)

        if style.underline
          rect(x, y + size, content_width, 1.0) do |command|
            command.color = Hokusai::Color.new(222,22,22)

            @command_cache << command
          end
        end

        # advance x
        x += content_width
      end

      # draw cursor
      cx, cy = cursor(canvas)
      rect(cx, cy, 1.0, size) do |command|
        command.color = Hokusai::Color.new(222, 22, 22)
        
        @command_cache << command
      end
    end
  end
end