# frozen_string_literal: true

require 'json'

class Riffer::Rig::UI::Renderer
  RESULT_PREVIEW_LIMIT = 200 #: Integer

  # @rbs @io: untyped
  # @rbs @theme: Riffer::Rig::UI::Theme
  # @rbs @tally: Riffer::Rig::TokenTally?
  # @rbs @smoother: Riffer::Rig::UI::Smoother | PassThroughSmoother?

  # @rbs io: untyped
  # @rbs ?theme: Riffer::Rig::UI::Theme
  # @rbs ?tally: Riffer::Rig::TokenTally?
  # @rbs ?smoother: Riffer::Rig::UI::Smoother | PassThroughSmoother?
  # @rbs return: void
  def initialize(io: $stdout, theme: Riffer::Rig::UI::Theme.for(io), tally: nil, smoother: nil)
    @io = io
    @theme = theme
    @tally = tally
    @smoother = smoother
  end

  # @rbs event: Riffer::StreamEvents::Base
  # @rbs return: void
  def render(event)
    case event
    when Riffer::StreamEvents::TextDelta
      smoother << event.content
    when Riffer::StreamEvents::ToolCallDone
      render_block(2) { @theme.cyan("⚙ #{event.name}(#{format_arguments(event.arguments)})") }
    when Riffer::StreamEvents::SkillActivation
      render_block(0) { @theme.magenta("✦ skill: #{event.name}") }
    when Riffer::StreamEvents::Interrupt
      render_block(0) { @theme.dim("[interrupted: #{event.reason}]") }
    when Riffer::StreamEvents::TokenUsageDone
      render_token_usage(event.token_usage)
    end
  end

  # @rbs message: Riffer::Messages::Base
  # @rbs return: void
  def render_tool_result(message)
    return unless message.is_a?(Riffer::Messages::Tool)

    line = "↳ #{preview(message.content)}"
    render_block(4) { message.error? ? @theme.red(line) : @theme.dim(line) }
  end

  private

  # Every non-prose block goes through here so spacing comes from the rule, not
  # from each render site. Blank line above, indented content, newline below;
  # the smoother is drained first so a pending partial prose block ends cleanly.
  #
  # @rbs indent: Integer
  # @rbs return: void
  def render_block(indent, &)
    drain_smoother
    @io.puts
    @io.puts((' ' * indent) + yield)
    @io.flush
  end

  # @rbs return: Riffer::Rig::UI::Smoother | PassThroughSmoother
  def smoother
    @smoother || PassThroughSmoother.new(@io)
  end

  # Stand-in when no smoother is injected, so a bare Riffer::Rig::UI::Renderer still prints
  # synchronously.
  class PassThroughSmoother
    # @rbs @io: untyped

    # @rbs io: untyped
    # @rbs return: void
    def initialize(io) = @io = io

    # @rbs content: String
    # @rbs return: self
    def <<(content)
      @io.print(content)
      @io.flush
      self
    end

    # @rbs return: nil
    def drain = nil

    # @rbs return: nil
    def finish = nil
  end

  # @rbs return: void
  def drain_smoother
    smoother.drain
  end

  # @rbs usage: Riffer::Providers::TokenUsage
  # @rbs return: void
  def render_token_usage(usage)
    tally = @tally
    return unless tally

    tally.add(usage)

    parts = ["↑#{usage.input_tokens}", "↓#{usage.output_tokens}"]
    parts << "cache_write:#{usage.cache_write_tokens}" if usage.cache_write_tokens&.positive?
    parts << "cache_read:#{usage.cache_read_tokens}" if usage.cache_read_tokens&.positive?
    parts << "session #{tally.total_tokens} tok"
    cost = tally.estimated_cost
    parts << format('~$%.4f', cost) if cost

    render_block(0) { @theme.dim(parts.join(' · ')) }
  end

  # @rbs arguments: String
  # @rbs return: String
  def format_arguments(arguments)
    parsed = JSON.parse(arguments)
    parsed.map { |key, value| "#{key}: #{value.inspect}" }.join(', ')
  rescue JSON::ParserError
    arguments
  end

  # @rbs content: String
  # @rbs return: String
  def preview(content)
    first_line = content.to_s.lines.first.to_s.chomp
    return first_line if first_line.length <= RESULT_PREVIEW_LIMIT

    "#{first_line[0, RESULT_PREVIEW_LIMIT]}…"
  end
end
