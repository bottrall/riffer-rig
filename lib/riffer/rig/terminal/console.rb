# frozen_string_literal: true

class Riffer::Rig::Terminal::Console
  # @rbs @frame: Riffer::Rig::Terminal::Frame
  # @rbs @pipeline: Riffer::Rig::Terminal::KeyPipeline
  # @rbs @loading: Riffer::Rig::Terminal::Loading

  # @rbs frame: Riffer::Rig::Terminal::Frame
  # @rbs pipeline: Riffer::Rig::Terminal::KeyPipeline
  # @rbs loading: Riffer::Rig::Terminal::Loading
  # @rbs return: void
  def initialize(frame:, pipeline:, loading:)
    @frame = frame
    @pipeline = pipeline
    @loading = loading
  end

  # @rbs return: void
  def start
    # The first tick pushes the animated line before the frame draws, so the
    # loading row is animated from its first write.
    @loading.start
    @frame.start
    @pipeline.start
  end

  # @rbs return: void
  def stop
    @pipeline.stop
    @frame.stop
    @loading.stop
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
    false
  end
end
