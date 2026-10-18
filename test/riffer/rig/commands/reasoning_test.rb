# frozen_string_literal: true

require 'test_helper'
require 'fileutils'
require 'json'

describe Riffer::Rig::Commands::Reasoning do
  before do
    FileUtils.rm_f(Riffer::Rig::Settings::File::PATH)
  end

  after do
    FileUtils.rm_f(Riffer::Rig::Settings::File::PATH)
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
    FileUtils.mkdir_p(File.dirname(Riffer::Rig::Settings::File::PATH))
    File.write(Riffer::Rig::Settings::File::PATH, JSON.generate(data))
  end

  def saved_settings
    return {} unless File.file?(Riffer::Rig::Settings::File::PATH)

    JSON.parse(File.read(Riffer::Rig::Settings::File::PATH))
  end

  def malform(path)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, '{"reasoning":"low",}')
  end

  def malformed(path)
    Riffer::Rig::Events::Notify.new("#{path} is not valid JSON at line 1 column 20", :error)
  end

  # The levels are per provider and the mock provider takes none, so the tests
  # that exercise a switch read the openai levels off any model string.
  def with_openai_levels
    provider_for = Riffer::Rig::Settings::ModelOptions.method(:provider_for)
    Riffer::Rig::Settings::ModelOptions.define_singleton_method(:provider_for) { |_model| 'openai' }
    yield
  ensure
    Riffer::Rig::Settings::ModelOptions.define_singleton_method(:provider_for, provider_for)
  end

  it 'reports the level in effect without arguments' do
    runtime = Riffer::Rig::Runtime.new('mock/test', settings: { reasoning: 'high' })

    assert_equal [output('Reasoning: high')], command_events(runtime, '')
  end

  it 'reports default without a level in effect' do
    assert_equal [output('Reasoning: default')], command_events(Riffer::Rig::Runtime.new('mock/test'), '')
  end

  describe 'a level switch' do
    def switch(args)
      runtime = Riffer::Rig::Runtime.new('mock/test')
      events = with_openai_levels { command_events(runtime, args) }

      [runtime, events]
    end

    it 'switches the level for the session' do
      runtime, = switch('high')

      assert_equal 'high', runtime.reasoning
    end

    it 're-derives the model options for the level' do
      runtime, = switch('high')

      assert_equal 'high', runtime.agent.config.model_options[:reasoning]
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

      assert_equal [output('Reasoning switched to high and saved to ~/.riffer/settings.json')], events
    end

    it 'keeps the other settings keys when it saves' do
      write_home_settings(model: 'openai/gpt-5')
      switch('high --save')

      assert_equal 'openai/gpt-5', saved_settings['model']
    end

    it 'refuses a level the provider does not accept' do
      _, events = switch('turbo')

      assert_equal([output('Use /reasoning level, with a level from: low, medium, high, xhigh')], events)
    end

    it 'keeps the level after refusing one the provider does not accept' do
      runtime, = switch('turbo')

      assert_nil runtime.reasoning
    end

    it 'saves nothing when it refuses a level' do
      switch('turbo --save')

      assert_empty saved_settings
    end
  end

  describe 'a provider without levels' do
    it 'refuses any level naming the provider' do
      events = command_events(Riffer::Rig::Runtime.new('mock/test'), 'high')

      assert_equal [output('mock accepts no reasoning level')], events
    end
  end

  describe 'save without a level' do
    it 'saves the level in effect' do
      runtime = Riffer::Rig::Runtime.new('mock/test', settings: { reasoning: 'high' })
      command_events(runtime, '--save')

      assert_equal 'high', saved_settings['reasoning']
    end

    it 'reports the save of the level in effect' do
      runtime = Riffer::Rig::Runtime.new('mock/test', settings: { reasoning: 'high' })

      assert_equal([output('Saved high to ~/.riffer/settings.json')], command_events(runtime, '--save'))
    end

    it 'reports that nothing is in effect to save' do
      assert_equal(
        [output('No reasoning level is in effect to save')],
        command_events(Riffer::Rig::Runtime.new('mock/test'), '--save')
      )
    end

    it 'writes nothing when nothing is in effect to save' do
      command_events(Riffer::Rig::Runtime.new('mock/test'), '--save')

      refute_path_exists Riffer::Rig::Settings::File::PATH
    end
  end

  describe 'a malformed home settings file' do
    it 'reports the file instead of the save' do
      malform(Riffer::Rig::Settings::File::PATH)
      runtime = Riffer::Rig::Runtime.new('mock/test', settings: { reasoning: 'high' })

      assert_equal([malformed(Riffer::Rig::Settings::File::PATH)], command_events(runtime, '--save'))
    end

    it 'reports the switch and then the file for the save of a switch' do
      malform(Riffer::Rig::Settings::File::PATH)
      runtime = Riffer::Rig::Runtime.new('mock/test')
      events = with_openai_levels { command_events(runtime, 'high --save') }

      assert_equal([output('Reasoning switched to high'), malformed(Riffer::Rig::Settings::File::PATH)], events)
    end

    it 'keeps the switched level when the save is refused' do
      malform(Riffer::Rig::Settings::File::PATH)
      runtime = Riffer::Rig::Runtime.new('mock/test')
      with_openai_levels { command_events(runtime, 'high --save') }

      assert_equal 'high', runtime.reasoning
    end
  end
end
