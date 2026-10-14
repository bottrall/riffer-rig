# frozen_string_literal: true

class Riffer::Rig::Terminal::Peek
  TOOL = '⚙' #: String

  # @rbs @frame: Riffer::Rig::Terminal::Frame
  # @rbs @mutex: Mutex
  # @rbs @buffer: Riffer::Rig::Terminal::TurnBuffer?
  # @rbs @open: bool

  # @rbs frame: Riffer::Rig::Terminal::Frame
  # @rbs return: void
  def initialize(frame:)
    @frame = frame
    @mutex = Mutex.new
    @buffer = nil
    @open = false
  end

  # @rbs buffer: Riffer::Rig::Terminal::TurnBuffer
  # @rbs return: void
  def watch(buffer)
    @mutex.synchronize { @buffer = buffer }
  end

  # @rbs key: Riffer::Rig::Terminal::Key
  # @rbs return: void
  def press(key)
    return unless key.name == :ctrl_t

    @mutex.synchronize do
      buffer = @buffer
      return unless buffer

      @open = !@open
      @frame.peek(@open ? content(buffer) : '')
    end
  end

  # @rbs return: void
  def refresh
    # A key is pressed off the thread the turn runs on: without the lock, a
    # peek read before it was toggled off could be drawn after it was hidden.
    @mutex.synchronize do
      buffer = @buffer
      @frame.peek(content(buffer)) if buffer && @open
    end
  end

  # @rbs return: void
  def unwatch
    @mutex.synchronize do
      @buffer = nil
      @open = false
      @frame.peek('')
    end
  end

  private

  # @rbs buffer: Riffer::Rig::Terminal::TurnBuffer
  # @rbs return: String
  def content(buffer)
    prose = buffer.prose.strip
    tool = buffer.tool
    # Running a tool closes the request that called it, so the prose that led
    # to a tool in flight is only ever the ghost.
    [prose.empty? ? buffer.ghost : prose, ("#{TOOL} #{tool}" if tool)]
      .compact
      .join("\n")
      .gsub(Riffer::Rig::Terminal::Markdown::CONTROL, '')
      .gsub("\t", Riffer::Rig::Terminal::Markdown::TAB)
  end
end
