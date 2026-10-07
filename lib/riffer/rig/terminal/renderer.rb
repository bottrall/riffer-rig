# frozen_string_literal: true

require 'io/console'
require 'json'

class Riffer::Rig::Terminal::Renderer
  RESULT_PREVIEW_LIMIT = 200 #: Integer

  ARGUMENT_PREVIEW_LIMIT = 60 #: Integer

  DETAIL_LIMIT = 48 #: Integer

  PROSE_INDENT = 2 #: Integer

  TOOL_RESULT_INDENT = 6 #: Integer

  # @rbs @io: IO
  # @rbs @theme: Riffer::Rig::Terminal::Theme
  # @rbs @smoother: Riffer::Rig::Terminal::Smoother | PassThroughSmoother
  # @rbs @cursor: Riffer::Rig::Terminal::Cursor
  # @rbs @prose_gap_pending: bool
  # @rbs @width: Integer?
  # @rbs @wrapper: Riffer::Rig::Terminal::Wrapper
  # @rbs @tool_calls: Hash[String, Integer]
  # @rbs @turn_started_at: Float?

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
    @tool_calls = {}
    @turn_started_at = nil
  end

  # @rbs event: Riffer::StreamEvents::TextDelta | Riffer::StreamEvents::ToolCallDone | Riffer::StreamEvents::Interrupt
  # @rbs return: void
  def render(event)
    case event
    when Riffer::StreamEvents::TextDelta
      render_prose(event.content)
    when Riffer::StreamEvents::ToolCallDone
      note_tool_call(event.name)
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
    line = fit(summary_line(usage, session), 0)
    flush_prose
    @prose_gap_pending = true
    return if line.empty?

    @io.puts
    @io.print("#{@theme.dim(line)}\n")
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
    @tool_calls = {}
    @turn_started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
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
    return unless message.error?

    open_tool_activity
    line = fit("✗ #{preview(message.content)}", TOOL_RESULT_INDENT)
    @io.print("#{' ' * TOOL_RESULT_INDENT}#{@theme.red(line)}\n")
    @io.flush
  end

  # @rbs name: String
  # @rbs arguments: String
  # @rbs return: String
  def tool_detail(name, arguments)
    parsed = JSON.parse(arguments)
    detail = parsed.map { |key, value| "#{key}: #{elide(value.inspect, ARGUMENT_PREVIEW_LIMIT)}" }.join(', ')
    elide("#{name}(#{detail})", DETAIL_LIMIT)
  rescue JSON::ParserError
    elide("#{name}(#{arguments})", DETAIL_LIMIT)
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

  # Tool calls are summarized per turn rather than printed as they happen —
  # the live status line carries the play-by-play — but prose on either side
  # of a tool burst still gets a gap, so paragraphs don't merge.
  # @rbs name: String
  # @rbs return: void
  def note_tool_call(name)
    flush_prose
    @prose_gap_pending = true
    @tool_calls[name] = @tool_calls.fetch(name, 0) + 1
  end

  # @rbs return: void
  def open_tool_activity
    # Tool-result lines share one blank line above the group; the group stays
    # open so the prose after it pays the closing gap.
    return if @prose_gap_pending

    flush_prose
    @io.puts
    @prose_gap_pending = true
  end

  # @rbs usage: Riffer::Providers::TokenUsage?
  # @rbs session: Riffer::Providers::TokenUsage?
  # @rbs return: String
  def summary_line(usage, session)
    parts = [calls_segment, elapsed_segment] #: Array[String?]
    if usage && session
      parts << token_segment(usage)
      parts << "session #{Riffer::Rig::Terminal::Format.tokens(session.total_tokens)} tok"
      cost = session.cost
      parts << format('~$%.4f', cost) if cost
    end

    parts.compact.join(' · ')
  end

  # @rbs return: String?
  def calls_segment
    total = @tool_calls.values.sum
    return nil if total.zero?

    breakdown = @tool_calls.map do |name, count|
      count == 1 ? name : "#{name}×#{count}"
    end.join(' ')
    "#{total == 1 ? '1 call' : "#{total} calls"} #{breakdown}"
  end

  # @rbs return: String?
  def elapsed_segment
    started = @turn_started_at
    return nil unless started

    Riffer::Rig::Terminal::Format.elapsed(Process.clock_gettime(Process::CLOCK_MONOTONIC) - started)
  end

  # @rbs usage: Riffer::Providers::TokenUsage
  # @rbs return: String
  def token_segment(usage)
    tokens = "↑#{Riffer::Rig::Terminal::Format.tokens(usage.input_tokens)} ↓#{Riffer::Rig::Terminal::Format.tokens(usage.output_tokens)}"
    tokens << " cache_write:#{usage.cache_write_tokens}" if usage.cache_write_tokens&.positive?
    tokens << " cache_read:#{usage.cache_read_tokens}" if usage.cache_read_tokens&.positive?

    tokens
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
