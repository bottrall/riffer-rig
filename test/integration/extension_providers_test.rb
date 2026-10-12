# frozen_string_literal: true

require 'test_helper'
require_relative '../support/confirming_host'
require_relative '../support/rig_files'

class AcmeSharedProvider < Riffer::Providers::Mock; end # rubocop:disable Rig/NoInheritance -- riffer builds providers through Riffer::Providers::Base subclasses

describe 'providers registered by an extension' do
  include RigFiles

  before do
    @home = Dir.mktmpdir
    @cwd = Dir.mktmpdir
    @config = Riffer::Config.new
  end

  after do
    Riffer::Rig::Providers.unregister(:acme)
    Riffer::Rig::Providers.unregister(:acme_shared)
    FileUtils.remove_entry(@home)
    FileUtils.remove_entry(@cwd)
  end

  def build(model: nil, host: Riffer::Rig::Hosts::Null.new, env: {})
    Riffer::Rig::Loader.runtime(
      cwd: @cwd,
      host: host,
      env: Riffer::Rig::Env.new({ 'MOCK_API_KEY' => 'mock-key' }.merge(env)),
      home: @home,
      riffer_config: @config,
      store: nil,
      options: Riffer::Rig::Loader::Options.new(model: model)
    )
  end

  def write_provider_rig(setup = nil)
    fields = setup ? ", setup: #{setup}" : ''
    write_rig(:home, <<~RUBY)
      class AcmeRigProvider < Riffer::Providers::Mock
        attr_reader :credentials

        private

        def build_request_params(messages, model, options)
          @credentials = Riffer::Rig.credentials('acme')
          super
        end
      end
      Riffer::Rig.extension('acme') { |rig| rig.provider('acme'#{fields}) { AcmeRigProvider } }
    RUBY
  end

  # The model is validated before the rig.rb files load, so a first build on
  # another provider is what registers the extension's.
  def build_on_acme
    build(model: 'mock/test')
    build(model: 'acme/foo', env: { 'ACME_API_KEY' => 'sk-acme' })
  end

  it 'reads the credentials through Riffer::Rig.credentials during a request' do
    write_provider_rig("{ fields: [{ name: :api_key, env: ['ACME_API_KEY'], secret: true, required: true }] }")
    runtime = build_on_acme
    runtime.agent.provider.stub_response('All done.')
    runtime.ask('hello')

    assert_equal({ api_key: 'sk-acme' }, runtime.agent.provider.credentials)
  end

  it 'lists the provider in the onboarding question' do
    Riffer::Rig::Registrar.new('acme').provider(:acme) { Riffer::Providers::Mock }
    host = ConfirmingHost.new(['mock/test'])
    build(host: host)

    assert_match(/with a provider from: .*acme/, host.questions.first)
  end

  it 'gives two Runtimes the same registered prefix' do
    extension = Riffer::Rig::Extension.new('acme') { |rig| rig.provider(:acme_shared) { AcmeSharedProvider } }
    first = Riffer::Rig::Runtime.new('acme_shared/first', extensions: [extension])
    second = Riffer::Rig::Runtime.new('acme_shared/second', extensions: [extension])

    assert_instance_of AcmeSharedProvider, second.agent.provider
  ensure
    [first, second].compact.each(&:close)
  end
end
