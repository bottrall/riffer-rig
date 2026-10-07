# frozen_string_literal: true

class Riffer::Rig::Loader
  class ConfigurationError < StandardError; end

  # Raised by a strict load: the reload abandons instead of continuing.
  class AbandonedError < StandardError; end

  EXTENSION_FEATURE = 'riffer/rig/extension' #: String

  private_constant :EXTENSION_FEATURE

  # @rbs @cwd: String
  # @rbs @host: Riffer::Rig::Hosts::_Host
  # @rbs @env: Riffer::Rig::Env
  # @rbs @home: String
  # @rbs @riffer_config: Riffer::Config
  # @rbs @store: Riffer::Rig::Stores::_Store | nil
  # @rbs @tracked_files: Array[String]
  # @rbs @stripped: Array[Symbol]
  # @rbs @extensions_enabled: bool
  # @rbs @gem_extensions: Array[Riffer::Rig::Extension]
  # @rbs @extra_extensions: Array[Riffer::Rig::Extension]
  # @rbs @file_state: Hash[String, Time?]?
  # @rbs @reload_mode: (:auto | :manual | nil)

  # @dynamic tracked_files
  attr_reader :tracked_files #: Array[String]

  # @rbs cwd: String
  # @rbs host: Riffer::Rig::Hosts::_Host
  # @rbs env: Riffer::Rig::Env | Riffer::Rig::Env::Invalid
  # @rbs home: String
  # @rbs riffer_config: Riffer::Config
  # @rbs model: String?
  # @rbs extensions: bool
  # @rbs skills: bool
  # @rbs agents_md: bool
  # @rbs tools: Array[String]?
  # @rbs max_steps: Integer?
  # @rbs store: Riffer::Rig::Stores::_Store | nil
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
    model: nil,
    extensions: true,
    skills: true,
    agents_md: true,
    tools: nil,
    max_steps: Riffer::Rig::Runtime::DEFAULT_MAX_STEPS,
    store: Riffer::Rig::Stores::JSONL.new,
    reload: nil,
    extra_extensions: [],
    snapshot: nil
  )
    new(cwd:, host:, env:, home:, riffer_config:, store:).runtime(
      model:,
      extensions:,
      skills:,
      agents_md:,
      tools:,
      max_steps:,
      reload:,
      extra_extensions:,
      snapshot:
    )
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
    store: Riffer::Rig::Stores::JSONL.new,
    env: Riffer::Rig::Env.load,
    home: Dir.home,
    riffer_config: Riffer.config
  )
    raise ConfigurationError, env.message if env.is_a?(Riffer::Rig::Env::Invalid)

    @cwd = cwd
    @host = host
    @env = env
    @home = home
    @riffer_config = riffer_config
    @store = store
    @tracked_files = []
    @stripped = []
    @extensions_enabled = true
    @gem_extensions = []
    @file_state = nil
    @reload_mode = nil
  end

  # @rbs model: String?
  # @rbs extensions: bool
  # @rbs skills: bool
  # @rbs agents_md: bool
  # @rbs tools: Array[String]?
  # @rbs max_steps: Integer?
  # @rbs reload: (:auto | :manual | nil)
  # @rbs extra_extensions: Array[Riffer::Rig::Extension]
  # @rbs snapshot: Hash[Symbol, untyped]?
  # @rbs return: Riffer::Rig::Runtime
  def runtime(
    model: nil,
    extensions: true,
    skills: true,
    agents_md: true,
    tools: nil,
    max_steps: Riffer::Rig::Runtime::DEFAULT_MAX_STEPS,
    reload: nil,
    extra_extensions: [],
    snapshot: nil
  )
    settings = merged_settings
    document = Riffer::Rig::Settings::Document.new(settings)
    selected = select_model(model || @env.model || document.model)
    provider = Riffer::Rig::Settings.provider_for(selected).to_s
    ensure_sdk(provider)
    credentials = { provider.to_sym => credentials_for(provider) }
    @extensions_enabled = extensions
    @extra_extensions = extra_extensions
    @reload_mode = reload
    @stripped = { skills: skills, agents_md: agents_md }.reject { |_name, kept| kept }.keys
    loaded = Riffer::Rig::Bundled::BY_NAME.except(*document.disabled.map(&:to_sym), *@stripped).values
    @tracked_files = []
    @gem_extensions = []
    loaded += load_rig_files(document.autoload) if extensions
    loaded += @extra_extensions

    recorder = recorder_for(document, resumed: !snapshot.nil?)
    loaded << Riffer::Rig::Stores::Recorder.extension(recorder) if recorder

    built = Riffer::Rig::Runtime.new(
      selected,
      extensions: loaded,
      tools: tools,
      settings: settings,
      host: @host,
      cwd: @cwd,
      max_steps: max_steps,
      credentials: credentials,
      env: @env,
      auth_path: home_auth_path,
      pricing: document.models,
      riffer_config: @riffer_config,
      model_options: Riffer::Rig::Settings.model_options(selected, document.reasoning),
      native_tools: document.native_tools,
      snapshot: snapshot
    )
    built.install_command(Riffer::Rig::Commands::Reload.command(self))
    built.install_reload_check(->(runtime) { automatic_reload(runtime) }) unless reload_mode(document) == :manual
    @file_state = file_state
    recorder&.attach(built)
    built
  end

  # @rbs model: String?
  # @rbs extensions: bool
  # @rbs skills: bool
  # @rbs agents_md: bool
  # @rbs tools: Array[String]?
  # @rbs max_steps: Integer?
  # @rbs return: Riffer::Rig::Runtime?
  def continue(
    model: nil,
    extensions: true,
    skills: true,
    agents_md: true,
    tools: nil,
    max_steps: Riffer::Rig::Runtime::DEFAULT_MAX_STEPS
  )
    store = @store
    return nil unless store

    latest = store.list(cwd: @cwd).max_by { |header| header.updated || Time.at(0) }
    return nil unless latest

    resume(latest.id, model:, extensions:, skills:, agents_md:, tools:, max_steps:)
  end

  # A resume carries the history over and nothing else: the settings,
  # credentials, extensions and tools are today's.
  # @rbs id: String
  # @rbs model: String?
  # @rbs extensions: bool
  # @rbs skills: bool
  # @rbs agents_md: bool
  # @rbs tools: Array[String]?
  # @rbs max_steps: Integer?
  # @rbs return: Riffer::Rig::Runtime?
  def resume(
    id,
    model: nil,
    extensions: true,
    skills: true,
    agents_md: true,
    tools: nil,
    max_steps: Riffer::Rig::Runtime::DEFAULT_MAX_STEPS
  )
    store = @store
    return nil unless store

    entries = store.read(id)
    return nil if entries.empty?

    runtime(model:, extensions:, skills:, agents_md:, tools:, max_steps:, snapshot: snapshot_of(entries, id))
  end

  # A host tier may not name the store, so the messages it replays come from
  # here, in the order they were recorded.
  # @rbs id: String
  # @rbs return: Array[Hash[Symbol, untyped]]
  def messages(id)
    store = @store
    return [] unless store

    store.read(id).filter_map { |entry| entry.message if entry.is_a?(Riffer::Rig::Stores::MessageEntry) }
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
  # Settings.rejection reports a rejection; the Runtime is the success value.
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
    reload_mode(Riffer::Rig::Settings::Document.new(merged_settings)) == :manual
  end

  # The automatic trigger: runs at every before_request boundary, so the
  # change check decides and a no-op costs the stat alone.
  # @rbs runtime: Riffer::Rig::Runtime
  # @rbs return: void
  def automatic_reload(runtime)
    _ = reload(runtime)
  end

  # @rbs return: Hash[Symbol, untyped]
  def merged_settings
    Riffer::Rig::Settings.merge(
      Riffer::Rig::Settings.read(home_settings_path),
      Riffer::Rig::Settings.read(File.join(@cwd, '.riffer', 'settings.json'))
    )
  end

  # Notifies every failure once and reports its message, unexpected raises
  # included — the automatic check runs mid-turn with no other isolation, and a
  # raised attempt must still advance the snapshot in reload. A rebuilt Runtime
  # is the success value.
  # @rbs runtime: Riffer::Rig::Runtime
  # @rbs return: (Riffer::Rig::Runtime | String)
  def perform_reload(runtime)
    settings = merged_settings
    document = Riffer::Rig::Settings::Document.new(settings)
    extensions = reload_extensions(document, settings)

    failure = reload_credentials(runtime)
    return notify_failure(failure) if failure

    runtime.rebuild(extensions: validated(extensions, settings), settings: settings)
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
  # @rbs settings: Hash[Symbol, untyped]
  # @rbs return: Array[Riffer::Rig::Extension]
  def reload_extensions(document, settings)
    candidates = Riffer::Rig::Bundled::BY_NAME.except(
      *document.disabled.map(&:to_sym),
      *@stripped
    ).values + @extra_extensions
    return validated(candidates, settings) unless @extensions_enabled

    scrub_tracked_features
    @tracked_files = []
    candidates.concat(@gem_extensions, rig_recordings)
    validated(candidates, settings)
  end

  # @rbs return: Array[Riffer::Rig::Extension]
  def rig_recordings
    recorded = [] #: Array[Riffer::Rig::Extension]
    recorded.concat(load_rig_file(home_rig_path, confirm_trust: false))
    recorded.concat(load_rig_file(project_rig_path, confirm_trust: true))
    recorded
  end

  # @rbs path: String
  # @rbs confirm_trust: bool
  # @rbs return: Array[Riffer::Rig::Extension]
  def load_rig_file(path, confirm_trust:)
    return [] unless File.file?(path)
    return [] if confirm_trust && !trusted?(path)

    load_file(path, track: true, strict: true)
  end

  # @rbs return: void
  def scrub_tracked_features
    @tracked_files.each { |path| $LOADED_FEATURES.delete(path) }
  end

  # Runs each extension against a throwaway registrar so that a failing block
  # is skipped and reported instead of aborting the rebuild.
  # @rbs extensions: Array[Riffer::Rig::Extension]
  # @rbs settings: Hash[Symbol, untyped]
  # @rbs return: Array[Riffer::Rig::Extension]
  def validated(extensions, settings)
    extensions.select do |extension|
      registrar = Riffer::Rig::Registrar.new(extension.name, settings[extension.name.to_sym] || {})
      error = extension.load_into(registrar)
      next true unless error

      @host.notify("Extension #{extension.name} failed to load: #{error.message}", level: :error)
      false
    end
  end

  # @rbs runtime: Riffer::Rig::Runtime
  # @rbs return: String?
  def reload_credentials(runtime)
    provider = runtime.model.partition('/').first
    resolution = Riffer::Rig::Credentials.resolve(
      provider,
      host: asking_host,
      env: @env,
      auth_path: home_auth_path,
      settings_path: home_settings_path
    )
    return missing_credentials(provider, resolution.missing) unless resolution.missing.empty?

    Riffer::Rig::Credentials.apply(provider, resolution.values, config: @riffer_config)
    runtime.merge_credentials(provider.to_sym, resolution.values)
    nil
  end

  # @rbs return: Hash[String, Time?]
  def file_state
    (@tracked_files + rig_paths).uniq.to_h { |path| [path, stamp(path)] }
  end

  # @rbs return: Array[String]
  def rig_paths
    return [] unless @extensions_enabled

    [home_rig_path, project_rig_path]
  end

  # @rbs path: String
  # @rbs return: Time?
  def stamp(path)
    File.file?(path) ? File.mtime(path) : nil
  end

  # @rbs return: String
  def home_rig_path
    File.expand_path(File.join(@home, '.riffer', 'rig.rb'))
  end

  # @rbs return: String
  def project_rig_path
    File.expand_path(File.join(@cwd, '.riffer', 'rig.rb'))
  end

  # @rbs autoload: bool
  # @rbs return: Array[Riffer::Rig::Extension]
  def load_rig_files(autoload)
    @gem_extensions = gem_extension_files(autoload).flat_map { |file| load_file(File.expand_path(file), track: false) }
    recorded = @gem_extensions.dup
    recorded.concat(load_file(home_rig_path, track: true)) if File.file?(home_rig_path)
    if File.file?(project_rig_path) && trusted?(project_rig_path)
      recorded.concat(load_file(project_rig_path, track: true))
    end
    recorded
  end

  # @rbs autoload: bool
  # @rbs return: Array[String]
  def gem_extension_files(autoload)
    return [] unless autoload

    Gem.find_files(EXTENSION_FEATURE)
  end

  # @rbs path: String
  # @rbs return: bool
  def trusted?(path)
    stored = Riffer::Rig::Trust.read(trust_path)[path]
    return stored unless stored.nil?

    asked = @host.capabilities.include?(:confirm)
    decision = asked ? @host.confirm("Trust #{path}?") : false
    Riffer::Rig::Trust.store(trust_path, path, decision) if asked
    decision
  end

  # @rbs return: String
  def trust_path
    File.join(@home, '.riffer', 'trust.json')
  end

  # Loads one file and returns the extensions it recorded. A tracked load adds
  # the features the load added to the tracked file set. A failure is reported
  # to the host and yields nothing, unless strict: then it propagates as
  # AbandonedError for the reload to abandon on.
  # @rbs path: String
  # @rbs track: bool
  # @rbs strict: bool
  # @rbs return: Array[Riffer::Rig::Extension]
  def load_file(path, track:, strict: false)
    before = Riffer::Rig.extensions
    before_features = $LOADED_FEATURES.dup
    begin
      load path
    rescue StandardError => e
      track_loaded(before_features, path) if track
      message = "#{path} failed to load: #{e.message}"
      raise AbandonedError, message if strict

      @host.notify(message, level: :error)
      return []
    end
    track_loaded(before_features, path) if track
    Riffer::Rig.extensions.values.reject { |extension| before[extension.name] == extension }
  end

  # @rbs before_features: Array[String]
  # @rbs path: String
  # @rbs return: void
  def track_loaded(before_features, path)
    recorded = ($LOADED_FEATURES - before_features) + [path] #: Array[String]
    @tracked_files.concat(recorded.select { |feature| local?(feature) })
  end

  # @rbs feature: String
  # @rbs return: bool
  def local?(feature)
    roots = [File.expand_path(File.join(@home, '.riffer')), File.expand_path(@cwd)] #: Array[String]
    roots.any? { |root| feature.start_with?("#{root}#{File::SEPARATOR}") }
  end

  # @rbs configured: String?
  # @rbs return: String
  def select_model(configured)
    model = configured || ask_for_model
    rejection = Riffer::Rig::Settings.rejection(model)
    raise ConfigurationError, rejection if rejection

    Riffer::Rig::Settings.store_model(model, path: home_settings_path) unless configured
    model
  end

  # @rbs return: String
  def ask_for_model
    answer = asking_host.ask(onboarding_question).to_s.strip
    raise ConfigurationError, no_model if answer.empty?

    answer
  end

  # @rbs return: String
  def onboarding_question
    'Which model should riffer use? Enter provider/name, ' \
      "with a provider from: #{provider_list}"
  end

  # @rbs return: String
  def no_model
    'No model is set: pass --model provider/name, set RIFFER_MODEL, or set "model" in ' \
      "~/.riffer/settings.json, with a provider from: #{provider_list}"
  end

  # @rbs return: String
  def provider_list
    Riffer::Rig::Settings.providers.join(', ')
  end

  # @rbs provider: String
  # @rbs return: void
  def ensure_sdk(provider)
    sdk = Riffer::Rig::ProviderSetup.for(provider).sdk
    return unless sdk

    gem, requirement = sdk
    message = Riffer::Rig::SDK.ensure(gem, requirement, host: asking_host)
    raise ConfigurationError, message if message
  end

  # @rbs provider: String
  # @rbs return: Hash[Symbol, String]
  def credentials_for(provider)
    resolution = Riffer::Rig::Credentials.resolve(
      provider,
      host: asking_host,
      env: @env,
      auth_path: home_auth_path,
      settings_path: home_settings_path
    )
    raise ConfigurationError, missing_credentials(provider, resolution.missing) unless resolution.missing.empty?

    Riffer::Rig::Credentials.apply(provider, resolution.values, config: @riffer_config)
    resolution.values
  end

  # @rbs provider: String
  # @rbs missing: Array[Symbol]
  # @rbs return: String
  def missing_credentials(provider, missing)
    setup = Riffer::Rig::ProviderSetup.for(provider)
    "#{provider} has no #{setup.missing_fields(missing)}; " \
      'set it in the environment or run riffer interactively to paste it' \
      "#{" (create one at #{setup.url})" if setup.url}"
  end

  # @rbs return: Riffer::Rig::Hosts::_Host
  def asking_host
    @host.capabilities.include?(:ask) ? @host : Riffer::Rig::Hosts::Null.new
  end

  # @rbs return: String
  def home_settings_path
    File.join(@home, '.riffer', 'settings.json')
  end

  # @rbs return: String
  def home_auth_path
    File.join(@home, '.riffer', 'auth.json')
  end

  # @rbs entries: Array[Riffer::Rig::Stores::entry]
  # @rbs id: String
  # @rbs return: Hash[Symbol, untyped]
  def snapshot_of(entries, id)
    {
      id: id,
      messages: entries.filter_map { |entry| entry.message if entry.is_a?(Riffer::Rig::Stores::MessageEntry) },
      model: entries.filter_map { |entry| entry.model if entry.is_a?(Riffer::Rig::Stores::ModelEntry) }.last,
      skills: entries.filter_map { |entry| entry.skill if entry.is_a?(Riffer::Rig::Stores::SkillEntry) }
    }
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
