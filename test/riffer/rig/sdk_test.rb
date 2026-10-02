# frozen_string_literal: true

require 'test_helper'

class AskRecorder
  attr_reader :confirmations #: Array[String?]

  # @rbs return: void
  def initialize
    @confirmations = []
  end

  # @rbs question: String?
  # @rbs return: bool
  def confirm(question = nil)
    @confirmations << question
    true
  end

  # @rbs label: String?
  # @rbs &block: ? () -> void
  # @rbs return: void
  def progress(_label = nil, &block)
    block&.call
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

  def with_bundler(managed)
    original = Riffer::Rig::SDK.method(:bundler?)
    Riffer::Rig::SDK.define_singleton_method(:bundler?) { managed }
    yield
  ensure
    Riffer::Rig::SDK.define_singleton_method(:bundler?, original)
  end

  def with_gem_stubs
    installs = []
    cleared = []
    install = Gem.method(:install)
    clear = Gem.method(:clear_paths)
    Gem.define_singleton_method(:install) { |name, requirement| installs << [name, requirement] }
    Gem.define_singleton_method(:clear_paths) { cleared << true }
    yield [installs, cleared]
  ensure
    Gem.define_singleton_method(:install, install)
    Gem.define_singleton_method(:clear_paths, clear)
  end

  describe '.ensure' do
    it 'requires a present gem' do
      assert_nil Riffer::Rig::SDK.ensure('json', '>= 0', host: null)
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

    it 'asks the host to install an absent gem outside Bundler' do
      host = AskRecorder.new
      with_sdk_absent do
        with_bundler(false) do
          with_gem_stubs do
            Riffer::Rig::SDK.ensure('json', '>= 0', host: host)
          end
        end
      end

      assert_equal ['Install the json gem now?'], host.confirmations
    end

    it 'installs the gem and requirement after a confirm' do
      host = AskRecorder.new
      with_sdk_absent do
        with_bundler(false) do
          with_gem_stubs do |(installs, _)|
            Riffer::Rig::SDK.ensure('json', '>= 0', host: host)

            assert_equal [['json', Gem::Requirement.new('>= 0')]], installs
          end
        end
      end
    end

    it 'clears the gem paths after installing' do
      host = AskRecorder.new
      with_sdk_absent do
        with_bundler(false) do
          with_gem_stubs do |(_, cleared)|
            Riffer::Rig::SDK.ensure('json', '>= 0', host: host)

            assert_equal [true], cleared
          end
        end
      end
    end

    it 'requires the gem after installing it' do
      host = AskRecorder.new
      with_sdk_absent do
        with_bundler(false) do
          with_gem_stubs do
            result = Riffer::Rig::SDK.ensure('json', '>= 0', host: host)

            assert_nil result
          end
        end
      end
    end
  end

  describe 'gemspec' do
    it 'depends on no provider SDK' do
      spec = Gem::Specification.load('riffer-rig.gemspec')
      sdks = spec.runtime_dependencies.select do |dependency|
        %w[anthropic openai aws-sdk-bedrockruntime].include?(dependency.name)
      end

      assert_empty sdks
    end
  end
end
