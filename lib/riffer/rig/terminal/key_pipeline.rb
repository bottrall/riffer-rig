# frozen_string_literal: true

require 'io/console'
require 'io/wait'

class Riffer::Rig::Terminal::KeyPipeline
  IDLE_SECONDS = 0.05 #: Float

  BRACKETED_PASTE_ON = "\e[?2004h" #: String

  BRACKETED_PASTE_OFF = "\e[?2004l" #: String

  # Terminals without the Kitty keyboard protocol ignore both sequences and
  # keep sending legacy bytes.
  KITTY_KEYBOARD_ON = "\e[>1u" #: String

  KITTY_KEYBOARD_OFF = "\e[<u" #: String

  # @rbs @input: IO
  # @rbs @output: IO
  # @rbs @decoder: Riffer::Rig::Terminal::KeyDecoder
  # @rbs @queue: Thread::Queue[Riffer::Rig::Terminal::Key]
  # @rbs @thread: Thread?
  # @rbs @stopping: bool

  # @rbs input: IO
  # @rbs output: IO
  # @rbs decoder: Riffer::Rig::Terminal::KeyDecoder
  # @rbs return: void
  def initialize(input:, output:, decoder: Riffer::Rig::Terminal::KeyDecoder.new)
    @input = input
    @output = output
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
    return @queue.close unless @input.tty?

    write(KITTY_KEYBOARD_ON)
    write(BRACKETED_PASTE_ON)
    @stopping = false
    @thread = Thread.new { read_loop }
  end

  # @rbs return: void
  def stop
    thread = @thread
    @thread = nil
    return unless thread

    @stopping = true
    thread.join
    write(BRACKETED_PASTE_OFF)
    write(KITTY_KEYBOARD_OFF)
  end

  private

  # The reader only reads: it never renders, and the queue is the single
  # handoff point back to the single-threaded render loop.
  # @rbs return: void
  def read_loop
    @input.raw do
      until @stopping
        # wait_readable's timeout and EOF both make getbyte-less paths return
        # nil, but only EOF may end the loop: an idle gap must keep polling.
        next unless @input.wait_readable(IDLE_SECONDS)

        # Bytes, not getc: getc decodes in the locale's encoding, and holds a
        # byte that may begin a character until the next key arrives.
        byte = @input.getbyte
        break unless byte

        emit(@decoder.push(byte))
        while @decoder.pending? && !@stopping
          follow = read_byte
          break unless follow

          emit(@decoder.push(follow))
        end
        emit(@decoder.flush) if @decoder.pending?
      end
      nil
    end
  ensure
    # A stop keeps the keys open for a restart. Anything else that ends the
    # reader, end of input or a failure, ends the keys for good.
    @queue.close unless @stopping
  end

  # @rbs return: Integer?
  def read_byte
    return unless @input.wait_readable(IDLE_SECONDS)

    @input.getbyte
  end

  # @rbs events: Array[Riffer::Rig::Terminal::Key]
  # @rbs return: void
  def emit(events)
    events.each { |key| @queue << key }
  end

  # @rbs sequence: String
  # @rbs return: void
  def write(sequence)
    @output.print(sequence)
    @output.flush
  end
end
