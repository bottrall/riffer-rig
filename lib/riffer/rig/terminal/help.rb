# frozen_string_literal: true

module Riffer::Rig::Terminal::Help
  extend self

  POINTER = "In the terminal, typing / opens a palette of these; the input line's keys are at " \
            'https://riffer.bottrall.dev/guides/terminal/' #: String

  # @rbs commands: Array[Riffer::Rig::Terminal::Autocomplete::_Entry]
  # @rbs return: String
  def call(commands)
    sorted = commands.sort_by(&:name)
    width = width(sorted)
    # The notice's wrap hangs a long description under its column only after
    # a gap of at least two spaces, and only while the names fill less than
    # half the line.
    rows = sorted.map { |command| "#{label(command, width)}  #{about(command)}" }
    [*rows, '', POINTER].join("\n")
  end

  # @rbs commands: Array[Riffer::Rig::Terminal::Autocomplete::_Entry]
  # @rbs return: Integer
  def width(commands)
    commands.map { |command| Riffer::Rig::Terminal::Columns.width(command.name) }.max.to_i
  end

  # @rbs command: Riffer::Rig::Terminal::Autocomplete::_Entry
  # @rbs width: Integer
  # @rbs return: String
  def label(command, width)
    padding = ' ' * (width - Riffer::Rig::Terminal::Columns.width(command.name))
    "#{Riffer::Rig::Terminal::Autocomplete::TRIGGER}#{command.name}#{padding}"
  end

  # @rbs command: Riffer::Rig::Terminal::Autocomplete::_Entry
  # @rbs return: String
  def about(command)
    # A line break in a description would split its row in two.
    command.description.gsub(/[[:cntrl:]]+/, ' ').strip
  end
end
