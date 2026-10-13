# frozen_string_literal: true

class Riffer::Rig::Tools::Bash::JobLog
  MAX_BYTES = 10_000_000 #: Integer

  KEEP_BYTES = MAX_BYTES / 2 #: Integer

  CHUNK_BYTES = 65_536 #: Integer

  DROPPED = "[earlier output dropped to keep this file under #{MAX_BYTES} bytes]\n".freeze #: String

  # @rbs @output: IO
  # @rbs @path: String
  # @rbs @mutex: Mutex
  # @rbs @dropped: Integer
  # @rbs @copier: Thread

  # @rbs output: IO
  # @rbs path: String
  # @rbs return: void
  def initialize(output, path)
    @output = output
    @path = path
    @mutex = Mutex.new
    @dropped = 0
    file = File.new(path, 'a+b', 0o600)
    file.sync = true
    @copier = Thread.new { copy(file) }
  end

  # @rbs offset: Integer
  # @rbs limit: Integer
  # @rbs return: [String, Integer]
  def read(offset, limit)
    @mutex.synchronize do
      marker = marker_bytes
      # Offsets count the bytes the job has written rather than a place in the
      # file, so they stay valid when the head of the file is dropped.
      position = offset < @dropped ? 0 : marker + offset - @dropped
      size = File.size?(@path).to_i
      output = slice(limit, position)
      # The inner max covers a file that grew between the size and the read,
      # the outer one a removed file, which must not move the offset back.
      [output, [@dropped - marker + [position + output.bytesize, size].max, offset].max]
    end
  end

  # @rbs limit: Integer
  # @rbs return: String
  def tail(limit)
    @mutex.synchronize { slice(limit, [File.size?(@path).to_i - limit, 0].max) }
  end

  # @rbs timeout: Float
  # @rbs return: void
  def drain(timeout)
    @copier.join(timeout)
  end

  # @rbs return: void
  def close
    # Closing the pipe raises IOError in a copier blocked reading it.
    @output.close
    @copier.join
  end

  private

  # @rbs file: File
  # @rbs return: void
  def copy(file)
    loop do
      chunk = @output.readpartial(CHUNK_BYTES)
      compact(file) if file.size + chunk.bytesize > MAX_BYTES
      file.write(chunk)
    end
  rescue IOError
    # The output ended, or close shut the pipe under the read.
  ensure
    @output.close
    file.close
  end

  # @rbs file: File
  # @rbs return: void
  def compact(file)
    cut = file.size - KEEP_BYTES
    kept = file.pread(KEEP_BYTES, cut)
    # Rewritten through the open file rather than replaced by path, so a
    # removed file or directory cannot stop the copy, and under the lock so no
    # read sees the file half-written.
    @mutex.synchronize do
      @dropped += cut - marker_bytes
      file.truncate(0)
      file.write(DROPPED, kept)
    end
  end

  # @rbs return: Integer
  def marker_bytes
    @dropped.zero? ? 0 : DROPPED.bytesize
  end

  # @rbs limit: Integer
  # @rbs position: Integer
  # @rbs return: String
  def slice(limit, position)
    read = begin
      File.read(@path, limit, position)
    rescue Errno::ENOENT
      # A tmp cleaner or the job itself can remove the output file, even between
      # the size and the read.
      nil
    end
    (read || +'').force_encoding(Encoding.default_external)
  end
end
