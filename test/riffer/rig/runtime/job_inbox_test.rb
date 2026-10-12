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
end
