# frozen_string_literal: true

class Riffer::Rig::Terminal::KeyDecoder
  ESCAPE = "\e" #: String

  CSI_KEYS = {
    'A' => :up, 'B' => :down, 'C' => :right, 'D' => :left,
    'H' => :home, 'F' => :end, 'Z' => :shift_tab
  }.freeze #: Hash[String, Symbol]

  MODIFIED_CSI_KEYS = {
    '3C' => :alt_right, '3D' => :alt_left, '5C' => :ctrl_right, '5D' => :ctrl_left
  }.freeze #: Hash[String, Symbol]

  META_KEYS = { 'b' => :alt_b, 'f' => :alt_f }.freeze #: Hash[String, Symbol]

  TILDE_KEYS = {
    '1' => :home, '2' => :insert, '3' => :delete, '4' => :end,
    '5' => :page_up, '6' => :page_down, '7' => :home, '8' => :end
  }.freeze #: Hash[String, Symbol]

  PASTE_START = '200' #: String

  PASTE_END = "\e[201~" #: String

  MAX_CHARACTER_BYTES = 4 #: Integer

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

  # @rbs byte: Integer
  # @rbs return: Array[Riffer::Rig::Terminal::Key]
  def push(byte)
    char = byte.chr
    case @state
    when :escape then escape(char)
    when :csi then csi(char)
    when :ss3 then ss3(char)
    when :paste then paste(char)
    when :character then continuation(char)
    else ground(char)
    end
  end

  # @rbs return: Array[Riffer::Rig::Terminal::Key]
  def flush
    # An idle gap inside a paste must not end it: the rest would decode as
    # keystrokes, and its newlines would submit.
    return [] if @state == :paste

    events = case @state
             when :escape then [Riffer::Rig::Terminal::Key.new(:escape)]
             when :character then stray
             else [] #: Array[Riffer::Rig::Terminal::Key]
             end
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
    return character(char) unless char.ascii_only?

    chord = ctrl_chord(char)
    return [Riffer::Rig::Terminal::Key.new(chord)] if chord
    return [] if char.ord < 0x20

    [Riffer::Rig::Terminal::Key.new(:text, char.encode(Encoding::UTF_8))]
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
  def continuation(char)
    char.ord.between?(0x80, 0xbf) ? character(char) : flush + ground(char)
  end

  # @rbs char: String
  # @rbs return: Array[Riffer::Rig::Terminal::Key]
  def character(char)
    @state = :character
    @sequence << char
    text = @sequence.dup.force_encoding(Encoding::UTF_8)
    if text.valid_encoding?
      @state = :ground
      @sequence = +''
      return [Riffer::Rig::Terminal::Key.new(:text, text)]
    end

    @sequence.bytesize < MAX_CHARACTER_BYTES ? [] : flush
  end

  # @rbs return: Array[Riffer::Rig::Terminal::Key]
  def stray
    return [] unless @sequence.bytesize == 1

    # xterm's 8-bit meta input sends Alt with a key as that key's byte with the
    # high bit set, a byte UTF-8 cannot carry on its own.
    name = META_KEYS.fetch((@sequence.b.ord & 0x7f).chr, nil)
    name ? [Riffer::Rig::Terminal::Key.new(name)] : []
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
      name = META_KEYS.fetch(char, nil)
      name ? [Riffer::Rig::Terminal::Key.new(name)] : [Riffer::Rig::Terminal::Key.new(:escape), *ground(char)]
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
      return ground(char)
    end

    @sequence << char
    []
  end

  # @rbs final: String
  # @rbs return: Array[Riffer::Rig::Terminal::Key]
  def finish_csi(final)
    @state = :ground
    param, modifier = @sequence.split(/[;<]/)
    @sequence = +''
    if final == '~'
      if param == PASTE_START
        @state = :paste
        return []
      end

      name = param ? TILDE_KEYS[param] : nil
    else
      name = MODIFIED_CSI_KEYS.fetch("#{modifier}#{final}") { CSI_KEYS[final] }
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

    # Terminals send a pasted line break as a carriage return.
    text = @sequence.delete_suffix(PASTE_END).force_encoding(Encoding::UTF_8).scrub('').gsub(/\r\n?/, "\n")
    @state = :ground
    @sequence = +''
    [Riffer::Rig::Terminal::Key.new(:paste, text)]
  end
end
