# frozen_string_literal: true

class Riffer::Rig::Terminal::Animator
  REVEAL_FRAME_SECONDS = 0.05 #: Float

  # @rbs @io: Riffer::Rig::Terminal::_Output
  # @rbs @theme: Riffer::Rig::Terminal::Theme

  # @rbs io: Riffer::Rig::Terminal::_Output
  # @rbs theme: Riffer::Rig::Terminal::Theme
  # @rbs return: void
  def initialize(io: $stdout, theme: Riffer::Rig::Terminal::Theme.for(io))
    @io = io
    @theme = theme
  end

  # @rbs frames: Array[Array[String]]
  # @rbs return: void
  def reveal(frames)
    unless enabled?
      frames.last.each { |line| @io.puts(line) }
      return
    end

    height = frames.first.length
    frames.each_with_index do |lines, index|
      lines.each { |line| @io.print("#{line}\e[K\n") }
      @io.flush
      sleep(REVEAL_FRAME_SECONDS)
      @io.print("\e[#{height}A\r") unless index == frames.length - 1
    end
  end

  private

  # @rbs return: bool
  def enabled?
    @theme.enabled && @io.tty?
  end
end
