require_relative "./screen"

class Ooze::UI::PluginResponse
  def initialize(on_reply, on_cancel)
    @on_reply = on_reply
    @on_cancel = on_cancel
  end

  def reply(data)
    @on_reply.call(data)
  end

  def cancel
    @on_cancel.call
  end
end

class Ooze::UI::Container < Hokusai::Block
  template <<-EOF
  [template]
    virtual
  EOF

  computed! :block

  def initialize(**args)
    super

    node.meta.set_child(0, block)
  end
end

class Ooze::UI::Session < Hokusai::Block
  style <<-EOF
  [style]
  scrollback {
    selection_color: rgb(220, 149, 149);
    selection_color_to: rgb(144, 94, 153);
    animate_selection: true;
  }
  EOF
  
  template <<-EOF
  [template]
    vblock
      [if="plugin"]
        container { :block="plugin" }
      [else]
        panel { @keypress="on_keypress" background="94,163,39"}
          screen { :width="width" :size="size"  }
  EOF

  uses(
    vblock: Hokusai::Blocks::Vblock,
    panel: Hokusai::Blocks::Panel,
    screen: Ooze::UI::Screen,
    container: Ooze::UI::Container,
  )

  provide :session, :session
  provide :new_runs, :new_runs
  computed :size, default: 15, convert: proc(&:to_i)

  attr_accessor :rows, :cols, :width, :plugin

  HOKUSAI_TO_INPUT = {
    kp_0: :kp0, kp_1: :kp1, kp_2: :kp2, kp_3: :kp3, kp_4: :kp4,
    kp_5: :kp5, kp_6: :kp6, kp_7: :kp7, kp_8: :kp8, kp_9: :kp9,
    kp_decimal: :kpperiod, kp_subtract: :kpminus, kp_enter: :kpenter,
    kp_divide: :kpdivide, kp_multiply: :kpmultiply, kp_add: :kpadd, kp_equal: :kpequal,
  }.freeze

  def compute_size(canvas)
    w, _ = Hokusai.fonts.get("default").measure_char("A", size)

    @width = w
    @cols = (canvas.width / w).floor
    @rows = (canvas.height / size).floor
  end

  def initialize(**args)
    @plugin = nil

    super
  end

  def clear_new_scrollback
    new_runs.clear
  end

  def new_runs
    @new_runs ||= []
  end

  def session
    return unless rows && cols

    @session ||= begin
      session = Ooze::Terminal::Session.spawn(rows, cols)
      session.screen.on_evicted do |runs|
        new_runs.concat runs
      end

      session.on_plugin do |command, id, *args|
        case command
        when :start
          plugin_name, cwd, on_reply, on_cancel = args
          response = Ooze::UI::PluginResponse.new(on_reply, on_cancel)
          if plugin_class = Ooze.plugins[plugin_name]
            self.plugin = plugin_class.mount("root", nil, providers: { response: ->() {response} })
            plugin.on_start(cwd.strip) if plugin.respond_to?(:on_start)
          else
            on_cancel.call
          end
        when :data
          plugin&.on_data(args[0]) if plugin&.respond_to?(:on_data)
        when :done
          id = args[0]
          plugin&.on_data_complete if plugin&.respond_to?(:on_data_complete)
        when :closed
          self.plugin = nil
        when :cancel
          plugin&.on_cancel if plugin&.respond_to?(:on_cancel)
          self.plugin = nil
        when :error
          plugin&.on_error if plugin&.respond_to?(:on_error)
        end
      end

      session
    end
  end

  def before_updated
    session.read
  end

  def after_updated
    if session.pty.exited?
      Hokusai.close_window
    end
  end

  def pack(seq)
    seq.pack("U*")
  end

  def on_keypress(event)
    return if session.modes[:kam]

    if event.symbol == :v && (event.super || event.ctrl) && (content = Hokusai.paste)
      session.input.paste(content)
      return
    end
  
    modifiers = {
      control: event.ctrl,
      shift: event.shift,
      alt: event.alt
    }

    if event.printable?
      session.input.print(event.char, modifiers)
    else
      key = HOKUSAI_TO_INPUT.fetch(event.symbol, event.symbol)
      session.input.keypress(key, modifiers)
    end
  end

  def render(canvas)
    compute_size(canvas) if rows.nil? || cols.nil?

    yield canvas
  end
end