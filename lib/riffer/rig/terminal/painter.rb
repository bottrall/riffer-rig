# frozen_string_literal: true

# @rbs generic Owner < Object
class Riffer::Rig::Terminal::Painter
  VISIBLE = /\S/ #: Regexp

  # @rbs @same: ^(Owner, Owner) -> bool

  # @rbs same: ^(Owner, Owner) -> bool
  # @rbs return: void
  def initialize(same:)
    @same = same
    freeze
  end

  # @rbs line: String
  # @rbs owners: Array[Owner]
  # @rbs &style: (String, Owner?) -> String
  # @rbs return: String
  def paint(line, owners)
    chars = line.chars
    owner_at = chars.each_index.select { |index| chars.fetch(index).match?(VISIBLE) }.zip(owners).to_h
    slots = chars.each_index.map { |index| owner_at[index] }
    cells = nearest(slots).zip(nearest(slots.reverse).reverse).map { |left, right| between(left, right) }
    runs = cells.zip(chars).chunk_while { |(left, _), (right, _)| alike?(left, right) }
    runs.map { |run| yield(run.map(&:last).join, run.fetch(0).first) }.join
  end

  private

  # @rbs slots: Array[Owner?]
  # @rbs return: Array[Owner?]
  def nearest(slots)
    slots.each_with_object([]) { |slot, filled| filled << (slot || filled.last) }
  end

  # @rbs left: Owner?
  # @rbs right: Owner?
  # @rbs return: Owner?
  def between(left, right)
    left if alike?(left, right)
  end

  # @rbs left: Owner?
  # @rbs right: Owner?
  # @rbs return: bool
  def alike?(left, right)
    return left.nil? && right.nil? unless left && right

    @same.call(left, right)
  end
end
