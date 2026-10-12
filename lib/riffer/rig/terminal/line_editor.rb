# frozen_string_literal: true

class Riffer::Rig::Terminal::LineEditor
  CONTROLS = "\u0000-\u001f\u007f-\u009f" #: String

  # C1 has no pictures of its own: tr pads the set with its last character.
  CONTROL_PICTURES = '␀-␟␡␦' #: String

  # @rbs @recall: Integer
  # @rbs @draft: String

  # @dynamic before, after, history
  attr_reader :before #: String
  attr_reader :after #: String
  attr_reader :history #: Array[String]

  # @rbs before: String
  # @rbs after: String
  # @rbs history: Array[String]
  # @rbs recall: Integer
  # @rbs draft: String
  # @rbs return: void
  def initialize(before: '', after: '', history: [], recall: history.size, draft: '')
    @before = before
    @after = after
    @history = history
    @recall = recall
    @draft = draft
    freeze
  end

  # @rbs return: String
  def text
    before + after
  end

  # @rbs return: String
  def printable_before
    before.tr(CONTROLS, CONTROL_PICTURES)
  end

  # @rbs return: String
  def printable_after
    after.tr(CONTROLS, CONTROL_PICTURES)
  end

  # @rbs key: Riffer::Rig::Terminal::Key
  # @rbs return: Riffer::Rig::Terminal::LineEditor
  def press(key)
    case key.name
    when :text, :paste then with(before: before + key.text.to_s)
    when :backspace then with(before: before.sub(/\X\z/, ''))
    when :delete then with(after: after.sub(/\A\X/, ''))
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
  # @rbs return: Riffer::Rig::Terminal::LineEditor
  def with(before: @before, after: @after, recall: @recall, draft: @draft)
    self.class.new(before: before, after: after, history: history, recall: recall, draft: draft)
  end

  # @rbs return: Riffer::Rig::Terminal::LineEditor
  def left
    cluster = before[/\X\z/].to_s
    with(before: before.delete_suffix(cluster), after: cluster + after)
  end

  # @rbs return: Riffer::Rig::Terminal::LineEditor
  def right
    cluster = after[/\A\X/].to_s
    with(before: before + cluster, after: after.delete_prefix(cluster))
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
