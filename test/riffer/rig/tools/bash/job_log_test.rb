# frozen_string_literal: true

require 'test_helper'

describe Riffer::Rig::Tools::Bash::JobLog do
  def setup
    @directory = Dir.mktmpdir('riffer-rig-log-test')
    @path = File.join(@directory, 'output')
    @reader, @writer = IO.pipe
    @threads = Thread.list
    @log = Riffer::Rig::Tools::Bash::JobLog.new(@reader, @path)
  end

  def teardown
    @writer.close
    @log.close
    FileUtils.rm_rf(@directory)
  end

  def finish(output)
    @writer.write(output)
    @writer.close
    @log.drain(5.0)
  end

  def overflow(drops: 1)
    bytes = Riffer::Rig::Tools::Bash::JobLog::MAX_BYTES + ((drops - 1) * Riffer::Rig::Tools::Bash::JobLog::KEEP_BYTES)
    Random.new(1).bytes(bytes + 1_000).tap { |stream| finish(stream) }
  end

  def kept
    File.binread(@path).delete_prefix(Riffer::Rig::Tools::Bash::JobLog::DROPPED)
  end

  describe '#initialize' do
    it 'creates the file before any output arrives' do
      assert_path_exists @path
    end

    it 'keeps the file private to its owner' do
      assert_equal 0o600, File.stat(@path).mode & 0o777
    end
  end

  describe '#read' do
    it 'reads the output from the given offset' do
      finish('hello world')

      assert_equal 'world', @log.read(6, 100).first
    end

    it 'reads no more than the limit' do
      finish('hello world')

      assert_equal 'hello', @log.read(0, 5).first
    end

    it 'reads nothing new as an empty string' do
      finish('hello world')

      assert_equal '', @log.read(11, 100).first
    end

    it 'reads output in the default external encoding' do
      finish('hello world')

      assert_equal Encoding.default_external, @log.read(0, 100).first.encoding
    end

    it 'returns the offset of the end of the output' do
      finish('hello world')

      assert_equal 11, @log.read(0, 5).last
    end

    it 'reads a removed file as an empty string' do
      finish('hello world')
      File.delete(@path)

      assert_equal '', @log.read(0, 100).first
    end

    it 'keeps the offset when the file was removed' do
      finish('hello world')
      File.delete(@path)

      assert_equal 5, @log.read(5, 100).last
    end

    it 'reads from the marker once the output at its offset was dropped' do
      overflow
      marker = Riffer::Rig::Tools::Bash::JobLog::DROPPED

      assert_equal marker, @log.read(0, marker.bytesize).first
    end

    it 'reads on from an offset whose output is still in the file' do
      stream = overflow(drops: 2)
      offset = stream.bytesize - 10

      assert_equal stream.byteslice(offset, 10), @log.read(offset, 10).first.b
    end

    it 'counts the dropped output in the offset it returns' do
      stream = overflow(drops: 2)

      assert_equal stream.bytesize, @log.read(0, 10).last
    end

    it 'keeps an offset behind the dropped output when the file was removed' do
      stream = overflow
      offset = stream.bytesize - kept.bytesize - 1
      File.delete(@path)

      assert_equal offset, @log.read(offset, 10).last
    end
  end

  describe '#tail' do
    it 'returns the last bytes of the output' do
      finish('hello world')

      assert_equal 'world', @log.tail(5)
    end

    it 'returns all of an output shorter than the limit' do
      finish('hello world')

      assert_equal 'hello world', @log.tail(100)
    end

    it 'returns an empty string when nothing was written' do
      assert_equal '', @log.tail(5)
    end

    it 'returns an empty string when the file was removed' do
      finish('hello world')
      File.delete(@path)

      assert_equal '', @log.tail(5)
    end
  end

  describe '#drain' do
    it 'waits for the output to end' do
      @writer.write('hello')
      @writer.close
      @log.drain(5.0)

      assert_equal 'hello', File.read(@path)
    end

    it 'gives up at the timeout while the output stays open' do
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      @log.drain(0.01)

      assert_operator Process.clock_gettime(Process::CLOCK_MONOTONIC) - started, :<, 5
    end
  end

  describe '#close' do
    it 'closes the pipe' do
      @log.close

      assert_predicate @reader, :closed?
    end

    it 'leaves no copier thread while the output stays open' do
      @log.close

      assert_empty Thread.list - @threads
    end
  end

  describe 'copier' do
    it 'copies output while more can still arrive' do
      @writer.write('hello')
      sleep 0.01 until File.size(@path) == 5

      assert_equal 'hello', File.read(@path)
    end

    it 'copies bytes that are not valid text unchanged' do
      finish("ok\xFFok".b)

      assert_equal "ok\xFFok".b, File.binread(@path)
    end

    it 'closes the pipe when the output ends' do
      finish('hello')

      assert_predicate @reader, :closed?
    end
  end

  describe 'past the cap' do
    it 'keeps the file within the cap' do
      overflow

      assert_operator File.size(@path), :<=, Riffer::Rig::Tools::Bash::JobLog::MAX_BYTES
    end

    it 'starts the file with a marker for the dropped output' do
      overflow
      marker = Riffer::Rig::Tools::Bash::JobLog::DROPPED

      assert_equal marker, File.read(@path, marker.bytesize)
    end

    it 'keeps at least the most recent half of the cap' do
      overflow

      assert_operator kept.bytesize, :>=, Riffer::Rig::Tools::Bash::JobLog::KEEP_BYTES
    end

    it 'keeps the most recent output after the marker' do
      stream = overflow

      assert stream.end_with?(kept)
    end

    it 'keeps the most recent output when it drops output again' do
      stream = overflow(drops: 2)

      assert stream.end_with?(kept)
    end

    it 'drops output in the file it already holds open' do
      inode = File.stat(@path).ino
      overflow

      assert_equal inode, File.stat(@path).ino
    end

    it 'copies past the cap after its directory was removed' do
      FileUtils.remove_entry(@directory)
      overflow

      assert_predicate @reader, :closed?
    end
  end
end
