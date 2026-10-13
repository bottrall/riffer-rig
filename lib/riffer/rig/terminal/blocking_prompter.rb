# frozen_string_literal: true

require 'io/console'

class Riffer::Rig::Terminal::BlockingPrompter
  # @rbs @input: IO
  # @rbs @renderer: Riffer::Rig::Terminal::Renderer

  # @rbs input: IO
  # @rbs renderer: Riffer::Rig::Terminal::Renderer
  # @rbs return: void
  def initialize(input:, renderer:)
    @input = input
    @renderer = renderer
  end

  # @rbs question: String?
  # @rbs options: Array[String]?
  # @rbs secret: bool
  # @rbs return: String?
  def ask(question, options:, secret:)
    @renderer.question(question, options, secret)
    secret ? read_secret : @input.gets
  end

  private

  # @rbs return: String?
  def read_secret
    return @input.gets unless @input.tty?

    answer = @input.noecho(&:gets)
    # noecho swallows the newline the user typed along with the secret.
    @renderer.newline
    answer
  end
end
