# frozen_string_literal: true

class Riffer::Rig::Terminal::Console
  # @rbs @output: IO
  # @rbs @frame: Riffer::Rig::Terminal::Frame
  # @rbs @pipeline: Riffer::Rig::Terminal::KeyPipeline
  # @rbs @partial: String

  # @rbs output: IO
  # @rbs frame: Riffer::Rig::Terminal::Frame
  # @rbs pipeline: Riffer::Rig::Terminal::KeyPipeline
  # @rbs return: void
  def initialize(output:, frame:, pipeline:)
    @output = output
    @frame = frame
    @pipeline = pipeline
    @partial = ''
  end

  # @rbs return: void
  def start
    @frame.start
    @pipeline.start
  end

  # @rbs return: void
  def stop
    @pipeline.stop
    settle
    @frame.stop
  end

  # @rbs *chunks: String
  # @rbs return: void
  def print(*chunks)
    # The footer sits where an unterminated line would end, so only whole
    # lines go above it.
    finished, newline, @partial = "#{@partial}#{chunks.join}".rpartition("\n")
    @frame.append("#{finished}#{newline}") unless newline.empty?
  end

  # @rbs line: String
  # @rbs return: void
  def puts(line = '')
    print(line.end_with?("\n") ? line : "#{line}\n")
  end

  # @rbs return: void
  def flush
    # The frame flushes each line it appends.
  end

  # @rbs return: bool
  def tty?
    # A tty would be given the spinner, the paced prose and the hidden cursor,
    # which all write to the line the footer owns.
    false
  end

  # @rbs return: [Integer, Integer]
  def winsize
    @output.winsize
  end

  # @rbs return: void
  def settle
    return if @partial.empty?

    @frame.append(@partial)
    @partial = ''
  end
end
