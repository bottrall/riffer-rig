# frozen_string_literal: true

class Riffer::Rig::Loader
  class ConfigurationError < StandardError; end

  EXTENSION_FEATURE = 'riffer/rig/extension' #: String

  private_constant :EXTENSION_FEATURE

  # @rbs @cwd: String
  # @rbs @host: Riffer::Rig::Hosts::_Host
  # @rbs @env: Riffer::Rig::Env
  # @rbs @home: String
  # @rbs @riffer_config: Riffer::Config
  # @rbs @tracked_files: Array[String]

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
    max_steps: Riffer::Rig::Runtime::DEFAULT_MAX_STEPS
  )
    new(cwd:, host:, env:, home:, riffer_config:).runtime(model:, extensions:, skills:, agents_md:, tools:, max_steps:)
  end

  # @rbs cwd: String
  # @rbs host: Riffer::Rig::Hosts::_Host
  # @rbs env: Riffer::Rig::Env | Riffer::Rig::Env::Invalid
  # @rbs home: String
  # @rbs riffer_config: Riffer::Config
  # @rbs return: void
  def initialize(cwd:, host:, env: Riffer::Rig::Env.load, home: Dir.home, riffer_config: Riffer.config)
    raise ConfigurationError, env.message if env.is_a?(Riffer::Rig::Env::Invalid)

    @cwd = cwd
    @host = host
    @env = env
    @home = home
    @riffer_config = riffer_config
    @tracked_files = []
  end

  # @rbs model: String?
  # @rbs extensions: bool
  # @rbs skills: bool
  # @rbs agents_md: bool
  # @rbs tools: Array[String]?
  # @rbs max_steps: Integer?
  # @rbs return: Riffer::Rig::Runtime
  def runtime(
    model: nil,
    extensions: true,
    skills: true,
    agents_md: true,
    tools: nil,
    max_steps: Riffer::Rig::Runtime::DEFAULT_MAX_STEPS
  )
    settings = Riffer::Rig::Settings.merge(
      Riffer::Rig::Settings.read(home_settings_path),
      Riffer::Rig::Settings.read(File.join(@cwd, '.riffer', 'settings.json'))
    )
    document = Riffer::Rig::Settings::Document.new(settings)
    selected = select_model(model || @env.model || document.model)
    provider = Riffer::Rig::Settings.provider_for(selected).to_s
    ensure_sdk(provider)
    credentials = { provider.to_sym => credentials_for(provider) }
    stripped = { skills: skills, agents_md: agents_md }.reject { |_name, kept| kept }.keys
    loaded = Riffer::Rig::Bundled::BY_NAME.except(*document.disabled.map(&:to_sym), *stripped).values
    loaded += load_rig_files(document.autoload) if extensions

    Riffer::Rig::Runtime.new(
      selected,
      extensions: loaded,
      tools: tools,
      settings: settings,
      host: @host,
      cwd: @cwd,
      max_steps: max_steps,
      credentials: credentials,
      pricing: document.models,
      riffer_config: @riffer_config,
      model_options: Riffer::Rig::Settings.model_options(selected, document.reasoning),
      native_tools: document.native_tools
    )
  end

  private

  # @rbs autoload: bool
  # @rbs return: Array[Riffer::Rig::Extension]
  def load_rig_files(autoload)
    recorded = gem_extension_files(autoload).flat_map { |file| load_file(File.expand_path(file), track: false) }
    home = File.expand_path(File.join(@home, '.riffer', 'rig.rb'))
    recorded.concat(load_file(home, track: true)) if File.file?(home)
    project = File.expand_path(File.join(@cwd, '.riffer', 'rig.rb'))
    recorded.concat(load_file(project, track: true)) if File.file?(project) && trusted?(project)
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

  # @rbs path: String
  # @rbs track: bool
  # @rbs return: Array[Riffer::Rig::Extension]
  def load_file(path, track:)
    before = Riffer::Rig.extensions
    before_features = $LOADED_FEATURES.dup
    begin
      load path
    rescue StandardError => e
      track_loaded(before_features, path) if track
      @host.notify("#{path} failed to load: #{e.message}", level: :error)
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
      auth_path: File.join(@home, '.riffer', 'auth.json'),
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
end
