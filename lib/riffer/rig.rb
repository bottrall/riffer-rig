# frozen_string_literal: true

require 'zeitwerk'
require 'riffer'
require_relative 'rig/version'

loader = Zeitwerk::Loader.for_gem_extension(Riffer)
loader.ignore("#{__dir__}/rig/version.rb")
loader.inflector.inflect('cli' => 'CLI', 'repl' => 'REPL', 'ui' => 'UI')
loader.setup

module Riffer::Rig
  # @rbs self.@extensions: Hash[String, Riffer::Rig::Extension]
  @extensions = {} #: Hash[String, Riffer::Rig::Extension]

  # Records a named extension block in the process registry. Re-recording a
  # name replaces the block, so reloading a file never duplicates it.
  #
  # @rbs name: String
  # @rbs requires: String?
  # @rbs &block: (::Riffer::Rig::Registrar) -> void
  # @rbs return: Riffer::Rig::Extension
  def self.extension(name, requires: nil, &)
    ext = Extension.new(name, requires: requires, &)
    if ext.requires && !ext.requires.satisfied_by?(Gem::Version.new(Riffer::Rig::VERSION))
      raise Riffer::ArgumentError,
            "extension #{name} requires riffer-rig #{ext.requires}, found #{Riffer::Rig::VERSION}"
    end

    @extensions[name] = ext
  end

  # Returns a copy of the process registry, keyed by extension name.
  #
  # @rbs return: Hash[String, Riffer::Rig::Extension]
  def self.extensions
    @extensions.dup
  end
end
