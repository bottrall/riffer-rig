# frozen_string_literal: true

require 'time'

class Riffer::Rig::Stores::Recorder
  EXTENSION_NAME = 'session-store' #: String

  # @rbs @store: Riffer::Rig::Stores::_Store
  # @rbs @resumed: bool
  # @rbs @runtime: Riffer::Rig::Runtime?
  # @rbs @header_written: bool
  # @rbs @pending: Array[Hash[Symbol, untyped]]
  # @rbs @title: String?

  # Records one Loader-built session into the store: the header on the first
  # message (its title needs the first prompt), one entry per message, one per
  # model switch and one per skill activation. Entries that land before the
  # first message (a /model before the first prompt) wait for the header. A
  # resumed session appends to the file its first run wrote, so it rewrites
  # no header.
  # @rbs store: Riffer::Rig::Stores::_Store
  # @rbs resumed: bool
  # @rbs return: void
  def initialize(store:, resumed: false)
    @store = store
    @resumed = resumed
    @runtime = nil
    @header_written = false
    @pending = []
    @title = nil
  end

  # @rbs runtime: Riffer::Rig::Runtime
  # @rbs return: void
  def attach(runtime)
    @runtime = runtime
    runtime.on_message { |message| message(message) }
    runtime.on_model_change { |model| switched(model) }
  end

  # @rbs event: Riffer::StreamEvents::SkillActivation
  # @rbs return: void
  def skill(event)
    record(type: 'skill', skill: event.name)
  end

  # @rbs message: Riffer::Messages::Base
  # @rbs return: void
  def message(message)
    @title ||= one_line(message.content) if message.is_a?(Riffer::Messages::User)
    write_header unless @header_written
    record(type: 'message', message: message.to_h)
  end

  # @rbs model: String
  # @rbs return: void
  def switched(model)
    record(type: 'model', model: model)
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

  # @rbs entry: Hash[Symbol, untyped]
  # @rbs return: void
  def record(entry)
    unless @header_written
      @pending << entry
      return
    end

    @store.append(runtime.id, entry)
  end

  # @rbs return: void
  def write_header
    @header_written = true
    @store.append(runtime.id, header_entry) unless @resumed
    @pending.each { |entry| @store.append(runtime.id, entry) }
    @pending.clear
  end

  # @rbs return: Hash[Symbol, untyped]
  def header_entry
    {
      type: 'header',
      schema_version: Riffer::Rig::Stores::JSONL::HEADER_VERSION,
      id: runtime.id,
      cwd: runtime.cwd,
      created_at: Time.now.utc.iso8601,
      model: runtime.model,
      riffer_rig_version: Riffer::Rig::VERSION,
      riffer_version: Riffer::VERSION,
      title: @title.to_s
    }
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
