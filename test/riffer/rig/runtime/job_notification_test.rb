# frozen_string_literal: true

require 'test_helper'

describe Riffer::Rig::Runtime::JobNotification do
  describe '#to_h' do
    it 'marks the user message hash as a job notification' do
      notification = Riffer::Rig::Runtime::JobNotification.new('<background-job id="a1b2c3d4">')

      assert_equal(
        { role: :user, content: '<background-job id="a1b2c3d4">', job_notification: true },
        notification.to_h
      )
    end
  end
end
