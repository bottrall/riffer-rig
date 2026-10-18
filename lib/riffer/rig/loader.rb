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
  # @rbs @stripped: Array[Symbol]
  # @rbs @extensions_enabled: bool
  # @rbs @extra_extensions: Array[Riffer::Rig::Extension]
  # @rbs @recorder_extensions: Array[Riffer::Rig::Extension]
  # @rbs @file_state: Hash[String, Time?]?
  # @rbs @reload_mode: (:auto | :manual | nil)

  # @rbs cwd: String
  # @rbs host: Riffer::Rig::Hosts::_Host
  # @rbs env: Riffer::Rig::Env | Riffer::Rig::Env::Invalid
  # @rbs home: String
  # @rbs riffer_config: Riffer::Config
  # @rbs store: Riffer::Rig::Stores::_Store | nil
  # @rbs options: Riffer::Rig::Loader::Options
  # @rbs reload: (:auto | :manual | nil)
  # @rbs extra_extensions: Array[Riffer::Rig::Extension]
  # @rbs snapshot: Hash[Symbol, untyped]?
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
    @stripped = []
    @extensions_enabled = true
    @recorder_extensions = []
    @file_state = nil
    @reload_mode = nil
  end

  # @rbs options: Riffer::Rig::Loader::Options
  # @rbs reload: (:auto | :manual | nil)
  # @rbs extra_extensions: Array[Riffer::Rig::Extension]
  # @rbs snapshot: Hash[Symbol, untyped]?
  # @rbs return: Riffer::Rig::Runtime
  def runtime(options = Options.new, reload: nil, extra_extensions: [], snapshot: nil)
    settings = merged_settings
    raise ConfigurationError, settings if settings.is_a?(String)

    document = Riffer::Rig::Settings::Document.new(settings)
    selected = select_model(options.model || @env.model || document.model)
    check_reasoning(options, selected)
    provider = Riffer::Rig::Settings::ModelOptions.provider_for(selected).to_s
    ensure_sdk(provider)
    credentials = install_credentials(provider)
    raise ConfigurationError, credentials if credentials.is_a?(String)

    @riffer_config.catalog_files = document.catalog_files
    @extensions_enabled = options.extensions
    @extra_extensions = extra_extensions
    @reload_mode = reload
    @stripped = { skills: options.skills, agents_md: options.agents_md }.reject { |_name, kept| kept }.keys
    loaded = bundled(document)
    loaded += @source.discover(autoload: document.autoload) if options.extensions
    loaded += @extra_extensions

    recorder = recorder_for(document, resumed: !snapshot.nil?)
    @recorder_extensions = recorder ? [Riffer::Rig::Stores::Recorder.extension(recorder)] : []
    loaded += @recorder_extensions

    snapshot = snapshot_without_forced(snapshot, options)
    reasoning = forced_reasoning(options, snapshot)

    built = Riffer::Rig::Runtime.new(
      selected,
      extensions: loaded,
      tools: options.tools,
      settings: settings,
      host: @host,
      cwd: @cwd,
      max_steps: options.max_steps,
      credentials: { provider.to_sym => credentials },
      env: @env,
      auth_path: home_auth_path,
      reasoning: reasoning || document.reasoning,
      riffer_config: @riffer_config,
      model_options: Riffer::Rig::Settings::ModelOptions.model_options(selected),
      native_tools: document.native_tools,
      snapshot: snapshot
    )
    built.install_command(Riffer::Rig::Commands::Reload.command(self))
    store = @store
    built.install_command(Riffer::Rig::Commands::Trace.command(store)) if store && recorder
    built.install_reload_check(->(runtime) { automatic_reload(runtime) }) unless reload_mode(document) == :manual
    @file_state = file_state
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

  # A resume carries the history over and nothing else: the settings,
  # credentials, extensions and tools are today's.
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

  # Without force, a no-op while the tracked file set and the two rig.rb paths
  # look as the last discovery left them and the reload mode is not manual —
  # the entry point the automatic trigger (#133) calls. The snapshot advances
  # on every attempt, failed ones included, so a failure does not retry every
  # request. Failures are notified once and reported as the message, the way
  # Settings::ModelOptions.rejection reports a rejection; the Runtime is the success value.
  # @rbs runtime: Riffer::Rig::Runtime
  # @rbs force: bool
  # @rbs return: (Riffer::Rig::Runtime | String)
  def reload(runtime, force: false)
    return runtime if !force && file_state == @file_state
    return runtime if !force && manual_reload?

    outcome = perform_reload(runtime)
    @file_state = file_state
    outcome
  end

  private

  # The reload mode a build runs under: the keyword wins over the setting,
  # the setting over the default.
  # @rbs document: Riffer::Rig::Settings::Document
  # @rbs return: (:auto | :manual)
  def reload_mode(document)
    @reload_mode || document.reload
  end

  # @rbs return: bool
  def manual_reload?
    return true if @reload_mode == :manual

    settings = merged_settings
    settings.is_a?(Hash) && reload_mode(Riffer::Rig::Settings::Document.new(settings)) == :manual
  end

  # The automatic trigger: runs at every before_request boundary, so the
  # change check decides and a no-op costs the stat alone.
  # @rbs runtime: Riffer::Rig::Runtime
  # @rbs return: void
  def automatic_reload(runtime)
    _ = reload(runtime)
  end

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

  # Notifies every failure once and reports its message, unexpected raises
  # included — the automatic check runs mid-turn with no other isolation, and a
  # raised attempt must still advance the snapshot in reload. A rebuilt Runtime
  # is the success value.
  # @rbs runtime: Riffer::Rig::Runtime
  # @rbs return: (Riffer::Rig::Runtime | String)
  def perform_reload(runtime)
    settings = merged_settings
    return notify_failure(settings) if settings.is_a?(String)

    candidates = reload_candidates(Riffer::Rig::Settings::Document.new(settings))
    return notify_failure(candidates) if candidates.is_a?(String)

    extensions = @source.validated(candidates + @recorder_extensions, settings)
    provider = runtime.model.partition('/').first
    credentials = install_credentials(provider)
    return notify_failure(credentials) if credentials.is_a?(String)

    runtime.merge_credentials(provider.to_sym, credentials)
    runtime.rebuild(extensions: extensions, settings: settings)
    runtime
  rescue StandardError => e
    notify_failure(e.message)
  end

  # @rbs message: String
  # @rbs return: String
  def notify_failure(message)
    @host.notify(message, level: :error)
    message
  end

  # @rbs document: Riffer::Rig::Settings::Document
  # @rbs return: (Array[Riffer::Rig::Extension] | String)
  def reload_candidates(document)
    candidates = bundled(document) + @extra_extensions
    return candidates unless @extensions_enabled

    rediscovered = @source.rediscover
    rediscovered.is_a?(String) ? rediscovered : candidates + rediscovered
  end

  # @rbs document: Riffer::Rig::Settings::Document
  # @rbs return: Array[Riffer::Rig::Extension]
  def bundled(document)
    Riffer::Rig::Bundled::BY_NAME.except(*document.disabled.map(&:to_sym), *@stripped).values
  end

  # @rbs return: Hash[String, Time?]
  def file_state
    @extensions_enabled ? @source.file_state : {}
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

  # A reasoning level from the flag or the environment is refused, the way a
  # bad model string is; one from the settings document or a session's recorded
  # switch falls back to the model's default instead.
  # @rbs options: Riffer::Rig::Loader::Options
  # @rbs selected: String
  # @rbs return: void
  def check_reasoning(options, selected)
    forced = options.reasoning || @env.reasoning
    return unless forced

    rejection = Riffer::Rig::Settings::ModelOptions.reasoning_rejection(forced, selected)
    return unless rejection

    raise ConfigurationError, options.reasoning ? rejection : "RIFFER_REASONING: #{rejection}"
  end

  # The reasoning in effect for the build, over the settings document: the flag,
  # then the session's recorded switch, then RIFFER_REASONING.
  # @rbs options: Riffer::Rig::Loader::Options
  # @rbs snapshot: Hash[Symbol, untyped]?
  # @rbs return: String?
  def forced_reasoning(options, snapshot)
    options.reasoning || recorded_reasoning(snapshot) || @env.reasoning
  end

  # @rbs snapshot: Hash[Symbol, untyped]?
  # @rbs return: String?
  def recorded_reasoning(snapshot)
    saved = snapshot && snapshot[:reasoning]
    saved.is_a?(String) ? saved : nil
  end

  # A model or reasoning level chosen for the run wins for that run only: it is
  # not recorded, so a later resume restores the session's own switches.
  # @rbs snapshot: Hash[Symbol, untyped]?
  # @rbs options: Riffer::Rig::Loader::Options
  # @rbs return: Hash[Symbol, untyped]?
  def snapshot_without_forced(snapshot, options)
    snapshot = snapshot&.merge(model: nil) if options.model
    snapshot = snapshot&.merge(reasoning: nil) if options.reasoning
    snapshot
  end

  # The store records unless it was declined with store: nil or globally with
  # "sessions": {"save": false}.
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
