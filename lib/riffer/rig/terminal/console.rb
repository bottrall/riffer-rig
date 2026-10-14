# frozen_string_literal: true

class Riffer::Rig::Terminal::Console
  # @rbs @frame: Riffer::Rig::Terminal::Frame
  # @rbs @pipeline: Riffer::Rig::Terminal::KeyPipeline

  # @rbs frame: Riffer::Rig::Terminal::Frame
  # @rbs pipeline: Riffer::Rig::Terminal::KeyPipeline
  # @rbs return: void
  def initialize(frame:, pipeline:)
    @frame = frame
    @pipeline = pipeline
  end

  # @rbs return: void
  def start
    @frame.start
    @pipeline.start
  end

  # @rbs return: void
  def stop
    @pipeline.stop
    @frame.stop
  end

  # @rbs *chunks: String
  # @rbs return: void
  def print(*chunks)
    text = chunks.join
    @frame.append(text) unless text.empty?
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
    # A tty would be given the banner's reveal, which redraws in place over
    # the rows the footer owns.
    false
  end
end
