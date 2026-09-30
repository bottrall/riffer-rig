# frozen_string_literal: true

class Riffer::Rig::Loader
  class ConfigurationError < StandardError; end

  PROVIDER_LIST = Riffer::Rig::Settings::PROVIDERS.join(', ') #: String

  ONBOARDING_QUESTION = 'Which model should riffer use? Enter provider/name, ' \
                        "with a provider from: #{PROVIDER_LIST}".freeze #: String

  NO_MODEL = 'No model is set: pass --model provider/name, set RIFFER_MODEL, or set "model" in ' \
             "~/.riffer/settings.json, with a provider from: #{PROVIDER_LIST}".freeze #: String

  private_constant :PROVIDER_LIST, :ONBOARDING_QUESTION, :NO_MODEL

  # @rbs @cwd: String
  # @rbs @host: Riffer::Rig::Hosts::_Host
  # @rbs @env: Riffer::Rig::Env
  # @rbs @home: String
  # @rbs @riffer_config: Riffer::Config

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
    credentials = { provider.to_sym => credentials_for(provider) }
    stripped = { skills: skills, agents_md: agents_md }.reject { |_name, kept| kept }.keys

    Riffer::Rig::Runtime.new(
      selected,
      extensions: Riffer::Rig::Bundled::BY_NAME.except(*document.disabled.map(&:to_sym), *stripped).values,
      tools: tools,
      settings: settings,
      host: @host,
      cwd: @cwd,
      max_steps: max_steps,
      credentials: credentials,
      pricing: document.models,
      riffer_config: @riffer_config,
      model_options: Riffer::Rig::Settings.model_options(selected, document.reasoning)
    )
  end

  private

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
    answer = asking_host.ask(ONBOARDING_QUESTION).to_s.strip
    raise ConfigurationError, NO_MODEL if answer.empty?

    answer
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
    fields = setup.fields.select { |field| missing.include?(field.name) }
    wanted = fields.map { |field| "#{field.name} (#{field.env.join(' or ')})" }.join(', ')
    "#{provider} has no #{wanted}; set it in the environment or run riffer interactively to paste it" \
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
