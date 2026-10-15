# frozen_string_literal: true

require 'test_helper'

describe Riffer::Rig::Runtime::JobInbox do
  def setup
    @inbox = Riffer::Rig::Runtime::JobInbox.new
    @completion = Riffer::Rig::Runtime::JobCompletion.new(
      job_id: 'abc123',
      command: 'true',
      exit_status: 0,
      duration: 1.5,
      output_path: '/tmp/riffer-rig-job-test',
      tail: ''
    )
  end

  describe '#push' do
    it 'drops a completion once closed' do
      @inbox.close
      @inbox.push(@completion)

      assert_empty @inbox.drain
    end

    it 'calls no subscriber once closed' do
      received = []
      @inbox.subscribe { |completion| received << completion }
      @inbox.close
      @inbox.push(@completion)

      assert_empty received
    end

    it 'calls each subscriber with the completion' do
      received = []
      2.times { @inbox.subscribe { |completion| received << completion } }
      @inbox.push(@completion)

      assert_equal [@completion, @completion], received
    end
  end

  describe '#size' do
    it 'counts the completions pushed since the last drain' do
      @inbox.push(@completion)
      @inbox.drain
      2.times { @inbox.push(@completion) }

      assert_equal 2, @inbox.size
    end
  end

  describe '#drain' do
    it 'returns the completions pushed since the last drain' do
      @inbox.push(@completion)

      assert_equal [@completion], @inbox.drain
    end

    it 'empties the inbox' do
      @inbox.push(@completion)
      @inbox.drain

      assert_empty @inbox.drain
    end
  end

  describe '#await' do
    def pushing_later(completion)
      Thread.new do
        sleep 0.05
        @inbox.push(completion)
      end
    end

    it 'is true at once while a completion is pending' do
      @inbox.push(@completion)

      assert @inbox.await(0)
    end

    it 'leaves a pending completion for the drain' do
      @inbox.push(@completion)
      @inbox.await(0)

      assert_equal [@completion], @inbox.drain
    end

    it 'is false once closed' do
      @inbox.close

      refute @inbox.await(nil)
    end

    it 'is false when the timeout passes with nothing pushed' do
      refute @inbox.await(0.05)
    end

    it 'is true when a completion is pushed during the wait' do
      pusher = pushing_later(@completion)

      assert @inbox.await(5)
    ensure
      pusher&.join
    end

    it 'waits without a timeout for a completion' do
      pusher = pushing_later(@completion)

      assert @inbox.await(nil)
    ensure
      pusher&.join
    end

    it 'is false when closed during the wait' do
      closer = Thread.new do
        sleep 0.05
        @inbox.close
      end

      refute @inbox.await(nil)
    ensure
      closer&.join
    end
  end
end
