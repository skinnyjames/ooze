require_relative "./screen"

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
    panel { @keypress="on_keypress" background="94,163,39"}
      screen { :width="width" :size="size"  }
  EOF

  uses(
    panel: Hokusai::Blocks::Panel,
    screen: Ooze::UI::Screen,
  )

  provide :session, :session
  provide :new_runs, :new_runs
  computed :size, default: 15, convert: proc(&:to_i)

  attr_accessor :rows, :cols, :width

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

  def clear_new_scrollback
    new_runs.clear
  end

  def new_runs
    @new_runs ||= []
  end

  def session
    return unless rows && cols

    @session ||= begin
      shell = ENV["SHELL"] || "bash"
      pty = PTY.spawn(shell, rows, cols)
      pty.set_size(rows, cols, 0, 0)
      session = Ooze::Terminal::Session.new(pty)
      session.screen.on_evicted do |runs|
        new_runs.concat runs
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

  def initialize(**args)
    super
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