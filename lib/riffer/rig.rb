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

  # Records an extension block in the process registry and returns the
  # extension object. Re-recording a name replaces the block.
  #
  #   Riffer::Rig.extension('git') do |rig|
  #     rig.tool GitLog
  #   end
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

  # @rbs return: Hash[String, Riffer::Rig::Extension]
  def self.extensions
    @extensions.dup
  end

  # Returns the credential values the Runtime prompting on the calling fiber
  # holds for one provider; nil outside a prompt or when it holds none.
  #
  #   Riffer::Rig.credentials(:acme) # => { api_key: '...' }
  #
  # @rbs id: Symbol
  # @rbs return: Hash[Symbol, String]?
  def self.credentials(id)
    Runtime.current&.then { |runtime| runtime.credentials[id] }
  end
end

Riffer::Rig::Clients.install(Riffer.config)
