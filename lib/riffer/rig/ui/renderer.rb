# frozen_string_literal: true

require 'json'

class Riffer::Rig::UI::Renderer
  RESULT_PREVIEW_LIMIT = 200 #: Integer

  # @rbs @io: IO
  # @rbs @theme: Riffer::Rig::UI::Theme
  # @rbs @tally: Riffer::Rig::TokenTally?
  # @rbs @smoother: Riffer::Rig::UI::Smoother | PassThroughSmoother?
  # @rbs @deferred_usage: Riffer::Providers::TokenUsage?
  # @rbs @prose_gap_pending: bool

  # @rbs io: IO
  # @rbs theme: Riffer::Rig::UI::Theme
  # @rbs tally: Riffer::Rig::TokenTally?
  # @rbs smoother: Riffer::Rig::UI::Smoother | PassThroughSmoother?
  # @rbs return: void
  def initialize(io: $stdout, theme: Riffer::Rig::UI::Theme.for(io), tally: nil, smoother: nil)
    @io = io
    @theme = theme
    @tally = tally
    @smoother = smoother
    @deferred_usage = nil
    @prose_gap_pending = false
  end

  # @rbs event: Riffer::StreamEvents::Base
  # @rbs return: void
  def render(event)
    case event
    when Riffer::StreamEvents::TextDelta
      render_prose(event.content)
    when Riffer::StreamEvents::ToolCallDone
      render_tool_activity(2) { @theme.cyan("⚙ #{event.name}(#{format_arguments(event.arguments)})") }
    when Riffer::StreamEvents::SkillActivation
      render_block(0) { @theme.magenta("✦ skill: #{event.name}") }
    when Riffer::StreamEvents::Interrupt
      render_block(0) { @theme.dim("[interrupted: #{event.reason}]") }
    when Riffer::StreamEvents::TokenUsageDone
      current = @deferred_usage
      @deferred_usage = current ? current + event.token_usage : event.token_usage
    end
  end

  # Sits on the renderer so a tool group left open by the previous turn closes
  # here, and the next turn's blocks open cleanly.
  #
  # @rbs return: void
  def prompt
    @prose_gap_pending = true
    @io.puts
    @io.print("#{@theme.pink('›')} ")
    @io.flush
  end

  # Usage arrives per model call but tool results arrive via the session
  # callback after each call's stream ends, so rendering inline would print the
  # stats above the results they belong with.
  #
  # @rbs return: void
  def flush_usage
    usage = @deferred_usage
    @deferred_usage = nil
    tally = @tally
    return unless usage && tally

    tally.add(usage)
    render_block(0) { @theme.dim(usage_line(usage, tally)) }
  end

  # @rbs message: Riffer::Messages::Base
  # @rbs return: void
  def render_tool_result(message)
    return unless message.is_a?(Riffer::Messages::Tool)

    open_tool_activity
    line = "↳ #{preview(message.content)}"
    styled = message.error? ? @theme.red(line) : @theme.dim(line)
    @io.print("    #{styled}\n")
    @io.flush
  end

  private

  # @rbs indent: Integer
  # @rbs &block: () -> String
  # @rbs return: void
  def render_block(indent, &)
    drain_smoother
    @io.puts
    @prose_gap_pending = true
    @io.puts((' ' * indent) + yield)
    @io.flush
  end

  # Streaming makes "which delta opens a prose block?" a stateful question, so
  # the gap is tracked in a flag rather than written at each render site.
  #
  # @rbs content: String
  # @rbs return: void
  def render_prose(content)
    if @prose_gap_pending
      @prose_gap_pending = false
      @io.print("\n")
    end
    smoother << content
  end

  # @rbs indent: Integer
  # @rbs &block: () -> String
  # @rbs return: void
  def render_tool_activity(indent, &)
    open_tool_activity
    @io.puts((' ' * indent) + yield)
    @io.flush
  end

  # Tool-activity lines (⚙ calls, ↳ results) share one blank line above the
  # group; the group stays open so the prose after it pays the closing gap.
  #
  # @rbs return: void
  def open_tool_activity
    return if @prose_gap_pending

    drain_smoother
    @io.puts
    @prose_gap_pending = true
  end

  # @rbs usage: Riffer::Providers::TokenUsage
  # @rbs tally: Riffer::Rig::TokenTally
  # @rbs return: String
  def usage_line(usage, tally)
    parts = ["↑#{usage.input_tokens}", "↓#{usage.output_tokens}"]
    parts << "cache_write:#{usage.cache_write_tokens}" if usage.cache_write_tokens&.positive?
    parts << "cache_read:#{usage.cache_read_tokens}" if usage.cache_read_tokens&.positive?
    parts << "session #{tally.total_tokens} tok"
    cost = tally.estimated_cost
    parts << format('~$%.4f', cost) if cost

    parts.join(' · ')
  end

  # @rbs return: Riffer::Rig::UI::Smoother | PassThroughSmoother
  def smoother
    @smoother || PassThroughSmoother.new(@io)
  end

  class PassThroughSmoother
    # @rbs @io: IO

    # @rbs io: IO
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
