# frozen_string_literal: true

class Riffer::Rig::Terminal::KeyDecoder
  ESCAPE = "\e" #: String

  CSI_KEYS = {
    'A' => :up, 'B' => :down, 'C' => :right, 'D' => :left,
    'H' => :home, 'F' => :end, 'Z' => :shift_tab
  }.freeze #: Hash[String, Symbol]

  TILDE_KEYS = {
    '1' => :home, '2' => :insert, '3' => :delete, '4' => :end,
    '5' => :page_up, '6' => :page_down, '7' => :home, '8' => :end
  }.freeze #: Hash[String, Symbol]

  PASTE_START = '200' #: String

  PASTE_END = "\e[201~" #: String

  # @rbs @state: Symbol
  # @rbs @sequence: String

  # @rbs return: void
  def initialize
    @state = :ground
    @sequence = +''
  end

  # @rbs return: bool
  def pending?
    @state != :ground
  end

  # @rbs char: String
  # @rbs return: Array[Riffer::Rig::Terminal::Key]
  def push(char)
    case @state
    when :escape then escape(char)
    when :csi then csi(char)
    when :ss3 then ss3(char)
    when :paste then paste(char)
    else ground(char)
    end
  end

  # @rbs return: Array[Riffer::Rig::Terminal::Key]
  def flush
    events = [] #: Array[Riffer::Rig::Terminal::Key]
    events << Riffer::Rig::Terminal::Key.new(:escape) if @state == :escape
    events << Riffer::Rig::Terminal::Key.new(:text, @sequence) if @state == :paste && !@sequence.empty?
    @state = :ground
    @sequence = +''
    events
  end

  private

  # @rbs char: String
  # @rbs return: Array[Riffer::Rig::Terminal::Key]
  def ground(char)
    case char
    when ESCAPE
      @state = :escape
      []
    when "\r", "\n"
      [Riffer::Rig::Terminal::Key.new(:enter)]
    when "\t"
      [Riffer::Rig::Terminal::Key.new(:tab)]
    when "\x7f", "\x08"
      [Riffer::Rig::Terminal::Key.new(:backspace)]
    else
      ground_other(char)
    end
  end

  # @rbs char: String
  # @rbs return: Array[Riffer::Rig::Terminal::Key]
  def ground_other(char)
    chord = ctrl_chord(char)
    return [Riffer::Rig::Terminal::Key.new(chord)] if chord
    return [] if char.ord < 0x20

    [Riffer::Rig::Terminal::Key.new(:text, char)]
  end

  # @rbs char: String
  # @rbs return: Symbol?
  def ctrl_chord(char)
    code = char.ord
    return unless code.between?(1, 26)

    :"ctrl_#{(code + 96).chr}"
  end

  # @rbs char: String
  # @rbs return: Array[Riffer::Rig::Terminal::Key]
  def escape(char)
    case char
    when '['
      @state = :csi
      @sequence = +''
      []
    when 'O'
      @state = :ss3
      []
    else
      @state = :ground
      [Riffer::Rig::Terminal::Key.new(:escape), *ground(char)]
    end
  end

  # @rbs char: String
  # @rbs return: Array[Riffer::Rig::Terminal::Key]
  def csi(char)
    code = char.ord
    return finish_csi(char) if code.between?(0x40, 0x7e)

    if code < 0x20
      # A control byte aborts an unterminated sequence; a fresh ESC restarts.
      @state = :ground
      @sequence = +''
      return push(char)
    end

    @sequence << char
    []
  end

  # @rbs final: String
  # @rbs return: Array[Riffer::Rig::Terminal::Key]
  def finish_csi(final)
    @state = :ground
    # stdlib types Array#first as non-nil, but an empty sequence yields nil.
    # @type var param: String?
    param = @sequence.split(/[;<]/).first
    @sequence = +''
    if final == '~'
      if param == PASTE_START
        @state = :paste
        return []
      end

      name = param ? TILDE_KEYS[param] : nil
    else
      name = CSI_KEYS[final]
    end
    name ? [Riffer::Rig::Terminal::Key.new(name)] : []
  end

  # @rbs char: String
  # @rbs return: Array[Riffer::Rig::Terminal::Key]
  def ss3(char)
    @state = :ground
    # @type var name: Symbol?
    name = CSI_KEYS[char]
    name ? [Riffer::Rig::Terminal::Key.new(name)] : []
  end

  # @rbs char: String
  # @rbs return: Array[Riffer::Rig::Terminal::Key]
  def paste(char)
    @sequence << char
    return [] unless @sequence.end_with?(PASTE_END)

    text = @sequence.delete_suffix(PASTE_END)
    @state = :ground
    @sequence = +''
    [Riffer::Rig::Terminal::Key.new(:paste, text)]
  end
end
