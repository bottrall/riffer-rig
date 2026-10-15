# frozen_string_literal: true

require 'test_helper'

describe Riffer::Rig::Runtime::JobNotification do
  describe '.from_hash' do
    it 'rebuilds the exit count of a notification that started a follow-up' do
      stored = { role: 'user', content: '<background-job id="a1b2c3d4">', job_notification: true, follow_up_exits: 2 }

      assert_equal 2, Riffer::Rig::Runtime::JobNotification.from_hash(stored).follow_up_exits
    end
  end

  describe '#initialize' do
    it 'takes the files riffer joins into a message of its class' do
      notification = Riffer::Rig::Runtime::JobNotification.new('<background-job id="a1b2c3d4">')

      assert_instance_of Riffer::Rig::Runtime::JobNotification, notification + Riffer::Messages::User.new('Go')
    end
  end

  describe '#to_h' do
    it 'marks the user message hash as a job notification' do
      notification = Riffer::Rig::Runtime::JobNotification.new('<background-job id="a1b2c3d4">')

      assert_equal(
        { role: :user, content: '<background-job id="a1b2c3d4">', job_notification: true },
        notification.to_h
      )
    end

    it 'records the exit count of a notification that started a follow-up' do
      notification = Riffer::Rig::Runtime::JobNotification.new('<background-job id="a1b2c3d4">', follow_up_exits: 2)

      assert_equal 2, notification.to_h[:follow_up_exits]
    end
  end
end
