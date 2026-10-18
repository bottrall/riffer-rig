# frozen_string_literal: true

class Riffer::Rig::Terminal::Loading
  TICK_SECONDS = 0.12 #: Float

  QUIP_TICKS = 8 #: Integer

  FRAMES = '⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'.chars.freeze #: Array[String]

  QUIPS = [
    'warming the amp…',
    'checking the levels…',
    'rolling the tape…',
    'finding the groove…',
    'setting the needle…',
    'dusting off the vinyl…',
    'plugging in…'
  ].freeze #: Array[String]

  # @rbs @frame: Riffer::Rig::Terminal::Frame
  # @rbs @random: Random
  # @rbs @halt: Thread::Queue[true]
  # @rbs @thread: Thread?
  # @rbs @tick: Integer
  # @rbs @quip: String

  # @rbs frame: Riffer::Rig::Terminal::Frame
  # @rbs random: Random
  # @rbs return: void
  def initialize(frame:, random:)
    @frame = frame
    @random = random
    @halt = Queue.new
    @thread = nil
    @tick = 0
    @quip = ''
  end

  # @rbs return: void
  def start
    tick
    @thread = Thread.new { tick until @halt.pop(timeout: TICK_SECONDS) }
  end

  # @rbs return: void
  def stop
    @halt << true
    @thread&.join
  end

  # @rbs return: void
  def tick
    # The banner, an error, or the frame stopping ends the loading row; the
    # halt handed to this thread's own wait below ends it without another lap.
    unless @frame.loading?
      @halt << true
      return
    end

    roll if (@tick % QUIP_TICKS).zero?
    @frame.loading("#{FRAMES.fetch(@tick % FRAMES.size)} #{@quip}")
    @tick += 1
  end

  private

  # @rbs return: void
  def roll
    @quip = QUIPS.fetch(@random.rand(QUIPS.size))
  end
end
