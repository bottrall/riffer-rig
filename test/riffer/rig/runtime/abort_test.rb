# frozen_string_literal: true

require 'test_helper'

describe Riffer::Rig::Runtime::Abort do
  before do
    @abort = Riffer::Rig::Runtime::Abort.new
  end

  def shielded(&)
    Thread.handle_interrupt(Riffer::Rig::Runtime::Abort::SHIELD, &)
  end

  # The cheapest call Ruby treats as blocking, which is where a signal lands.
  def block_briefly
    sleep(0)
  end

  def signal_pending?
    Thread.pending_interrupt?(Riffer::Rig::Runtime::Abort::Signal)
  end

  describe '#window' do
    it 'returns what the block returns' do
      assert_equal(:done, @abort.window { :done })
    end

    it 'returns nil when fired from another thread while the block is blocked' do
      started = Queue.new
      canceller = Thread.new do
        started.pop
        @abort.fire
      end
      result = @abort.window do
        started << true
        Queue.new.pop(timeout: 5)
        :done
      end
      canceller.join

      assert_nil result
    end

    it 'holds a signal off inside the shield' do
      finished = false
      @abort.window do
        shielded do
          @abort.fire
          block_briefly
          finished = true
        end
      end

      assert finished
    end

    it 'lands a held signal at the next blocking call' do
      result = @abort.window do
        shielded { @abort.fire }
        block_briefly
        :done
      end

      assert_nil result
    end

    it 'lets a block that never blocks again finish' do
      result = @abort.window do
        shielded { @abort.fire }
        :done
      end

      assert_equal :done, result
    end

    it 'leaves no signal pending for the caller' do
      @abort.window { shielded { @abort.fire } }

      refute_predicate self, :signal_pending?
    end

    it 'raises what the block raises' do
      assert_raises(ArgumentError) { @abort.window { raise ArgumentError } }
    end

    it 'closes when the block raises' do
      begin
        @abort.window { raise ArgumentError }
      rescue ArgumentError
        nil
      end
      @abort.fire

      refute_predicate self, :signal_pending?
    end
  end

  describe '#fire' do
    it 'does nothing with no window open' do
      @abort.fire

      refute_predicate self, :signal_pending?
    end

    it 'does nothing once the window has closed' do
      @abort.window { :done }
      @abort.fire

      refute_predicate self, :signal_pending?
    end

    it 'signals a window once' do
      result = @abort.window do
        shielded { 2.times { @abort.fire } }
        :done
      end

      assert_equal :done, result
    end
  end
end
