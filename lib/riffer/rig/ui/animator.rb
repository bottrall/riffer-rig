# frozen_string_literal: true

# Animated output is gated behind an interactive, colour-enabled TTY, so piped
# or tested runs stay silent and escape-free.
class Riffer::Rig::UI::Animator
  REVEAL_FRAME_SECONDS = 0.05
  SPINNER_FRAME_SECONDS = 0.12
  SPINNER_FRAMES = '⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'.chars.freeze

  def initialize(io: $stdout, theme: Riffer::Rig::UI::Theme.for(io))
    @io = io
    @theme = theme
    @thread = nil
  end

  # When not on a TTY, prints the final frame once instead of animating.
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

  def start_thinking
    return unless enabled?

    @stop = false
    @thread = Thread.new do
      tick = 0
      until @stop
        frame = SPINNER_FRAMES[tick % SPINNER_FRAMES.length]
        @io.print("\r  #{frame} #{@theme.cyan('thinking…')}\e[K")
        @io.flush
        sleep(SPINNER_FRAME_SECONDS)
        tick += 1
      end
    end
  end

  def stop_thinking
    return unless @thread

    @stop = true
    @thread.join
    @thread = nil
    @io.print("\r\e[K")
    @io.flush
  end

  private

  def enabled?
    @theme.enabled && @io.respond_to?(:tty?) && @io.tty?
  end
end
