# frozen_string_literal: true

class Riffer::Rig::Terminal::Autocomplete
  TRIGGER = '/'

  QUERY = %r{\A/(\S*)\z} #: Regexp

  # @rbs @commands: Array[_Command]
  # @rbs @index: Integer
  # @rbs @dismissed: bool

  # @dynamic editor, matches
  attr_reader :editor #: Riffer::Rig::Terminal::LineEditor
  attr_reader :matches #: Array[_Command]

  # @rbs commands: Array[_Command]
  # @rbs editor: Riffer::Rig::Terminal::LineEditor
  # @rbs index: Integer
  # @rbs dismissed: bool
  # @rbs return: void
  def initialize(commands:, editor: Riffer::Rig::Terminal::LineEditor.new, index: 0, dismissed: false)
    @commands = commands
    @editor = editor
    @index = index
    @dismissed = dismissed
    @matches = dismissed ? [] : ranked(editor.text[QUERY, 1])
    freeze
  end

  # @rbs return: bool
  def open?
    matches.any?
  end

  # @rbs return: _Command?
  def selected
    matches[@index]
  end

  # @rbs return: String
  def ghost
    name = selected&.name
    typed = editor.text.delete_prefix(TRIGGER)
    return '' unless name && editor.after.empty? && name.downcase.start_with?(typed.downcase)

    name[typed.length..].to_s
  end

  # @rbs key: Riffer::Rig::Terminal::Key
  # @rbs return: Riffer::Rig::Terminal::Autocomplete
  def press(key)
    return edit(key) unless open?

    case key.name
    when :up then with(index: (@index - 1) % matches.size)
    when :down then with(index: (@index + 1) % matches.size)
    when :tab then accept
    when :right then editor.after.empty? ? accept : edit(key)
    when :escape then with(dismissed: true)
    else edit(key)
    end
  end

  # @rbs return: Riffer::Rig::Terminal::Autocomplete
  def submit
    self.class.new(commands: @commands, editor: editor.submit)
  end

  private

  # @rbs editor: Riffer::Rig::Terminal::LineEditor
  # @rbs index: Integer
  # @rbs dismissed: bool
  # @rbs return: Riffer::Rig::Terminal::Autocomplete
  def with(editor: @editor, index: @index, dismissed: @dismissed)
    self.class.new(commands: @commands, editor: editor, index: index, dismissed: dismissed)
  end

  # @rbs query: String?
  # @rbs return: Array[_Command]
  def ranked(query)
    return [] unless query

    fuzzy = Regexp.new(query.chars.map { |char| Regexp.escape(char) }.join('.*'), Regexp::IGNORECASE)
    @commands.select { |command| command.name.match?(fuzzy) }
             .sort_by(&:name)
             .partition { |command| command.name.downcase.start_with?(query.downcase) }
             .flatten
  end

  # @rbs key: Riffer::Rig::Terminal::Key
  # @rbs return: Riffer::Rig::Terminal::Autocomplete
  def edit(key)
    pressed = editor.press(key)
    changed = pressed.text != editor.text
    recalled = changed && %i[up down].include?(key.name)
    with(
      editor: pressed,
      index: changed ? 0 : @index,
      dismissed: (@dismissed || recalled) && pressed.text.start_with?(TRIGGER)
    )
  end

  # @rbs return: Riffer::Rig::Terminal::Autocomplete
  def accept
    accepted = "#{TRIGGER}#{matches.fetch(@index).name} "
    with(editor: Riffer::Rig::Terminal::LineEditor.new(before: accepted, history: editor.history))
  end
end
