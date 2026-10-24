# frozen_string_literal: true

class Riffer::Rig::Loader
  class ConfigurationError < StandardError; end

  # @rbs @cwd: String
  # @rbs @host: Riffer::Rig::Hosts::_Host
  # @rbs @env: Riffer::Rig::Env
  # @rbs @home: String
  # @rbs @riffer_config: Riffer::Config
  # @rbs @store: Riffer::Rig::Stores::_Store | nil
  # @rbs @source: Riffer::Rig::Loader::ExtensionSource
  # @rbs @reloaders: ObjectSpace::WeakKeyMap[Riffer::Rig::Runtime, Riffer::Rig::Loader::Reloader]

  # @rbs cwd: String
  # @rbs host: Riffer::Rig::Hosts::_Host
  # @rbs env: Riffer::Rig::Env | Riffer::Rig::Env::Invalid
  # @rbs home: String
  # @rbs riffer_config: Riffer::Config
  # @rbs store: Riffer::Rig::Stores::_Store | nil
  # @rbs options: Riffer::Rig::Loader::Options
  # @rbs reload: (:auto | :manual | nil)
  # @rbs extra_extensions: Array[Riffer::Rig::Extension]
  # @rbs snapshot: (Riffer::Rig::Runtime::Snapshot | Hash[Symbol, untyped])?
  # @rbs return: Riffer::Rig::Runtime
  def self.runtime(
    cwd:,
    host:,
    env: Riffer::Rig::Env.load,
    home: Dir.home,
    riffer_config: Riffer.config,
    store: Riffer::Rig::Stores::JSONL.new(home: home),
    options: Options.new,
    reload: nil,
    extra_extensions: [],
    snapshot: nil
  )
    new(cwd:, host:, env:, home:, riffer_config:, store:).runtime(options, reload:, extra_extensions:, snapshot:)
  end

  # @rbs cwd: String
  # @rbs host: Riffer::Rig::Hosts::_Host
  # @rbs env: Riffer::Rig::Env | Riffer::Rig::Env::Invalid
  # @rbs home: String
  # @rbs riffer_config: Riffer::Config
  # @rbs store: Riffer::Rig::Stores::_Store | nil
  # @rbs return: void
  def initialize(
    cwd:,
    host:,
    env: Riffer::Rig::Env.load,
    home: Dir.home,
    riffer_config: Riffer.config,
    store: Riffer::Rig::Stores::JSONL.new(home: home)
  )
    raise ConfigurationError, env.message if env.is_a?(Riffer::Rig::Env::Invalid)

    @cwd = cwd
    @host = host
    @env = env
    @home = home
    @riffer_config = riffer_config
    @store = store
    @source = Riffer::Rig::Loader::ExtensionSource.new(cwd: cwd, home: home, host: host)
    @reloaders = ObjectSpace::WeakKeyMap.new
  end

  # @rbs options: Riffer::Rig::Loader::Options
  # @rbs reload: (:auto | :manual | nil)
  # @rbs extra_extensions: Array[Riffer::Rig::Extension]
  # @rbs snapshot: (Riffer::Rig::Runtime::Snapshot | Hash[Symbol, untyped])?
  # @rbs return: Riffer::Rig::Runtime
  def runtime(options = Options.new, reload: nil, extra_extensions: [], snapshot: nil)
    settings = merged_settings
    raise ConfigurationError, settings if settings.is_a?(String)

    document = Riffer::Rig::Settings::Document.new(settings)
    selected = select_model(options.model || @env.model || document.model)
    rejection = Riffer::Rig::Loader::Reasoning.rejection(options.reasoning, @env.reasoning)
    raise ConfigurationError, rejection if rejection

    provider = Riffer::Rig::Settings::ModelOptions.provider_for(selected).to_s
    ensure_sdk(provider)
    credentials = install_credentials(provider)
    raise ConfigurationError, credentials if credentials.is_a?(String)

    @riffer_config.catalog_files = document.catalog_files
    stripped = { skills: options.skills, agents_md: options.agents_md }.reject { |_name, kept| kept }.keys
    discovered = options.extensions ? @source.discover(autoload: document.autoload) : [] #: Array[Riffer::Rig::Extension]

    saved = snapshot && Riffer::Rig::Runtime::Snapshot.of(snapshot)
    recorder = recorder_for(document, resumed: !saved.nil?)
    recording = recorder ? [Riffer::Rig::Stores::Recorder.extension(recorder)] : [] #: Array[Riffer::Rig::Extension]

    saved = snapshot_without_forced(saved, options)

    built = Riffer::Rig::Runtime.new(
      selected,
      extensions: bundled(document, stripped) + discovered + extra_extensions + recording,
      tools: options.tools,
      settings: settings,
      host: @host,
      cwd: @cwd,
      max_steps: options.max_steps,
      credentials: { provider.to_sym => credentials },
      env: @env,
      auth_path: home_auth_path,
      reasoning: Riffer::Rig::Loader::Reasoning.forced(options.reasoning, @env.reasoning),
      riffer_config: @riffer_config,
      model_options: Riffer::Rig::Settings::ModelOptions.model_options(selected),
      native_tools: document.native_tools,
      snapshot: saved
    )
    reloader = Riffer::Rig::Loader::Reloader.new(
      source: @source,
      host: @host,
      settings: -> { merged_settings },
      credentials: ->(name) { install_credentials(name) },
      extensions: ->(current, found) { bundled(current, stripped) + extra_extensions + found + recording },
      rediscovers: options.extensions,
      mode: reload
    )
    @reloaders[built] = reloader
    built.install_command(Riffer::Rig::Commands::Reload.command(reloader))
    store = @store
    built.install_command(Riffer::Rig::Commands::Trace.command(store)) if store && recorder
    unless (reload || document.reload) == :manual
      built.install_reload_check(->(runtime) { _ = reloader.reload(runtime) })
    end
    recorder&.attach(built)
    built
  end

  # @rbs options: Riffer::Rig::Loader::Options
  # @rbs return: Riffer::Rig::Runtime?
  def continue(options = Options.new)
    store = @store
    return nil unless store

    latest = store.list(cwd: @cwd).max_by { |header| header.updated || Time.at(0) }
    return nil unless latest

    resume(latest.id, options)
  end

  # @rbs id: String
  # @rbs options: Riffer::Rig::Loader::Options
  # @rbs extra_extensions: Array[Riffer::Rig::Extension]
  # @rbs return: Riffer::Rig::Runtime?
  def resume(id, options = Options.new, extra_extensions: [])
    store = @store
    return nil unless store

    entries = store.read(id)
    return nil if entries.empty?

    runtime(options, extra_extensions: extra_extensions, snapshot: Riffer::Rig::Stores::Entries.snapshot(entries, id))
  end

  # A host tier may not name the store, so the messages it replays come from
  # here, in the order they were recorded.
  # @rbs id: String
  # @rbs return: Array[Hash[Symbol, untyped]]
  def messages(id)
    store = @store
    return [] unless store

    Riffer::Rig::Stores::Entries.messages(store.read(id))
  end

  # @rbs all: bool
  # @rbs return: Array[::Riffer::Rig::Stores::Header]
  def list(all: false)
    store = @store
    return [] unless store

    all ? store.list : store.list(cwd: @cwd)
  end

  # @rbs id: String
  # @rbs return: void
  def delete(id)
    store = @store
    return unless store

    store.delete(id)
  end

  # @rbs runtime: Riffer::Rig::Runtime
  # @rbs force: bool
  # @rbs return: (Riffer::Rig::Runtime | String)
  def reload(runtime, force: false)
    reloader = @reloaders[runtime]
    reloader ? reloader.reload(runtime, force: force) : runtime
  end

  private

  # @rbs return: (Hash[Symbol, untyped] | String)
  def merged_settings
    home = read_settings(home_settings_path)
    return home if home.is_a?(String)

    project = read_settings(File.join(@cwd, '.riffer', 'settings.json'))
    return project if project.is_a?(String)

    Riffer::Rig::Settings.merge(home, project)
  end

  # @rbs path: String
  # @rbs return: (Hash[Symbol, untyped] | String)
  def read_settings(path)
    source = Riffer::Rig::Settings::File.read(path)
    return source if source.is_a?(String) || source.fetch(:model, '').is_a?(String)

    "#{path} sets \"model\" to a value that is not a string"
  end

  # @rbs document: Riffer::Rig::Settings::Document
  # @rbs stripped: Array[Symbol]
  # @rbs return: Array[Riffer::Rig::Extension]
  def bundled(document, stripped)
    Riffer::Rig::Bundled::BY_NAME.except(*document.disabled.map(&:to_sym), *stripped).values
  end

  # @rbs configured: String?
  # @rbs return: String
  def select_model(configured)
    model = configured || ask_for_model
    rejection = Riffer::Rig::Settings::ModelOptions.rejection(model)
    raise ConfigurationError, rejection if rejection

    refusal = Riffer::Rig::Settings::File.store_model(model, path: home_settings_path) unless configured
    raise ConfigurationError, refusal if refusal

    model
  end

  # @rbs return: String
  def ask_for_model
    reply = @host.ask(onboarding_question) if @host.capabilities.include?(:ask)
    answer = reply.to_s.strip
    raise ConfigurationError, no_model if answer.empty?

    answer
  end

  # @rbs return: String
  def onboarding_question
    'Which model should riffer use? Enter provider/name, ' \
      "with a provider from: #{Riffer::Rig::Providers.list}"
  end

  # @rbs return: String
  def no_model
    'No model is set: pass --model provider/name, set RIFFER_MODEL, or set "model" in ' \
      "~/.riffer/settings.json, with a provider from: #{Riffer::Rig::Providers.list}"
  end

  # @rbs provider: String
  # @rbs return: void
  def ensure_sdk(provider)
    sdk = Riffer::Rig::ProviderSetup.for(provider).sdk
    return unless sdk

    gem, requirement = sdk
    message = Riffer::Rig::SDK.ensure(gem, requirement, host: @host)
    raise ConfigurationError, message if message
  end

  # @rbs provider: String
  # @rbs return: (Hash[Symbol, String] | String)
  def install_credentials(provider)
    Riffer::Rig::Loader::Credentials.install(
      provider,
      host: @host,
      env: @env,
      config: @riffer_config,
      auth_path: home_auth_path,
      settings_path: home_settings_path
    )
  end

  # @rbs return: String
  def home_settings_path
    File.join(@home, '.riffer', 'settings.json')
  end

  # @rbs return: String
  def home_auth_path
    File.join(@home, '.riffer', 'auth.json')
  end

  # @rbs snapshot: Riffer::Rig::Runtime::Snapshot?
  # @rbs options: Riffer::Rig::Loader::Options
  # @rbs return: Riffer::Rig::Runtime::Snapshot?
  def snapshot_without_forced(snapshot, options)
    # The flags beat the session's recorded switches, which the Runtime would
    # otherwise restore over them.
    snapshot = snapshot&.without_model if options.model
    snapshot = snapshot&.without_reasoning if options.reasoning
    snapshot
  end

  # @rbs document: Riffer::Rig::Settings::Document
  # @rbs resumed: bool
  # @rbs return: Riffer::Rig::Stores::Recorder?
  def recorder_for(document, resumed:)
    store = @store
    return nil unless document.save
    return nil unless store

    Riffer::Rig::Stores::Recorder.new(store: store, resumed: resumed)
  end
end
