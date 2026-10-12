# frozen_string_literal: true

require 'test_helper'

class AskRecorder
  attr_reader :capabilities #: Set[Symbol]
  attr_reader :confirmations #: Array[String?]

  # @rbs capabilities: Set[Symbol]
  # @rbs answer: bool
  # @rbs return: void
  def initialize(capabilities = Set[:confirm], answer: true)
    @capabilities = capabilities
    @answer = answer
    @confirmations = []
  end

  # @rbs question: String?
  # @rbs return: bool
  def confirm(question = nil)
    @confirmations << question
    @answer
  end

  # @rbs label: String?
  # @rbs &block: ? () -> void
  # @rbs return: void
  def progress(_label = nil, &block)
    block&.call
  end
end

class InstallRecorder
  attr_reader :installs #: Array[[String, Gem::Requirement]]
  attr_reader :clears #: Integer

  # @rbs failure: Gem::Exception?
  # @rbs return: void
  def initialize(failure = nil)
    @failure = failure
    @installs = []
    @clears = 0
  end

  # @rbs name: String
  # @rbs requirement: Gem::Requirement
  # @rbs return: void
  def install(name, requirement)
    raise @failure if @failure

    @installs << [name, requirement]
  end

  # @rbs return: void
  def clear_paths
    @clears += 1
  end
end

describe Riffer::Rig::SDK do
  let(:null) { Riffer::Rig::Hosts::Null.new }

  def with_sdk_absent
    original = Gem::Specification.method(:find_by_name)
    Gem::Specification.define_singleton_method(:find_by_name) { |*_args| raise Gem::LoadError, 'not installed' }
    yield
  ensure
    Gem::Specification.define_singleton_method(:find_by_name, original)
  end

  def with_sdk_present
    original = Gem::Specification.method(:find_by_name)
    Gem::Specification.define_singleton_method(:find_by_name) { |*_args| true }
    yield
  ensure
    Gem::Specification.define_singleton_method(:find_by_name, original)
  end

  def with_bundler(managed)
    original = Riffer::Rig::SDK.method(:bundler?)
    Riffer::Rig::SDK.define_singleton_method(:bundler?) { managed }
    yield
  ensure
    Riffer::Rig::SDK.define_singleton_method(:bundler?, original)
  end

  describe '.ensure' do
    it 'requires a present gem' do
      assert_nil Riffer::Rig::SDK.ensure('json', '>= 0', host: null)
    end

    it 'falls through when an installed gem cannot be loaded' do
      with_sdk_present do
        with_bundler(true) do
          result = Riffer::Rig::SDK.ensure('acme-sdk', '~> 1.0', host: null)

          assert_equal(
            'acme-sdk is not installed and Bundler manages the load path; ' \
            "add gem 'acme-sdk', '~> 1.0' to the Gemfile",
            result
          )
        end
      end
    end

    it 'reports the Gemfile line for an absent gem under Bundler' do
      with_sdk_absent do
        with_bundler(true) do
          result = Riffer::Rig::SDK.ensure('acme-sdk', '~> 1.0', host: null)

          assert_equal(
            'acme-sdk is not installed and Bundler manages the load path; ' \
            "add gem 'acme-sdk', '~> 1.0' to the Gemfile",
            result
          )
        end
      end
    end

    it 'reports how to install when the host declines' do
      with_sdk_absent do
        with_bundler(false) do
          result = Riffer::Rig::SDK.ensure('acme-sdk', '~> 1.0', host: null)

          assert_equal(
            "acme-sdk is not installed; install it with gem install acme-sdk -v '~> 1.0' or add it to a Gemfile",
            result
          )
        end
      end
    end

    it 'does not ask a host that cannot confirm' do
      host = AskRecorder.new(Set[:ask])
      with_sdk_absent do
        with_bundler(false) do
          Riffer::Rig::SDK.ensure('acme-sdk', '~> 1.0', host: host)
        end
      end

      assert_empty host.confirmations
    end

    it 'reports how to install when the user declines the confirm' do
      host = AskRecorder.new(answer: false)
      with_sdk_absent do
        with_bundler(false) do
          result = Riffer::Rig::SDK.ensure('acme-sdk', '~> 1.0', host: host)

          assert_equal(
            "acme-sdk is not installed; install it with gem install acme-sdk -v '~> 1.0' or add it to a Gemfile",
            result
          )
        end
      end
    end

    it 'asks the host to install an absent gem outside Bundler' do
      host = AskRecorder.new
      with_sdk_absent do
        with_bundler(false) do
          Riffer::Rig::SDK.ensure('json', '>= 0', host: host, installer: InstallRecorder.new)
        end
      end

      assert_equal ['Install the json gem now?'], host.confirmations
    end

    it 'installs the gem and requirement after a confirm' do
      installer = InstallRecorder.new
      with_sdk_absent do
        with_bundler(false) do
          Riffer::Rig::SDK.ensure('json', '>= 0', host: AskRecorder.new, installer: installer)
        end
      end

      assert_equal [['json', Gem::Requirement.new('>= 0')]], installer.installs
    end

    it 'reports an install that fails' do
      installer = InstallRecorder.new(Gem::InstallError.new('no write permissions'))
      with_sdk_absent do
        with_bundler(false) do
          result = Riffer::Rig::SDK.ensure('json', '>= 0', host: AskRecorder.new, installer: installer)

          assert_equal 'json could not be installed: no write permissions', result
        end
      end
    end

    it 'clears the gem paths after installing' do
      installer = InstallRecorder.new
      with_sdk_absent do
        with_bundler(false) do
          Riffer::Rig::SDK.ensure('json', '>= 0', host: AskRecorder.new, installer: installer)
        end
      end

      assert_equal 1, installer.clears
    end

    it 'requires the gem after installing it' do
      with_sdk_absent do
        with_bundler(false) do
          result = Riffer::Rig::SDK.ensure('json', '>= 0', host: AskRecorder.new, installer: InstallRecorder.new)

          assert_nil result
        end
      end
    end

    it 'reports a gem that still cannot be loaded after installing' do
      with_sdk_absent do
        with_bundler(false) do
          result = Riffer::Rig::SDK.ensure('acme-sdk', '~> 1.0', host: AskRecorder.new, installer: InstallRecorder.new)

          assert_equal 'acme-sdk was installed but could not be loaded', result
        end
      end
    end
  end
end
