# frozen_string_literal: true

require 'test_helper'
require 'fileutils'
require 'json'

describe Riffer::Rig::Commands::Reasoning do
  before do
    @home = Dir.mktmpdir
    @settings_path = File.join(@home, 'settings.json')
  end

  after do
    FileUtils.remove_entry(@home)
  end

  def new_runtime(**)
    Riffer::Rig::Runtime.new('mock/test', settings_path: @settings_path, **)
  end

  def command_events(runtime, args)
    events = []
    runtime.run_command('reasoning', args) { |event| events << event }
    events
  end

  def output(text)
    Riffer::Rig::Events::CommandOutput.new('reasoning', text)
  end

  def write_home_settings(data)
    FileUtils.mkdir_p(File.dirname(@settings_path))
    File.write(@settings_path, JSON.generate(data))
  end

  def saved_settings
    return {} unless File.file?(@settings_path)

    JSON.parse(File.read(@settings_path))
  end

  def malform(path)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, '{"reasoning":"low",}')
  end

  def malformed(path)
    Riffer::Rig::Events::Notify.new("#{path} is not valid JSON at line 1 column 20", :error)
  end

  it 'reports the level in effect without arguments' do
    runtime = new_runtime(settings: { reasoning: 'high' })

    assert_equal [output('Reasoning: high')], command_events(runtime, '')
  end

  it 'reports default without a level in effect' do
    assert_equal [output('Reasoning: default')], command_events(new_runtime, '')
  end

  describe 'a level switch' do
    def switch(args)
      runtime = new_runtime

      [runtime, command_events(runtime, args)]
    end

    it 'switches the level for the session' do
      runtime, = switch('high')

      assert_equal 'high', runtime.reasoning
    end

    it 'carries the switched level to the agent config' do
      runtime, = switch('high')

      assert_equal :high, runtime.agent.config.reasoning
    end

    it 'reports the switch' do
      _, events = switch('high')

      assert_equal [output('Reasoning switched to high')], events
    end

    it 'saves the level with --save' do
      switch('high --save')

      assert_equal 'high', saved_settings['reasoning']
    end

    it 'reports the switch and the save' do
      _, events = switch('high --save')

      assert_equal [output("Reasoning switched to high and saved to #{@settings_path}")], events
    end

    it 'keeps the other settings keys when it saves' do
      write_home_settings(model: 'openai/gpt-5')
      switch('high --save')

      assert_equal 'openai/gpt-5', saved_settings['model']
    end

    it 'refuses a level riffer does not accept' do
      _, events = switch('turbo')

      assert_equal([output('turbo is not a reasoning level; riffer accepts: off low medium high xhigh max')], events)
    end

    it 'keeps the level after refusing one riffer does not accept' do
      runtime, = switch('turbo')

      assert_nil runtime.reasoning
    end

    it 'saves nothing when it refuses a level' do
      switch('turbo --save')

      assert_empty saved_settings
    end
  end

  describe 'the off level' do
    it 'switches reasoning off for the session' do
      runtime = new_runtime
      command_events(runtime, 'off')

      assert_equal :off, runtime.agent.config.reasoning
    end

    it 'reports off as the level in effect' do
      runtime = new_runtime
      command_events(runtime, 'off')

      assert_equal [output('Reasoning: off')], command_events(runtime, '')
    end

    it 'saves off with --save' do
      runtime = new_runtime
      command_events(runtime, 'off --save')

      assert_equal 'off', saved_settings['reasoning']
    end
  end

  describe 'save without a level' do
    it 'saves the level in effect' do
      runtime = new_runtime(settings: { reasoning: 'high' })
      command_events(runtime, '--save')

      assert_equal 'high', saved_settings['reasoning']
    end

    it 'reports the save of the level in effect' do
      runtime = new_runtime(settings: { reasoning: 'high' })

      assert_equal([output("Saved high to #{@settings_path}")], command_events(runtime, '--save'))
    end

    it 'reports that nothing is in effect to save' do
      assert_equal([output('No reasoning level is in effect to save')], command_events(new_runtime, '--save'))
    end

    it 'writes nothing when nothing is in effect to save' do
      command_events(new_runtime, '--save')

      refute_path_exists @settings_path
    end
  end

  describe 'a malformed home settings file' do
    it 'reports the file instead of the save' do
      malform(@settings_path)
      runtime = new_runtime(settings: { reasoning: 'high' })

      assert_equal([malformed(@settings_path)], command_events(runtime, '--save'))
    end

    it 'reports the switch and then the file for the save of a switch' do
      malform(@settings_path)
      runtime = new_runtime
      events = command_events(runtime, 'high --save')

      assert_equal([output('Reasoning switched to high'), malformed(@settings_path)], events)
    end

    it 'keeps the switched level when the save is refused' do
      malform(@settings_path)
      runtime = new_runtime
      command_events(runtime, 'high --save')

      assert_equal 'high', runtime.reasoning
    end
  end
end
