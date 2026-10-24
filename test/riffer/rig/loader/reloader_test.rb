# frozen_string_literal: true

require 'test_helper'

describe Riffer::Rig::Loader::Reloader do
  before do
    @host = Riffer::Rig::Hosts::Mirror.new(Riffer::Rig::Hosts::Null.new)
    @state = { 'rig.rb' => Time.at(1) }
    @rediscovered = []
    @settings = {}
    @credentials = { api_key: 'mock-key' }
    @fresh = Riffer::Rig::Extension.new('fresh') { |rig| rig.tool Riffer::Rig::Tools::Read }
    @runtime = Riffer::Rig::Runtime.new('mock/test', host: @host)
  end

  def source
    test = self
    Class.new do
      define_method(:file_state) { test.instance_variable_get(:@state) }
      define_method(:rediscover) { test.instance_variable_get(:@rediscovered) }
      define_method(:validated) { |extensions, _settings| extensions }
    end.new
  end

  def reloader(mode: nil, rediscovers: true)
    Riffer::Rig::Loader::Reloader.new(
      source: source,
      host: @host,
      settings: -> { @settings },
      credentials: ->(_provider) { @credentials },
      extensions: ->(_document, found) { [@fresh, *found] },
      rediscovers: rediscovers,
      mode: mode
    )
  end

  def change_files
    @state = { 'rig.rb' => Time.at(2) }
  end

  def tool_names(runtime)
    runtime.agent.tools.map(&:name)
  end

  describe '#reload' do
    it 'leaves the runtime alone while the files are unchanged' do
      reloader.reload(@runtime)

      assert_empty tool_names(@runtime)
    end

    it 'rebuilds the runtime once a file changed' do
      subject = reloader
      change_files
      subject.reload(@runtime)

      assert_equal %w[read], tool_names(@runtime)
    end

    it 'returns the runtime it rebuilt' do
      subject = reloader
      change_files

      assert_same @runtime, subject.reload(@runtime)
    end

    it 'rebuilds unchanged files when forced' do
      reloader.reload(@runtime, force: true)

      assert_equal %w[read], tool_names(@runtime)
    end

    it 'leaves the runtime alone under a manual mode' do
      subject = reloader(mode: :manual)
      change_files
      subject.reload(@runtime)

      assert_empty tool_names(@runtime)
    end

    it 'leaves the runtime alone when the setting says manual' do
      subject = reloader
      @settings = { reload: 'manual' }
      change_files
      subject.reload(@runtime)

      assert_empty tool_names(@runtime)
    end

    it 'lets an auto mode override a manual setting' do
      subject = reloader(mode: :auto)
      @settings = { reload: 'manual' }
      change_files
      subject.reload(@runtime)

      assert_equal %w[read], tool_names(@runtime)
    end

    it 'never sees a change without rediscovery' do
      subject = reloader(rediscovers: false)
      change_files
      subject.reload(@runtime)

      assert_empty tool_names(@runtime)
    end

    it 'adds the rediscovered extensions' do
      @rediscovered = [Riffer::Rig::Extension.new('found') { |rig| rig.tool Riffer::Rig::Tools::Write }]
      reloader.reload(@runtime, force: true)

      assert_equal %w[read write], tool_names(@runtime)
    end

    it 'merges the provider credentials into the runtime' do
      reloader.reload(@runtime, force: true)

      assert_equal @credentials, @runtime.credentials[:mock]
    end

    it 'reports settings that do not read' do
      @settings = 'settings.json is not valid JSON'

      assert_equal 'settings.json is not valid JSON', reloader.reload(@runtime, force: true)
    end

    it 'reports a rediscovery that failed' do
      @rediscovered = 'rig.rb is not trusted'

      assert_equal 'rig.rb is not trusted', reloader.reload(@runtime, force: true)
    end

    it 'reports credentials that did not resolve' do
      @credentials = 'No mock key'

      assert_equal 'No mock key', reloader.reload(@runtime, force: true)
    end

    it 'reports a raise as its message' do
      @fresh = Riffer::Rig::Extension.new('broken') { |_rig| raise 'boom' }

      assert_equal 'boom', reloader.reload(@runtime, force: true)
    end

    it 'notifies a failure at error level' do
      @credentials = 'No mock key'
      reloader.reload(@runtime, force: true)

      assert_equal [Riffer::Rig::Events::Notify.new('No mock key', :error)], @host.drain
    end

    it 'does not retry a failed reload while the files stay as they were' do
      subject = reloader
      @credentials = 'No mock key'
      change_files
      subject.reload(@runtime)
      @credentials = { api_key: 'mock-key' }
      subject.reload(@runtime)

      assert_empty tool_names(@runtime)
    end
  end
end
