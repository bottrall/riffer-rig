# frozen_string_literal: true

class Riffer::Rig::Terminal::LineEditor
  CONTROLS = "\u0000-\u001f\u007f-\u009f" #: String

  # C1 has no pictures of its own: tr pads the set with its last character.
  CONTROL_PICTURES = '␀-␟␡␦' #: String

  ELIDE_FROM = 1000 #: Integer

  WORD = /[[:alnum:]]/ #: Regexp

  # @rbs @recall: Integer
  # @rbs @draft: String
  # @rbs @pastes: Array[String]
  # @rbs @kill: String

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
  # @rbs kill: String
  # @rbs return: void
  def initialize(before: '', after: '', history: [], recall: history.size, draft: '', pastes: [], kill: '')
    @before = before
    @after = after
    @history = history
    @recall = recall
    @draft = draft
    @pastes = pastes
    @kill = kill
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
    when :ctrl_left, :alt_left, :alt_b then word_left
    when :ctrl_right, :alt_right, :alt_f then word_right
    when :home then with(before: '', after: text)
    when :end then with(before: text, after: '')
    when :ctrl_w then kill_before(word_before(/\S/))
    when :ctrl_u then kill_before(before)
    when :ctrl_k then after.empty? ? self : with(after: '', kill: after)
    when :ctrl_y then with(before: before + @kill)
    when :up then recall(-1)
    when :down then recall(1)
    else self
    end
  end

  # @rbs sent: String
  # @rbs return: Riffer::Rig::Terminal::LineEditor
  def submit(sent = text)
    self.class.new(history: sent.strip.empty? ? history : [*history, sent], kill: @kill)
  end

  private

  # @rbs before: String
  # @rbs after: String
  # @rbs recall: Integer
  # @rbs draft: String
  # @rbs pastes: Array[String]
  # @rbs kill: String
  # @rbs return: Riffer::Rig::Terminal::LineEditor
  def with(before: @before, after: @after, recall: @recall, draft: @draft, pastes: @pastes, kill: @kill)
    self.class.new(
      before: before, after: after, history: history, recall: recall, draft: draft, pastes: pastes, kill: kill
    )
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

  # @rbs return: Riffer::Rig::Terminal::LineEditor
  def word_left
    word = word_before(WORD)
    with(before: before.delete_suffix(word), after: word + after)
  end

  # @rbs return: Riffer::Rig::Terminal::LineEditor
  def word_right
    word = leading_word(after.grapheme_clusters, WORD).join
    with(before: before + word, after: after.delete_prefix(word))
  end

  # @rbs killed: String
  # @rbs return: Riffer::Rig::Terminal::LineEditor
  def kill_before(killed)
    return self if killed.empty?

    with(before: before.delete_suffix(killed), kill: killed)
  end

  # @rbs pattern: Regexp
  # @rbs return: String
  def word_before(pattern)
    leading_word(before.grapheme_clusters.reverse, pattern).reverse.join
  end

  # @rbs clusters: Array[String]
  # @rbs pattern: Regexp
  # @rbs return: Array[String]
  def leading_word(clusters, pattern)
    gap = clusters.take_while { |cluster| !cluster.match?(pattern) }
    gap + clusters.drop(gap.size).take_while { |cluster| cluster.match?(pattern) }
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
