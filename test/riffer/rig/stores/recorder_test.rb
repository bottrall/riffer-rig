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
  attr_reader :appended, :ids

  def initialize(seeded = [])
    @seeded = seeded
    @appended = []
    @ids = []
  end

  def append(id, entry)
    @ids << id
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

  def on_message(&block)
    @message_listener = block
  end

  def on_model_change(&block)
    @model_listener = block
  end

  def announce(message)
    @message_listener.call(message)
  end

  def switch(model)
    @model_listener.call(model)
  end
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

  def assistant(content = 'hi')
    Riffer::Messages::Assistant.new(content)
  end

  def notification
    Riffer::Rig::Runtime::JobNotification.new('<background-job id="a1b2c3d4">')
  end

  def header(title = 'hello')
    Riffer::Rig::Stores::Header.new(
      schema_version: Riffer::Rig::Stores::JSONL::HEADER_VERSION,
      id: 'aaa',
      cwd: '/project',
      created_at: '2026-10-11T12:00:00Z',
      model: 'mock/test',
      riffer_rig_version: Riffer::Rig::VERSION,
      riffer_version: Riffer::VERSION,
      title: title
    )
  end

  def stream_hooks(recording)
    registrar = Riffer::Rig::Registrar.new(Riffer::Rig::Stores::Recorder::EXTENSION_NAME)
    Riffer::Rig::Stores::Recorder.extension(recording).run(registrar)
    registrar.hooks.fetch(:stream)
  end

  def stamps(store)
    store.appended.grep_v(Riffer::Rig::Stores::Header).map(&:recorded_time)
  end

  describe '#attach' do
    it 'starts a fresh session on the clock, whatever the store holds' do
      seeded = [Riffer::Rig::Stores::MessageEntry.new(message: user.to_h, recorded_at: Riffer::Rig::Stores::Timestamp.dump(at(9)))]
      store = SeededStore.new(seeded)
      recorder(store, [at(1), at(2)]).message(user)

      assert_equal [at(2)], stamps(store)
    end

    it 'never steps back from the session it resumes' do
      seeded = [Riffer::Rig::Stores::MessageEntry.new(message: user.to_h, recorded_at: Riffer::Rig::Stores::Timestamp.dump(at(9)))]
      store = SeededStore.new(seeded)
      recording = recorder(store, [at(3), at(10)], resumed: true)
      2.times { recording.message(user) }

      assert_equal [at(9), at(10)], stamps(store)
    end

    it 'skips the header of the session it resumes' do
      seeded = [header, Riffer::Rig::Stores::MessageEntry.new(message: user.to_h, recorded_at: Riffer::Rig::Stores::Timestamp.dump(at(9)))]
      store = SeededStore.new(seeded)
      recorder(store, [at(3)], resumed: true).message(user)

      assert_equal [at(9)], stamps(store)
    end

    it 'resumes a session recorded without timestamps on the clock' do
      store = SeededStore.new([Riffer::Rig::Stores::MessageEntry.new(message: user.to_h)])
      recorder(store, [at(3)], resumed: true).message(user)

      assert_equal [at(3)], stamps(store)
    end

    it 'records the messages the runtime announces' do
      store = SeededStore.new
      runtime = ObservedRuntime.new
      Riffer::Rig::Stores::Recorder.new(store: store, clock: SteppingClock.new([at(1), at(2)])).attach(runtime)
      runtime.announce(user)

      assert_equal [user.to_h], store.appended.grep(Riffer::Rig::Stores::MessageEntry).map(&:message)
    end

    it 'records the model changes the runtime announces' do
      store = SeededStore.new
      runtime = ObservedRuntime.new
      Riffer::Rig::Stores::Recorder.new(store: store, clock: SteppingClock.new([at(1), at(2), at(3)])).attach(runtime)
      runtime.announce(user)
      runtime.switch('mock/other')

      assert_equal ['mock/other'], store.appended.grep(Riffer::Rig::Stores::ModelEntry).map(&:model)
    end
  end

  describe '#skill' do
    it 'records the skill the event names' do
      store = SeededStore.new
      recording = recorder(store, [at(1), at(2), at(3)])
      recording.message(user)
      recording.skill(Riffer::StreamEvents::SkillActivation.new('a'))

      assert_equal ['a'], store.appended.grep(Riffer::Rig::Stores::SkillEntry).map(&:skill)
    end

    it 'stamps a skill entry with the clock' do
      store = SeededStore.new
      recording = recorder(store, [at(1), at(2)], resumed: true)
      recording.message(user)
      recording.skill(Riffer::StreamEvents::SkillActivation.new('a'))

      assert_equal at(2), store.appended.grep(Riffer::Rig::Stores::SkillEntry).first.recorded_time
    end
  end

  describe '#message' do
    it 'titles the header with the first line of the first prompt' do
      store = SeededStore.new
      recorder(store, [at(1), at(2)]).message(user("  first line \nsecond line"))

      assert_equal 'first line', store.appended.first.title
    end

    it 'leaves the header untitled when the first message is not a prompt' do
      store = SeededStore.new
      recorder(store, [at(1), at(2)]).message(assistant)

      assert_equal '', store.appended.first.title
    end

    it 'holds a job notification that lands before the header' do
      store = SeededStore.new
      recorder(store, [at(1)]).message(notification)

      assert_empty store.appended
    end

    it 'titles the header with the first prompt after a job notification' do
      store = SeededStore.new
      recording = recorder(store, [at(1), at(2), at(3)])
      recording.message(notification)
      recording.message(user('first prompt'))

      assert_equal 'first prompt', store.appended.first.title
    end

    it 'records a held job notification ahead of the prompt that wrote the header' do
      store = SeededStore.new
      recording = recorder(store, [at(1), at(2), at(3)])
      recording.message(notification)
      recording.message(user)

      assert_equal [notification.to_h, user.to_h], store.appended.grep(Riffer::Rig::Stores::MessageEntry).map(&:message)
    end

    it 'describes the runtime in the header' do
      store = SeededStore.new
      recorder(store, [at(1), at(2)]).message(user)

      assert_equal %w[aaa /project mock/test], store.appended.first.to_h.values_at(:id, :cwd, :model)
    end

    it 'stamps the header with the clock' do
      store = SeededStore.new
      recorder(store, [at(1), at(2)]).message(user)

      assert_equal '2026-10-11T12:00:01Z', store.appended.first.created_at
    end

    it 'writes the header before the first message' do
      store = SeededStore.new
      recorder(store, [at(1), at(2)]).message(user)

      assert_equal [Riffer::Rig::Stores::Header, Riffer::Rig::Stores::MessageEntry], store.appended.map(&:class)
    end

    it 'keys the header and the message by the runtime id' do
      store = SeededStore.new
      recorder(store, [at(1), at(2)]).message(user)

      assert_equal %w[aaa aaa], store.ids
    end

    it 'writes the header once' do
      store = SeededStore.new
      recording = recorder(store, [at(1), at(2), at(3)])
      2.times { recording.message(user) }

      assert_equal 1, store.appended.grep(Riffer::Rig::Stores::Header).size
    end

    it 'writes no header into the session it resumes' do
      store = SeededStore.new
      recorder(store, [at(1)], resumed: true).message(user)

      assert_empty store.appended.grep(Riffer::Rig::Stores::Header)
    end

    it 'records the message' do
      store = SeededStore.new
      recorder(store, [at(1), at(2)]).message(user('hello'))

      assert_equal [user('hello').to_h], store.appended.grep(Riffer::Rig::Stores::MessageEntry).map(&:message)
    end

    it 'records one entry per message' do
      store = SeededStore.new
      recording = recorder(store, [at(1), at(2), at(3)])
      recording.message(user)
      recording.message(assistant)

      assert_equal [user.to_h, assistant.to_h], store.appended.grep(Riffer::Rig::Stores::MessageEntry).map(&:message)
    end

    it 'stamps a message entry with the clock' do
      store = SeededStore.new
      recorder(store, [at(1), at(2)]).message(user)

      assert_equal [at(2)], stamps(store)
    end

    it 'never steps back when the clock does' do
      store = SeededStore.new
      recording = recorder(store, [at(5), at(3), at(4), at(6)], resumed: true)
      4.times { recording.message(user) }

      assert_equal [at(5), at(5), at(5), at(6)], stamps(store)
    end
  end

  describe '#switched' do
    it 'holds an entry until the header is written' do
      store = SeededStore.new
      recorder(store, [at(1)]).switched('mock/other')

      assert_empty store.appended
    end

    it 'writes a held entry after the header, ahead of the first message' do
      store = SeededStore.new
      recording = recorder(store, [at(1), at(2), at(3)])
      recording.switched('mock/other')
      recording.message(user)

      assert_equal(
        [Riffer::Rig::Stores::Header, Riffer::Rig::Stores::ModelEntry, Riffer::Rig::Stores::MessageEntry],
        store.appended.map(&:class)
      )
    end

    it 'records the model' do
      store = SeededStore.new
      recording = recorder(store, [at(1), at(2), at(3)])
      recording.message(user)
      recording.switched('mock/other')

      assert_equal ['mock/other'], store.appended.grep(Riffer::Rig::Stores::ModelEntry).map(&:model)
    end

    it 'stamps a model entry with the clock' do
      store = SeededStore.new
      recording = recorder(store, [at(1), at(2)], resumed: true)
      recording.switched('mock/other')
      recording.message(user)

      assert_equal at(1), store.appended.grep(Riffer::Rig::Stores::ModelEntry).first.recorded_time
    end

    it 'stamps an entry held for the header when it happened' do
      store = SeededStore.new
      recording = recorder(store, [at(1), at(2), at(3)])
      recording.switched('mock/other')
      recording.message(user)

      assert_equal [at(1), at(3)], stamps(store)
    end
  end

  describe '.extension' do
    it 'records a skill activation off the stream' do
      store = SeededStore.new
      recording = recorder(store, [at(1), at(2), at(3)])
      recording.message(user)
      stream_hooks(recording).each { |hook| hook.call(Riffer::StreamEvents::SkillActivation.new('a')) }

      assert_equal ['a'], store.appended.grep(Riffer::Rig::Stores::SkillEntry).map(&:skill)
    end

    it 'records nothing for any other stream event' do
      store = SeededStore.new
      recording = recorder(store, [at(1), at(2)])
      recording.message(user)
      stream_hooks(recording).each { |hook| hook.call(Riffer::StreamEvents::TextDelta.new('hi')) }

      assert_equal [Riffer::Rig::Stores::Header, Riffer::Rig::Stores::MessageEntry], store.appended.map(&:class)
    end
  end
end
