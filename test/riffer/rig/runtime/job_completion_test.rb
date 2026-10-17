# frozen_string_literal: true

require 'test_helper'

describe Riffer::Rig::Runtime::JobCompletion do
  it 'freezes itself' do
    completion = Riffer::Rig::Runtime::JobCompletion.new(
      job_id: 'abc123',
      command: 'true',
      exit_status: 0,
      signal: nil,
      duration: 1.5,
      output_path: '/tmp/riffer-rig-job-test',
      tail: ''
    )

    assert_predicate completion, :frozen?
  end
end
