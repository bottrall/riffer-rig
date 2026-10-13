# frozen_string_literal: true

class Riffer::Rig::Loader::ExtensionSource
  EXTENSION_FEATURE = 'riffer/rig/extension'

  private_constant :EXTENSION_FEATURE

  # @rbs @cwd: String
  # @rbs @home: String
  # @rbs @host: Riffer::Rig::Hosts::_Host
  # @rbs @tracked_files: Array[String]
  # @rbs @gem_extensions: Array[Riffer::Rig::Extension]

  # @dynamic tracked_files
  attr_reader :tracked_files #: Array[String]

  # @rbs cwd: String
  # @rbs home: String
  # @rbs host: Riffer::Rig::Hosts::_Host
  # @rbs return: void
  def initialize(cwd:, home:, host:)
    @cwd = cwd
    @home = home
    @host = host
    @tracked_files = []
    @gem_extensions = []
  end

  # @rbs autoload: bool
  # @rbs return: Array[Riffer::Rig::Extension]
  def discover(autoload:)
    @tracked_files = []
    @gem_extensions = gem_extension_files(autoload).flat_map do |file|
      reported(load_file(File.expand_path(file), track: false))
    end
    @gem_extensions +
      reported(rig_file(home_rig_path, confirm_trust: false)) +
      reported(rig_file(project_rig_path, confirm_trust: true))
  end

  # @rbs return: (Array[Riffer::Rig::Extension] | String)
  def rediscover
    @tracked_files.each { |path| $LOADED_FEATURES.delete(path) }
    @tracked_files = []
    home = rig_file(home_rig_path, confirm_trust: false)
    return home if home.is_a?(String)

    project = rig_file(project_rig_path, confirm_trust: true)
    return project if project.is_a?(String)

    @gem_extensions + home + project
  end

  # @rbs extensions: Array[Riffer::Rig::Extension]
  # @rbs settings: Hash[Symbol, untyped]
  # @rbs return: Array[Riffer::Rig::Extension]
  def validated(extensions, settings)
    # Runtime#rebuild raises on a failing extension block.
    extensions.select do |extension|
      outcome = extension.trial(settings)
      next true unless outcome.is_a?(StandardError)

      @host.notify("Extension #{extension.name} failed to load: #{outcome.message}", level: :error)
      false
    end
  end

  # @rbs return: Hash[String, Time?]
  def file_state
    (@tracked_files + [home_rig_path, project_rig_path]).uniq.to_h { |path| [path, stamp(path)] }
  end

  private

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
  # @rbs return: Array[String]
  def gem_extension_files(autoload)
    return [] unless autoload

    Gem.find_files(EXTENSION_FEATURE)
  end

  # @rbs outcome: Array[Riffer::Rig::Extension] | String
  # @rbs return: Array[Riffer::Rig::Extension]
  def reported(outcome)
    return outcome unless outcome.is_a?(String)

    @host.notify(outcome, level: :error)
    []
  end

  # @rbs path: String
  # @rbs confirm_trust: bool
  # @rbs return: (Array[Riffer::Rig::Extension] | String)
  def rig_file(path, confirm_trust:)
    return [] unless File.file?(path)

    trusted = confirm_trust ? trust(path) : true
    return trusted if trusted.is_a?(String)
    return [] unless trusted

    load_file(path, track: true)
  end

  # @rbs path: String
  # @rbs return: (bool | String)
  def trust(path)
    decisions = Riffer::Rig::Trust.read(trust_path)
    return decisions if decisions.is_a?(String)

    stored = decisions[path]
    return stored unless stored.nil?
    return false unless @host.capabilities.include?(:confirm)

    decision = @host.confirm("Trust #{path}?")
    Riffer::Rig::Trust.store(trust_path, path, decision) || decision
  end

  # @rbs return: String
  def trust_path
    File.join(@home, '.riffer', 'trust.json')
  end

  # @rbs path: String
  # @rbs track: bool
  # @rbs return: (Array[Riffer::Rig::Extension] | String)
  def load_file(path, track:)
    before = Riffer::Rig.extensions
    before_features = $LOADED_FEATURES.dup
    error = attempt(path)
    track_loaded(before_features, path) if track
    return "#{path} failed to load: #{error.message}" if error

    Riffer::Rig.extensions.values.reject { |extension| before[extension.name] == extension }
  end

  # @rbs path: String
  # @rbs return: StandardError?
  def attempt(path)
    load path
    nil
  rescue StandardError => e
    e
  end

  # @rbs before_features: Array[String]
  # @rbs path: String
  # @rbs return: void
  def track_loaded(before_features, path)
    recorded = ($LOADED_FEATURES - before_features) + [path] #: Array[String]
    @tracked_files += recorded.select { |feature| local?(feature) }
  end

  # @rbs feature: String
  # @rbs return: bool
  def local?(feature)
    roots = [File.expand_path(File.join(@home, '.riffer')), File.expand_path(@cwd)] #: Array[String]
    roots.any? { |root| feature.start_with?("#{root}#{File::SEPARATOR}") }
  end
end
