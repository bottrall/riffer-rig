# frozen_string_literal: true

require 'io/console'
require 'json'

class Riffer::Rig::Terminal::Renderer
  RESULT_PREVIEW_LIMIT = 200 #: Integer

  ARGUMENT_PREVIEW_LIMIT = 60 #: Integer

  PROSE_INDENT = 2 #: Integer

  TOOL_CALL_INDENT = 4 #: Integer

  TOOL_RESULT_INDENT = 6 #: Integer

  # @rbs @io: IO
  # @rbs @theme: Riffer::Rig::Terminal::Theme
  # @rbs @smoother: Riffer::Rig::Terminal::Smoother | PassThroughSmoother
  # @rbs @cursor: Riffer::Rig::Terminal::Cursor
  # @rbs @prose_gap_pending: bool
  # @rbs @width: Integer?
  # @rbs @wrapper: Riffer::Rig::Terminal::Wrapper

  # @rbs io: IO
  # @rbs theme: Riffer::Rig::Terminal::Theme
  # @rbs smoother: Riffer::Rig::Terminal::Smoother | PassThroughSmoother
  # @rbs cursor: Riffer::Rig::Terminal::Cursor
  # @rbs width: Integer?
  # @rbs return: void
  def initialize(
    io: $stdout,
    theme: Riffer::Rig::Terminal::Theme.for(io),
    smoother: PassThroughSmoother.new(io),
    cursor: Riffer::Rig::Terminal::Cursor.new(io: io, theme: theme),
    width: nil
  )
    @io = io
    @theme = theme
    @smoother = smoother
    @cursor = cursor
    @prose_gap_pending = false
    @width = width
    @wrapper = new_wrapper
  end

  # @rbs event: Riffer::StreamEvents::TextDelta | Riffer::StreamEvents::ToolCallDone | Riffer::StreamEvents::Interrupt
  # @rbs return: void
  def render(event)
    case event
    when Riffer::StreamEvents::TextDelta
      render_prose(event.content)
    when Riffer::StreamEvents::ToolCallDone
      render_tool_activity(TOOL_CALL_INDENT) { "⚙ #{event.name}(#{format_arguments(event.arguments)})" }
    when Riffer::StreamEvents::Interrupt
      render_block(0) { @theme.dim("[interrupted: #{event.reason}]") }
    end
  end

  # @rbs name: String
  # @rbs return: void
  def skill(name)
    render_block(0) { @theme.magenta("✦ skill: #{name}") }
  end

  # @rbs text: String
  # @rbs return: void
  def notice(text)
    render_block(0) { @theme.grey(text) }
  end

  # @rbs text: String
  # @rbs return: void
  def error(text)
    render_block(0) { @theme.red(text) }
  end

  # @rbs message: String
  # @rbs level: Symbol
  # @rbs return: void
  def notify(message, level)
    level == :error ? error(message) : notice(message)
  end

  # @rbs usage: Riffer::Providers::TokenUsage?
  # @rbs session: Riffer::Providers::TokenUsage?
  # @rbs return: void
  def usage(usage, session)
    return unless usage && session

    flush_prose
    @prose_gap_pending = true
    @io.puts
    text = (@wrapper << usage_line(usage, session)) + @wrapper.flush
    @io.print(@theme.dim(text)) unless text.empty?
    @io.flush
  end

  # @rbs return: void
  def prompt
    # Closes any tool group the previous turn left open, so the next turn's
    # blocks open cleanly.
    @prose_gap_pending = true
    @io.puts
    @io.print("#{@theme.pink('›')} ")
    @io.flush
  end

  # @rbs question: String?
  # @rbs options: Array[String]?
  # @rbs secret: bool
  # @rbs return: void
  def question(question, options, secret)
    drain
    @io.puts
    @io.puts(question) if question
    options&.each_with_index { |option, index| @io.puts("  #{@theme.magenta("#{index + 1}.")} #{option}") }
    @io.print("#{@theme.pink('›')} #{@theme.grey('(hidden) ') if secret}")
    @io.flush
  end

  # @rbs return: void
  def newline
    @io.puts
    @io.flush
  end

  # @rbs return: void
  def begin_turn
    # A hidden cursor can't flicker against the animator's erase-and-redraw
    # churn.
    @cursor.hide
    @smoother.start
  end

  # @rbs return: void
  def end_turn
    flush_prose
    @smoother.finish
    @cursor.show
  end

  # @rbs return: void
  def drain
    flush_prose
  end

  # @rbs message: Riffer::Messages::Base
  # @rbs return: void
  def render_tool_result(message)
    return unless message.is_a?(Riffer::Messages::Tool)

    open_tool_activity
    line = fit("↳ #{preview(message.content)}", TOOL_RESULT_INDENT)
    styled = message.error? ? @theme.red(line) : @theme.dim(line)
    @io.print("#{' ' * TOOL_RESULT_INDENT}#{styled}\n")
    @io.flush
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
    def start = nil

    # @rbs return: nil
    def drain = nil

    # @rbs return: nil
    def finish = nil
  end

  private

  # @rbs indent: Integer
  # @rbs &block: () -> String
  # @rbs return: void
  def render_block(indent, &)
    flush_prose
    @io.puts
    @prose_gap_pending = true
    @io.puts((' ' * indent) + yield)
    @io.flush
  end

  # @rbs content: String
  # @rbs return: void
  def render_prose(content)
    # Streaming makes "which delta opens a prose block?" a stateful question,
    # so the gap is tracked in a flag rather than written at each render site.
    if @prose_gap_pending
      @prose_gap_pending = false
      @io.print("\n")
      @wrapper = new_wrapper
    end
    emit = @wrapper << content
    @smoother << emit unless emit.empty?
  end

  # @rbs indent: Integer
  # @rbs &block: () -> String
  # @rbs return: void
  def render_tool_activity(indent, &)
    open_tool_activity
    @io.puts((' ' * indent) + @theme.cyan(fit(yield, indent)))
    @io.flush
  end

  # @rbs return: void
  def open_tool_activity
    # Tool-activity lines (⚙ calls, ↳ results) share one blank line above the
    # group; the group stays open so the prose after it pays the closing gap.
    return if @prose_gap_pending

    flush_prose
    @io.puts
    @prose_gap_pending = true
  end

  # @rbs usage: Riffer::Providers::TokenUsage
  # @rbs session: Riffer::Providers::TokenUsage
  # @rbs return: String
  def usage_line(usage, session)
    parts = ["↑#{usage.input_tokens}", "↓#{usage.output_tokens}"]
    parts << "cache_write:#{usage.cache_write_tokens}" if usage.cache_write_tokens&.positive?
    parts << "cache_read:#{usage.cache_read_tokens}" if usage.cache_read_tokens&.positive?
    parts << "session #{session.total_tokens} tok"
    cost = session.cost
    parts << format('~$%.4f', cost) if cost

    parts.join(' · ')
  end

  # @rbs arguments: String
  # @rbs return: String
  def format_arguments(arguments)
    parsed = JSON.parse(arguments)
    parsed.map { |key, value| "#{key}: #{elide(value.inspect, ARGUMENT_PREVIEW_LIMIT)}" }.join(', ')
  rescue JSON::ParserError
    arguments
  end

  # @rbs content: String
  # @rbs return: String
  def preview(content)
    first_line = content.to_s.lines.first.to_s.chomp
    elide(first_line, RESULT_PREVIEW_LIMIT)
  end

  # @rbs text: String
  # @rbs limit: Integer
  # @rbs return: String
  def elide(text, limit)
    return text if text.length <= limit
    return '…' if limit < 1

    "#{text[0, limit - 1]}…"
  end

  # Truncation is what keeps an indented line from wrapping: a wrapped
  # continuation starts at column zero and destroys the prose > tool nesting.
  # @rbs text: String
  # @rbs indent: Integer
  # @rbs return: String
  def fit(text, indent)
    width = detect_width
    return text unless width

    elide(text, width - indent)
  end

  # @rbs return: void
  def flush_prose
    emit = @wrapper.flush
    @smoother << emit unless emit.empty?
    @smoother.drain
  end

  # @rbs return: Riffer::Rig::Terminal::Wrapper
  def new_wrapper
    Riffer::Rig::Terminal::Wrapper.new(width: detect_width, indent: PROSE_INDENT)
  end

  # @rbs return: Integer?
  def detect_width
    @width || detected_width
  end

  # winsize raises on ttys with no queryable window size and some pty
  # wrappers report zero columns; either way the real width is unknowable,
  # and nil leaves every consumer un-fitted rather than mis-fitted.
  # @rbs return: Integer?
  def detected_width
    return nil unless @io.tty?

    width = @io.winsize[1]
    width.positive? ? width : nil
  rescue SystemCallError
    nil
  end
end
