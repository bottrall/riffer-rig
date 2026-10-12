# frozen_string_literal: true

class Riffer::Rig::Tools::Bash::Capture
  CHUNK_BYTES = 16_384 #: Integer

  # @rbs @stream: IO
  # @rbs @limit: Integer
  # @rbs @buffer: String
  # @rbs @ended: bool

  # @rbs stream: IO
  # @rbs limit: Integer
  # @rbs return: void
  def initialize(stream, limit)
    @stream = stream
    @limit = limit
    @buffer = String.new(encoding: Encoding::BINARY)
    @ended = false
  end

  # @rbs timeout: Float
  # @rbs return: void
  def read(timeout)
    @stream.wait_readable(timeout)
    take
  end

  # @rbs return: void
  def drain
    loop { break unless take.is_a?(String) && within_limit? }
  end

  # @rbs return: bool
  def ended?
    @ended
  end

  # @rbs return: String
  def to_s
    @buffer.dup.force_encoding(Encoding::UTF_8).scrub
  end

  private

  # @rbs return: (String | :wait_readable)?
  def take
    chunk = @stream.read_nonblock(CHUNK_BYTES, exception: false)
    @ended = chunk.nil?
    # Truncation only marks text longer than the limit, so the buffer must overrun it.
    @buffer << chunk if chunk.is_a?(String) && within_limit?
    chunk
  end

  # @rbs return: bool
  def within_limit?
    @buffer.bytesize <= @limit
  end
end
