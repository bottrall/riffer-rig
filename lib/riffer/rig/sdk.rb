# frozen_string_literal: true

module Riffer::Rig::SDK
  extend self

  CONFIRM_QUESTION = 'Install the %s gem now?' #: String

  PROGRESS_LABEL = 'Installing %s %s' #: String

  BUNDLER_MESSAGE = "%s is not installed and Bundler manages the load path; add gem '%s', '%s' to the Gemfile" #: String

  DECLINED_MESSAGE = "%s is not installed; install it with gem install %s -v '%s' or add it to a Gemfile" #: String

  FAILED_MESSAGE = '%s was installed but could not be loaded' #: String

  private_constant :CONFIRM_QUESTION, :PROGRESS_LABEL, :BUNDLER_MESSAGE, :DECLINED_MESSAGE, :FAILED_MESSAGE

  # @rbs gem: String
  # @rbs requirement: String
  # @rbs host: Riffer::Rig::Hosts::_Host
  # @rbs return: String?
  def ensure(gem, requirement, host:)
    return nil if installed?(gem, requirement) && require_gem(gem)
    return format(BUNDLER_MESSAGE, gem, gem, requirement) if bundler?

    return format(DECLINED_MESSAGE, gem, gem, requirement) unless host.confirm(format(CONFIRM_QUESTION, gem))

    host.progress(format(PROGRESS_LABEL, gem, requirement)) do
      Gem.install(gem, Gem::Requirement.new(requirement))
      Gem.clear_paths
    end
    return nil if require_gem(gem)

    format(FAILED_MESSAGE, gem)
  end

  private

  # @rbs gem: String
  # @rbs requirement: String
  # @rbs return: bool
  def installed?(gem, requirement)
    Gem::Specification.find_by_name(gem, requirement)
    true
  rescue Gem::LoadError
    false
  end

  # @rbs gem: String
  # @rbs return: bool
  def require_gem(gem)
    require gem
    true
  rescue ::LoadError
    false
  end

  # @rbs return: bool
  def bundler?
    !defined?(Bundler).nil?
  end
end
