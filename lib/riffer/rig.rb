# frozen_string_literal: true

require 'zeitwerk'
require 'riffer'
require_relative 'rig/version'

loader = Zeitwerk::Loader.for_gem_extension(Riffer)
loader.ignore("#{__dir__}/rig/version.rb")
loader.inflector.inflect('cli' => 'CLI', 'sdk' => 'SDK')
loader.setup

module Riffer::Rig
  # @rbs self.@extensions: Hash[String, Riffer::Rig::Extension]
  @extensions = {} #: Hash[String, Riffer::Rig::Extension]

  # @rbs name: String
  # @rbs requires: String?
  # @rbs &block: (::Riffer::Rig::Registrar) -> void
  # @rbs return: Riffer::Rig::Extension
  def self.extension(name, requires: nil, &)
    # Keyed by name so reloading a file replaces its block rather than
    # duplicating it.
    @extensions[name] = Extension.new(name, requires: requires, &)
  end

  # @rbs return: Hash[String, Riffer::Rig::Extension]
  def self.extensions
    @extensions.dup
  end

  # @rbs identifier: String | Symbol
  # @rbs return: Hash[Symbol, String]?
  def self.credentials(identifier)
    Credentials.read(identifier)
  end

  # @rbs name: Symbol?
  # @rbs return: Riffer::Rig::Extension | Array[Riffer::Rig::Extension]
  def self.bundled(name = nil)
    name ? Bundled::BY_NAME.fetch(name) : Bundled::BY_NAME.values
  end
end
