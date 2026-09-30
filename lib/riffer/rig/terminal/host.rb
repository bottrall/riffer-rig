# frozen_string_literal: true

require 'io/console'

class Riffer::Rig::Hosts::Terminal
  CAPABILITIES = Set[:ask, :confirm, :notify, :progress].freeze #: Set[Symbol]

  # @rbs @input: IO
  # @rbs @renderer: Riffer::Rig::Terminal::Renderer
  # @rbs @animator: Riffer::Rig::Terminal::Animator

  # @rbs input: IO
  # @rbs renderer: Riffer::Rig::Terminal::Renderer
  # @rbs animator: Riffer::Rig::Terminal::Animator
  # @rbs return: void
  def initialize(input:, renderer:, animator:)
    @input = input
    @renderer = renderer
    @animator = animator
  end

  # @rbs return: Set[Symbol]
  def capabilities
    CAPABILITIES
  end

  # @rbs question: String?
  # @rbs options: Array[String]?
  # @rbs secret: bool
  # @rbs return: String?
  def ask(question = nil, options: nil, secret: false)
    @animator.stop
    @renderer.question(question, options, secret)
    answer = secret ? read_secret : @input.gets
    return nil if answer.nil?

    choice(answer.strip, options)
  end

  # @rbs question: String?
  # @rbs return: bool
  def confirm(question = nil)
    ask("#{question} [y/N]").to_s.downcase.start_with?('y')
  end

  # @rbs message: String?
  # @rbs level: Symbol
  # @rbs return: void
  def notify(message = nil, level: :info)
    @animator.stop
    @renderer.notify(message.to_s, level)
  end

  # @rbs label: String?
  # @rbs &block: ? () -> void
  # @rbs return: void
  def progress(label = nil, &block)
    @renderer.notice(label) if label
    @animator.start
    block&.call
  ensure
    @animator.stop
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

  # @rbs answer: String
  # @rbs options: Array[String]?
  # @rbs return: String
  def choice(answer, options)
    return answer unless options && answer.match?(/\A[1-9]\d*\z/)

    options[answer.to_i - 1] || answer
  end
end
