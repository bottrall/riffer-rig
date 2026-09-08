# frozen_string_literal: true

require 'json'

class Riffer::Rig::UI::Renderer
  RESULT_PREVIEW_LIMIT = 200

  def initialize(io: $stdout, theme: Riffer::Rig::UI::Theme.for(io), tally: nil, smoother: nil)
    @io = io
    @theme = theme
    @tally = tally
    @smoother = smoother
  end

  def render(event)
    case event
    when Riffer::StreamEvents::TextDelta
      smoother << event.content
    when Riffer::StreamEvents::ToolCallDone
      drain_smoother
      @io.puts("\n#{@theme.cyan("⚙ #{event.name}(#{format_arguments(event.arguments)})")}")
    when Riffer::StreamEvents::SkillActivation
      drain_smoother
      @io.puts("\n#{@theme.magenta("✦ skill: #{event.name}")}")
    when Riffer::StreamEvents::Interrupt
      drain_smoother
      @io.puts(@theme.dim("[interrupted: #{event.reason}]"))
    when Riffer::StreamEvents::TokenUsageDone
      drain_smoother
      render_token_usage(event.token_usage)
    end
  end

  def render_tool_result(message)
    return unless message.is_a?(Riffer::Messages::Tool)

    line = "↳ #{preview(message.content)}"
    @io.puts(message.error? ? @theme.red(line) : @theme.dim(line))
  end

  private

  def smoother
    @smoother || PassThroughSmoother.new(@io)
  end

  # Stand-in when no smoother is injected, so a bare Renderer still prints
  # synchronously.
  class PassThroughSmoother
    def initialize(io) = @io = io

    def <<(content)
      @io.print(content)
      @io.flush
      self
    end

    def drain = nil

    def finish = nil
  end

  def drain_smoother
    smoother.drain
  end

  def render_token_usage(usage)
    return unless @tally

    @tally.add(usage)

    parts = ["↑#{usage.input_tokens}", "↓#{usage.output_tokens}"]
    parts << "cache_write:#{usage.cache_write_tokens}" if usage.cache_write_tokens&.positive?
    parts << "cache_read:#{usage.cache_read_tokens}" if usage.cache_read_tokens&.positive?

    session_parts = ["session #{@tally.total_tokens} tok"]
    cost = @tally.estimated_cost
    session_parts << format('~$%.4f', cost) if cost

    @io.puts("\n#{@theme.dim("#{parts.join(' · ')}   #{session_parts.join(' · ')}")}")
  end

  def format_arguments(arguments)
    parsed = JSON.parse(arguments)
    parsed.map { |key, value| "#{key}: #{value.inspect}" }.join(', ')
  rescue JSON::ParserError
    arguments
  end

  def preview(content)
    first_line = content.to_s.lines.first.to_s.chomp
    return first_line if first_line.length <= RESULT_PREVIEW_LIMIT

    "#{first_line[0, RESULT_PREVIEW_LIMIT]}…"
  end
end
