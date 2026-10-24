# frozen_string_literal: true

class Riffer::Rig::Loader::Reloader
  # @rbs @source: Riffer::Rig::Loader::ExtensionSource
  # @rbs @host: Riffer::Rig::Hosts::_Host
  # @rbs @settings: ^() -> (Hash[Symbol, untyped] | String)
  # @rbs @credentials: ^(String) -> (Hash[Symbol, String] | String)
  # @rbs @extensions: ^(Riffer::Rig::Settings::Document, Array[Riffer::Rig::Extension]) -> Array[Riffer::Rig::Extension]
  # @rbs @rediscovers: bool
  # @rbs @mode: (:auto | :manual | nil)
  # @rbs @file_state: Hash[String, Time?]

  # @rbs source: Riffer::Rig::Loader::ExtensionSource
  # @rbs host: Riffer::Rig::Hosts::_Host
  # @rbs settings: ^() -> (Hash[Symbol, untyped] | String)
  # @rbs credentials: ^(String) -> (Hash[Symbol, String] | String)
  # @rbs extensions: ^(Riffer::Rig::Settings::Document, Array[Riffer::Rig::Extension]) -> Array[Riffer::Rig::Extension]
  # @rbs rediscovers: bool
  # @rbs mode: (:auto | :manual | nil)
  # @rbs return: void
  def initialize(source:, host:, settings:, credentials:, extensions:, rediscovers:, mode:)
    @source = source
    @host = host
    @settings = settings
    @credentials = credentials
    @extensions = extensions
    @rediscovers = rediscovers
    @mode = mode
    @file_state = file_state
  end

  # @rbs runtime: Riffer::Rig::Runtime
  # @rbs force: bool
  # @rbs return: (Riffer::Rig::Runtime | String)
  def reload(runtime, force: false)
    return runtime if !force && file_state == @file_state
    return runtime if !force && manual?

    outcome = perform(runtime)
    # Every attempt advances the state, failed ones included, so a failure is
    # not retried at every request.
    @file_state = file_state
    outcome
  end

  private

  # @rbs return: bool
  def manual?
    return @mode == :manual if @mode

    settings = @settings.call
    settings.is_a?(Hash) && Riffer::Rig::Settings::Document.new(settings).reload == :manual
  end

  # @rbs runtime: Riffer::Rig::Runtime
  # @rbs return: (Riffer::Rig::Runtime | String)
  def perform(runtime)
    settings = @settings.call
    return notify_failure(settings) if settings.is_a?(String)

    rediscovered = @rediscovers ? @source.rediscover : [] #: Array[Riffer::Rig::Extension] | String
    return notify_failure(rediscovered) if rediscovered.is_a?(String)

    candidates = @extensions.call(Riffer::Rig::Settings::Document.new(settings), rediscovered)
    extensions = @source.validated(candidates, settings)
    provider = runtime.model.partition('/').first
    credentials = @credentials.call(provider)
    return notify_failure(credentials) if credentials.is_a?(String)

    runtime.merge_credentials(provider.to_sym, credentials)
    runtime.rebuild(extensions: extensions, settings: settings)
    runtime
  rescue StandardError => e
    # The automatic check runs mid-turn with nothing else to catch a raise,
    # and a raised attempt must still advance the file state.
    notify_failure(e.message)
  end

  # @rbs message: String
  # @rbs return: String
  def notify_failure(message)
    @host.notify(message, level: :error)
    message
  end

  # @rbs return: Hash[String, Time?]
  def file_state
    @rediscovers ? @source.file_state : {}
  end
end
