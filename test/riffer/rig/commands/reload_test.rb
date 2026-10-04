# frozen_string_literal: true

require 'test_helper'
require 'fileutils'
require 'json'

describe Riffer::Rig::Commands::Reload do
  before do
    @home = Dir.mktmpdir
    @cwd = Dir.mktmpdir
    @config = Riffer::Config.new
  end

  after do
    FileUtils.remove_entry(@home)
    FileUtils.remove_entry(@cwd)
  end

  def build_runtime
    Riffer::Rig::Loader.runtime(
      cwd: @cwd,
      host: Riffer::Rig::Hosts::Null.new,
      env: Riffer::Rig::Env.new({ 'MOCK_API_KEY' => 'mock-key' }),
      home: @home,
      riffer_config: @config,
      model: 'mock/test'
    )
  end

  def run_reload(runtime)
    events = []
    runtime.run_command('reload') { |event| events << event }
    events
  end

  it 'is installed by the Loader' do
    assert_includes build_runtime.commands.map(&:name), 'reload'
  end

  it 'reports Reloaded' do
    runtime = build_runtime

    assert_equal [Riffer::Rig::Events::CommandOutput.new('reload', 'Reloaded')], run_reload(runtime)
  end

  it 'reloads the tracked file set' do
    rig_path = File.expand_path(File.join(@cwd, '.riffer', 'rig.rb'))
    FileUtils.mkdir_p(File.join(@home, '.riffer'))
    File.write(File.join(@home, '.riffer', 'trust.json'), JSON.generate({ rig_path => true }))
    FileUtils.mkdir_p(File.join(@cwd, '.riffer'))
    File.write(File.join(@cwd, '.riffer', 'rig.rb'), <<~RUBY)
      class ProbeTool < Riffer::Tool
        identifier 'probe'
        description 'probe'
        def call(context:) = text('probe')
      end
      Riffer::Rig.extension('probe') { |rig| rig.tool ProbeTool }
    RUBY
    runtime = build_runtime
    File.write(File.join(@cwd, '.riffer', 'rig.rb'), <<~RUBY)
      class ProbeTool < Riffer::Tool
        identifier 'probe_next'
        description 'probe'
        def call(context:) = text('probe')
      end
      Riffer::Rig.extension('probe') { |rig| rig.tool ProbeTool }
    RUBY
    run_reload(runtime)

    assert_includes runtime.agent.tools.map(&:identifier), 'probe_next'
  end

  it 'stays installed after the rebuild it triggers' do
    runtime = build_runtime
    run_reload(runtime)
    events = run_reload(runtime)

    assert_equal [Riffer::Rig::Events::CommandOutput.new('reload', 'Reloaded')], events
  end
end
