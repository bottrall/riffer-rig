# frozen_string_literal: true

class Riffer::Rig::Terminal::LineEditor
  CONTROLS = "\u0000-\u001f\u007f-\u009f" #: String

  # C1 has no pictures of its own: tr pads the set with its last character.
  CONTROL_PICTURES = '␀-␟␡␦' #: String

  ELIDE_FROM = 1000 #: Integer

  # @rbs @recall: Integer
  # @rbs @draft: String
  # @rbs @pastes: Array[String]

  # @dynamic before, after, history
  attr_reader :before #: String
  attr_reader :after #: String
  attr_reader :history #: Array[String]

  # @rbs before: String
  # @rbs after: String
  # @rbs history: Array[String]
  # @rbs recall: Integer
  # @rbs draft: String
  # @rbs pastes: Array[String]
  # @rbs return: void
  def initialize(before: '', after: '', history: [], recall: history.size, draft: '', pastes: [])
    @before = before
    @after = after
    @history = history
    @recall = recall
    @draft = draft
    @pastes = pastes
    freeze
  end

  # @rbs return: String
  def text
    before + after
  end

  # @rbs return: String
  def printable_before
    printable(before)
  end

  # @rbs return: String
  def printable_after
    printable(after)
  end

  # @rbs key: Riffer::Rig::Terminal::Key
  # @rbs return: Riffer::Rig::Terminal::LineEditor
  def press(key)
    case key.name
    when :text then with(before: before + key.text.to_s)
    when :paste then paste(key.text.to_s)
    when :backspace then with(before: before.delete_suffix(unit_before))
    when :delete then with(after: after.delete_prefix(unit_after))
    when :left then left
    when :right then right
    when :home then with(before: '', after: text)
    when :end then with(before: text, after: '')
    when :up then recall(-1)
    when :down then recall(1)
    else self
    end
  end

  # @rbs return: Riffer::Rig::Terminal::LineEditor
  def submit
    self.class.new(history: text.strip.empty? ? history : [*history, text])
  end

  private

  # @rbs before: String
  # @rbs after: String
  # @rbs recall: Integer
  # @rbs draft: String
  # @rbs pastes: Array[String]
  # @rbs return: Riffer::Rig::Terminal::LineEditor
  def with(before: @before, after: @after, recall: @recall, draft: @draft, pastes: @pastes)
    self.class.new(before: before, after: after, history: history, recall: recall, draft: draft, pastes: pastes)
  end

  # @rbs text: String
  # @rbs return: String
  def printable(text)
    text.gsub(Regexp.union(@pastes)) { |paste| format('[pasted %.1fk chars]', paste.size / 1000.0) }
        .tr(CONTROLS, CONTROL_PICTURES)
  end

  # @rbs text: String
  # @rbs return: Riffer::Rig::Terminal::LineEditor
  def paste(text)
    return with(before: before + text) if text.size < ELIDE_FROM

    # Longest first, so a paste that begins with an earlier one elides whole.
    with(before: before + text, pastes: (@pastes | [text]).sort_by { |elided| -elided.size })
  end

  # @rbs return: String
  def unit_before
    @pastes.find { |elided| before.end_with?(elided) } || before[/\X\z/].to_s
  end

  # @rbs return: String
  def unit_after
    @pastes.find { |elided| after.start_with?(elided) } || after[/\A\X/].to_s
  end

  # @rbs return: Riffer::Rig::Terminal::LineEditor
  def left
    unit = unit_before
    with(before: before.delete_suffix(unit), after: unit + after)
  end

  # @rbs return: Riffer::Rig::Terminal::LineEditor
  def right
    unit = unit_after
    with(before: before + unit, after: after.delete_prefix(unit))
  end

  # @rbs step: Integer
  # @rbs return: Riffer::Rig::Terminal::LineEditor
  def recall(step)
    target = @recall + step
    return self unless target.between?(0, history.size)

    draft = @recall == history.size ? text : @draft
    with(before: history.fetch(target, draft), after: '', recall: target, draft: draft)
  end
end
