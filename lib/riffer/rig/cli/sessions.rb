# frozen_string_literal: true

class Riffer::Rig::CLI::Sessions
  # The terminal's sessions collaborator: translates the parsed flags into
  # Loader builds and store lookups, so the host never sees the flags.
  #
  # @rbs @flags: Riffer::Rig::CLI::Flags
  # @rbs @env: Riffer::Rig::Env | Riffer::Rig::Env::Invalid
  # @rbs @cwd: String
  # @rbs @home: String
  # @rbs @store: Riffer::Rig::Stores::_Store?
  # @rbs @loader: Riffer::Rig::Loader?

  # @rbs flags: Riffer::Rig::CLI::Flags
  # @rbs env: Riffer::Rig::Env | Riffer::Rig::Env::Invalid
  # @rbs cwd: String
  # @rbs home: String
  # @rbs return: void
  def initialize(flags:, env:, cwd:, home:)
    @flags = flags
    @env = env
    @cwd = cwd
    @home = home
    @store = flags.save ? Riffer::Rig::Stores::JSONL.new(home: home) : nil
    @loader = nil
  end

  # @rbs host: Riffer::Rig::Hosts::_Host
  # @rbs return: Riffer::Rig::Runtime
  def start(host)
    started = find(host)
    host.notify(missing) if started.nil? && asked?

    started || loader(host).runtime(**@flags.keywords)
  end

  # @rbs host: Riffer::Rig::Hosts::_Host
  # @rbs return: Riffer::Rig::Runtime?
  def find(host)
    id = resume_id
    if id
      loader(host).resume(id, **@flags.keywords)
    elsif @flags.continue
      loader(host).continue(**@flags.keywords)
    end
  end

  # @rbs host: Riffer::Rig::Hosts::_Host
  # @rbs return: Riffer::Rig::Runtime
  def fresh(host)
    loader(host).runtime(**@flags.keywords)
  end

  # @rbs host: Riffer::Rig::Hosts::_Host
  # @rbs id: String
  # @rbs return: Riffer::Rig::Runtime?
  def resume(host, id)
    loader(host).resume(id, **@flags.keywords)
  end

  # @rbs host: Riffer::Rig::Hosts::_Host
  # @rbs all: bool
  # @rbs return: Array[::Riffer::Rig::Terminal::Session]
  def list(host, all: false)
    loader(host)
      .list(all: all)
      # The id breaks mtime ties so the rows never shuffle under sort_by.
      .sort_by { |header| [header.updated ? -header.updated.to_f : 0.0, header.id] }
      .map { |header| row(header) }
  end

  # @rbs host: Riffer::Rig::Hosts::_Host
  # @rbs id: String
  # @rbs return: void
  def delete(host, id)
    loader(host).delete(id)
  end

  # @rbs return: bool
  def asked?
    resume_id ? true : @flags.continue
  end

  # @rbs id: String?
  # @rbs return: String
  def missing(id = nil)
    id ||= resume_id
    id ? "No saved session #{id}." : 'No saved session in this directory.'
  end

  private

  # @rbs header: Riffer::Rig::Stores::Header
  # @rbs return: ::Riffer::Rig::Terminal::Session
  def row(header)
    Riffer::Rig::Terminal::Session.new(
      id: header.id,
      title: header.title.gsub(/\s+/, ' ').strip,
      updated: header.updated,
      cwd: header.cwd
    )
  end

  # @rbs host: Riffer::Rig::Hosts::_Host
  # @rbs return: Riffer::Rig::Loader
  def loader(host)
    @loader ||= Riffer::Rig::Loader.new(cwd: @cwd, host: host, env: @env, home: @home, store: @store)
  end

  # @rbs return: String?
  def resume_id
    id = @flags.resume
    id unless id.nil? || id.empty?
  end
end
