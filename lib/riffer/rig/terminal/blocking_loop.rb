# frozen_string_literal: true

class Riffer::Rig::Terminal::BlockingLoop
  # @rbs @input: IO
  # @rbs @renderer: Riffer::Rig::Terminal::Renderer
  # @rbs @armed: bool

  # @rbs input: IO
  # @rbs renderer: Riffer::Rig::Terminal::Renderer
  # @rbs return: void
  def initialize(input:, renderer:)
    @input = input
    @renderer = renderer
    @armed = false
  end

  # @rbs return: void
  def start; end

  # @rbs return: void
  def stop; end

  # @rbs &block: (String) -> void
  # @rbs return: void
  def run
    loop do
      case (line = read_line)
      when nil then break
      when :interrupt then break unless arm
      else
        @armed = false
        text = line.strip
        next if text.empty?

        begin
          yield text
        rescue Interrupt
          arm
        end
      end
    end
  end

  # @rbs return: bool
  def arm # rubocop:disable Naming/PredicateMethod -- it acts, and its result says whether the session goes on, as Repl#arm does
    return false if @armed

    @armed = true
    @renderer.notice(Riffer::Rig::Terminal::EXIT_HINT)
    true
  end

  private

  # @rbs return: String | :interrupt | nil
  def read_line
    @renderer.prompt
    @input.gets
  rescue Interrupt
    :interrupt
  end
end
