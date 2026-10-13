# frozen_string_literal: true

class Riffer::Rig::Terminal::Host
  CAPABILITIES = Set[:ask, :confirm, :notify, :progress].freeze #: Set[Symbol]

  # @rbs @prompter: Riffer::Rig::Terminal::_Prompter
  # @rbs @renderer: Riffer::Rig::Terminal::Renderer
  # @rbs @animator: Riffer::Rig::Terminal::Animator

  # @rbs prompter: Riffer::Rig::Terminal::_Prompter
  # @rbs renderer: Riffer::Rig::Terminal::Renderer
  # @rbs animator: Riffer::Rig::Terminal::Animator
  # @rbs return: void
  def initialize(prompter:, renderer:, animator:)
    @prompter = prompter
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
    answer = @prompter.ask(question, options: options, secret: secret)
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

  # @rbs answer: String
  # @rbs options: Array[String]?
  # @rbs return: String
  def choice(answer, options)
    return answer unless options && answer.match?(/\A[1-9]\d*\z/)

    options[answer.to_i - 1] || answer
  end
end
