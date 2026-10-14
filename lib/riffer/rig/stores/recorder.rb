# frozen_string_literal: true

require 'time'

class Riffer::Rig::Stores::Recorder
  EXTENSION_NAME = 'session-store' #: String

  # @rbs @store: Riffer::Rig::Stores::_Store
  # @rbs @resumed: bool
  # @rbs @clock: singleton(Time)
  # @rbs @runtime: Riffer::Rig::Runtime?
  # @rbs @header_written: bool
  # @rbs @pending: Array[Riffer::Rig::Stores::entry]
  # @rbs @last_recorded_at: Time?

  # Records one Loader-built session into the store: the header on the first
  # message (its title needs the first prompt), one entry per message, one per
  # model switch and one per skill activation. Entries that land before the
  # first message (a /model before the first prompt) wait for the header. A
  # resumed session appends to the file its first run wrote, so it rewrites
  # no header.
  # @rbs store: Riffer::Rig::Stores::_Store
  # @rbs resumed: bool
  # @rbs clock: singleton(Time)
  # @rbs return: void
  def initialize(store:, resumed: false, clock: Time)
    @store = store
    @resumed = resumed
    @clock = clock
    @runtime = nil
    @header_written = false
    @pending = []
    @last_recorded_at = nil
  end

  # @rbs runtime: Riffer::Rig::Runtime
  # @rbs return: void
  def attach(runtime)
    @runtime = runtime
    @last_recorded_at = last_recorded_at(runtime.id) if @resumed
    runtime.on_message { |message| message(message) }
    runtime.on_model_change { |model| switched(model) }
  end

  # @rbs event: Riffer::StreamEvents::SkillActivation
  # @rbs return: void
  def skill(event)
    record(Riffer::Rig::Stores::SkillEntry.new(skill: event.name, recorded_at: Riffer::Rig::Stores::Timestamp.dump(stamp)))
  end

  # @rbs message: Riffer::Messages::Base
  # @rbs return: void
  def message(message)
    # A job notification is no prompt to title the session from, so it waits
    # for the header like any other entry that lands before one.
    write_header(message) unless @header_written || message.is_a?(Riffer::Rig::Runtime::JobNotification)
    record(Riffer::Rig::Stores::MessageEntry.new(message: message.to_h, recorded_at: Riffer::Rig::Stores::Timestamp.dump(stamp)))
  end

  # @rbs model: String
  # @rbs return: void
  def switched(model)
    record(Riffer::Rig::Stores::ModelEntry.new(model: model, recorded_at: Riffer::Rig::Stores::Timestamp.dump(stamp)))
  end

  # The extension rides the build as its last extension, so its :stream hook
  # sees the model's skill activations. Per build, unlike the extensions in
  # the process registry: the hook closes over this build's recorder.
  # @rbs recorder: Riffer::Rig::Stores::Recorder
  # @rbs return: Riffer::Rig::Extension
  def self.extension(recorder)
    Riffer::Rig::Extension.new(EXTENSION_NAME) do |registrar|
      registrar.on(:stream) do |event|
        case event
        when Riffer::StreamEvents::SkillActivation then recorder.skill(event)
        end
      end
    end
  end

  private

  # @rbs entry: Riffer::Rig::Stores::entry
  # @rbs return: void
  def record(entry)
    unless @header_written
      @pending << entry
      return
    end

    @store.append(runtime.id, entry)
  end

  # @rbs message: Riffer::Messages::Base
  # @rbs return: void
  def write_header(message)
    @header_written = true
    @store.append(runtime.id, header_entry(message)) unless @resumed
    @pending.each { |entry| @store.append(runtime.id, entry) }
    @pending.clear
  end

  # @rbs message: Riffer::Messages::Base
  # @rbs return: ::Riffer::Rig::Stores::Header
  def header_entry(message)
    Riffer::Rig::Stores::Header.new(
      schema_version: Riffer::Rig::Stores::JSONL::HEADER_VERSION,
      id: runtime.id,
      cwd: runtime.cwd,
      created_at: @clock.now.getutc.iso8601,
      model: runtime.model,
      riffer_rig_version: Riffer::Rig::VERSION,
      riffer_version: Riffer::VERSION,
      title: message.is_a?(Riffer::Messages::User) ? one_line(message.content) : ''
    )
  end

  # @rbs return: Time
  def stamp
    now = @clock.now
    last = @last_recorded_at
    # A wall clock can step backwards; the entries of one session never do.
    @last_recorded_at = last && last > now ? last : now
  end

  # @rbs id: String
  # @rbs return: Time?
  def last_recorded_at(id)
    @store.read(id).filter_map { |entry| entry.recorded_time unless entry.is_a?(Riffer::Rig::Stores::Header) }.max
  end

  # @rbs content: String
  # @rbs return: String
  def one_line(content)
    content.lines.first.to_s.strip
  end

  # The recorder is built before the Runtime it records; every entry arrives
  # after attach, so the runtime is always there by then.
  # @rbs return: Riffer::Rig::Runtime
  def runtime
    @runtime || raise(StandardError, 'Recorder used before attach')
  end
end
