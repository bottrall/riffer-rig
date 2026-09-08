# frozen_string_literal: true

require 'zeitwerk'
require 'riffer'
require_relative 'rig/version'

loader = Zeitwerk::Loader.for_gem_extension(Riffer)
loader.ignore("#{__dir__}/rig/version.rb")
loader.inflector.inflect('cli' => 'CLI', 'repl' => 'REPL', 'ui' => 'UI')
loader.setup

module Riffer::Rig
  @extensions = {} # : Hash[String, Riffer::Rig::Extension]

  # Records an extension block in the process registry and returns the
  # extension object. Re-recording a name replaces the block.
  #
  #   Riffer::Rig.extension('git') do |rig|
  #     rig.tool GitLog
  #   end
  #
  # : (String, ?requires: String?, &(untyped) -> void) -> Riffer::Rig::Extension
  def self.extension(name, requires: nil, &)
    ext = Extension.new(name, requires: requires, &)
    if ext.requires && !ext.requires.satisfied_by?(Gem::Version.new(Riffer::Rig::VERSION))
      raise Riffer::ArgumentError,
            "extension #{name} requires riffer-rig #{ext.requires}, found #{Riffer::Rig::VERSION}"
    end

    @extensions[name] = ext
  end

  # : () -> Hash[String, Riffer::Rig::Extension]
  def self.extensions
    @extensions.dup
  end
end
