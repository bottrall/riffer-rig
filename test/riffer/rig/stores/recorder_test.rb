# frozen_string_literal: true

require 'test_helper'

class SteppingClock
  def initialize(times)
    @times = times
  end

  def now
    @times.shift
  end
end

class SeededStore
  attr_reader :appended

  def initialize(seeded = [])
    @seeded = seeded
    @appended = []
  end

  def append(_id, entry)
    @appended << entry
  end

  def read(_id)
    @seeded
  end
end

class ObservedRuntime
  attr_reader :id, :cwd, :model

  def initialize
    @id = 'aaa'
    @cwd = '/project'
    @model = 'mock/test'
  end

  def on_message; end

  def on_model_change; end
end

describe Riffer::Rig::Stores::Recorder do
  def at(seconds)
    Time.utc(2026, 10, 11, 12, 0, seconds)
  end

  def recorder(store, times, resumed: false)
    Riffer::Rig::Stores::Recorder.new(store: store, resumed: resumed, clock: SteppingClock.new(times)).tap do |recorder|
      recorder.attach(ObservedRuntime.new)
    end
  end

  def user(content = 'hello')
    Riffer::Messages::User.new(content)
  end

  def stamps(store)
    store.appended.grep_v(Riffer::Rig::Stores::Header).map(&:recorded_at)
  end

  it 'stamps the header with the clock' do
    store = SeededStore.new
    recorder(store, [at(1), at(2)]).message(user)

    assert_equal '2026-10-11T12:00:01Z', store.appended.first.created_at
  end

  it 'stamps a message entry with the clock' do
    store = SeededStore.new
    recorder(store, [at(1), at(2)]).message(user)

    assert_equal [at(2)], stamps(store)
  end

  it 'stamps a model entry with the clock' do
    store = SeededStore.new
    recording = recorder(store, [at(1), at(2)], resumed: true)
    recording.switched('mock/other')
    recording.message(user)

    assert_equal at(1), store.appended.grep(Riffer::Rig::Stores::ModelEntry).first.recorded_at
  end

  it 'stamps a skill entry with the clock' do
    store = SeededStore.new
    recording = recorder(store, [at(1), at(2)], resumed: true)
    recording.message(user)
    recording.skill(Riffer::StreamEvents::SkillActivation.new('a'))

    assert_equal at(2), store.appended.grep(Riffer::Rig::Stores::SkillEntry).first.recorded_at
  end

  it 'stamps an entry held for the header when it happened' do
    store = SeededStore.new
    recording = recorder(store, [at(1), at(2), at(3)])
    recording.switched('mock/other')
    recording.message(user)

    assert_equal [at(1), at(3)], stamps(store)
  end

  it 'never steps back when the clock does' do
    store = SeededStore.new
    recording = recorder(store, [at(5), at(3), at(4), at(6)], resumed: true)
    4.times { recording.message(user) }

    assert_equal [at(5), at(5), at(5), at(6)], stamps(store)
  end

  it 'never steps back from the session it resumes' do
    seeded = [Riffer::Rig::Stores::MessageEntry.new(message: user.to_h, recorded_at: at(9))]
    store = SeededStore.new(seeded)
    recording = recorder(store, [at(3), at(10)], resumed: true)
    2.times { recording.message(user) }

    assert_equal [at(9), at(10)], stamps(store)
  end

  it 'resumes a session recorded without timestamps on the clock' do
    store = SeededStore.new([Riffer::Rig::Stores::MessageEntry.new(message: user.to_h)])
    recorder(store, [at(3)], resumed: true).message(user)

    assert_equal [at(3)], stamps(store)
  end
end
