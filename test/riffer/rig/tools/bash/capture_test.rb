# frozen_string_literal: true

require 'test_helper'

describe Riffer::Rig::Tools::Bash::Capture do
  def setup
    @reader, @writer = IO.pipe
  end

  def teardown
    [@reader, @writer].each(&:close)
  end

  def new_capture(limit = 100)
    Riffer::Rig::Tools::Bash::Capture.new(@reader, limit)
  end

  describe '#read' do
    it 'takes output that is ready' do
      capture = new_capture
      @writer.write('hello')
      capture.read(0.0)

      assert_equal 'hello', capture.to_s
    end

    it 'waits for output to arrive' do
      capture = new_capture
      writer = Thread.new do
        sleep 0.05
        @writer.write('late')
      end
      capture.read(5.0)
      writer.join

      assert_equal 'late', capture.to_s
    end

    it 'returns when nothing arrives in time' do
      capture = new_capture
      capture.read(0.0)

      assert_equal '', capture.to_s
    end

    it 'keeps the chunk that crosses the limit' do
      capture = new_capture(4)
      @writer.write('abcdef')
      capture.read(0.0)

      assert_equal 'abcdef', capture.to_s
    end

    it 'drops output arriving past the limit' do
      capture = new_capture(4)
      %w[abcdef ghi].each do |chunk|
        @writer.write(chunk)
        capture.read(0.0)
      end

      assert_equal 'abcdef', capture.to_s
    end

    it 'still consumes output arriving past the limit' do
      capture = new_capture(4)
      %w[abcdef ghi].each do |chunk|
        @writer.write(chunk)
        capture.read(0.0)
      end

      assert_equal :wait_readable, @reader.read_nonblock(1, exception: false)
    end
  end

  describe '#drain' do
    it 'takes everything already written' do
      capture = new_capture(50_000)
      @writer.write('x' * 40_000)
      capture.drain

      assert_equal 40_000, capture.to_s.bytesize
    end

    it 'returns when nothing is ready' do
      capture = new_capture
      capture.drain

      assert_equal '', capture.to_s
    end

    it 'stops once past the limit' do
      capture = new_capture(10)
      @writer.write('x' * 40_000)
      capture.drain

      assert_equal 40_000 - Riffer::Rig::Tools::Bash::Capture::CHUNK_BYTES, @reader.read_nonblock(40_000).bytesize
    end
  end

  describe '#ended?' do
    it 'is false while the stream is open' do
      capture = new_capture
      capture.read(0.0)

      refute_predicate capture, :ended?
    end

    it 'is true once the stream has closed' do
      capture = new_capture
      @writer.close
      capture.read(0.0)

      assert_predicate capture, :ended?
    end
  end

  describe '#to_s' do
    it 'replaces bytes that are not valid UTF-8' do
      capture = new_capture
      @writer.write("ok\xFFok".b)
      capture.read(0.0)

      assert_equal "ok\u{FFFD}ok", capture.to_s
    end

    it 'joins a character split across reads' do
      capture = new_capture
      'é'.bytes.each do |byte|
        @writer.write(byte.chr)
        capture.read(0.0)
      end

      assert_equal 'é', capture.to_s
    end
  end
end
