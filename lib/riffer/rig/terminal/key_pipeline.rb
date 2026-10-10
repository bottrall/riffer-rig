# frozen_string_literal: true

require 'io/console'
require 'io/wait'

class Riffer::Rig::Terminal::KeyPipeline
  IDLE_SECONDS = 0.05 #: Float

  # @rbs @input: IO
  # @rbs @decoder: Riffer::Rig::Terminal::KeyDecoder
  # @rbs @queue: Thread::Queue[Riffer::Rig::Terminal::Key]
  # @rbs @thread: Thread?
  # @rbs @stopping: bool

  # @rbs input: IO
  # @rbs decoder: Riffer::Rig::Terminal::KeyDecoder
  # @rbs return: void
  def initialize(input:, decoder: Riffer::Rig::Terminal::KeyDecoder.new)
    @input = input
    @decoder = decoder
    @queue = Queue.new
    @thread = nil
    @stopping = false
  end

  # @rbs return: Thread::Queue[Riffer::Rig::Terminal::Key]
  def keys
    @queue
  end

  # @rbs return: void
  def start
    return unless @input.tty?

    @thread = Thread.new { read_loop }
  end

  # @rbs return: void
  def stop
    thread = @thread
    @thread = nil
    return unless thread

    @stopping = true
    thread.join
  end

  private

  # The reader only reads: it never renders, and the queue is the single
  # handoff point back to the single-threaded render loop.
  # @rbs return: void
  def read_loop
    @input.raw do
      until @stopping
        # wait_readable's timeout and EOF both make getc-less paths return
        # nil, but only EOF may end the loop: an idle gap must keep polling.
        next unless @input.wait_readable(IDLE_SECONDS)

        char = @input.getc
        break unless char

        emit(@decoder.push(char))
        while @decoder.pending? && !@stopping
          follow = read_char
          break unless follow

          emit(@decoder.push(follow))
        end
        emit(@decoder.flush) if @decoder.pending?
      end
      nil
    end
  end

  # @rbs return: String?
  def read_char
    return unless @input.wait_readable(IDLE_SECONDS)

    @input.getc
  end

  # @rbs events: Array[Riffer::Rig::Terminal::Key]
  # @rbs return: void
  def emit(events)
    events.each { |key| @queue << key }
  end
end
