# frozen_string_literal: true

require 'test_helper'
require 'fileutils'

class ReloadOutcome
  attr_reader :calls

  def initialize(outcome)
    @outcome = outcome
    @calls = []
  end

  def reload(_runtime, force: false)
    @calls << { force: force }
    @outcome
  end
end

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
      options: Riffer::Rig::Loader::Options.new(model: 'mock/test')
    )
  end

  def run_reload(runtime)
    events = []
    runtime.run_command('reload') { |event| events << event }
    events
  end

  def run_with(reloader, runtime)
    events = []
    ctx = Riffer::Rig::Command::Context.new(
      'reload',
      '',
      runtime: runtime,
      host: Riffer::Rig::Hosts::Null.new,
      settings: {},
      emit: ->(event) { events << event },
      turn: ->(_text) {}
    )
    Riffer::Rig::Commands::Reload.run(reloader, ctx)
    events
  end

  it 'forces the reload' do
    runtime = build_runtime
    reloader = ReloadOutcome.new(runtime)
    run_with(reloader, runtime)

    assert_equal [{ force: true }], reloader.calls
  end

  it 'reports Reloaded' do
    runtime = build_runtime

    assert_equal [Riffer::Rig::Events::CommandOutput.new('reload', 'Reloaded')], run_reload(runtime)
  end

  it 'reports nothing when the reload fails' do
    events = run_with(ReloadOutcome.new('boom'), build_runtime)

    assert_empty events
  end
end
