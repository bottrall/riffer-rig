# frozen_string_literal: true

class Riffer::Rig::Terminal::Markdown::Span
  # @dynamic text, styles, url
  attr_reader :text #: String
  attr_reader :styles #: Array[Symbol]
  attr_reader :url #: String?

  # @rbs text: String
  # @rbs styles: Array[Symbol]
  # @rbs url: String?
  # @rbs return: void
  def initialize(text:, styles: [], url: nil)
    @text = text
    @styles = styles
    @url = url
    freeze
  end

  # @rbs other: Riffer::Rig::Terminal::Markdown::Span
  # @rbs return: bool
  def same_style?(other)
    styles == other.styles && url == other.url
  end
end
