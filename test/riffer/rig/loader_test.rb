# frozen_string_literal: true

require 'test_helper'
require 'json'
require 'forwardable'

class ScriptedHost
  extend Forwardable

  def_delegators :@null, :confirm, :notify, :progress

  attr_reader :questions

  def initialize(*answers)
    @null = Riffer::Rig::Hosts::Null.new
    @answers = answers
    @questions = []
  end

  def capabilities
    Set[:ask]
  end

  def ask(question = nil, options: nil, secret: false)
    @questions << question
    @answers.shift
  end
end

describe Riffer::Rig::Loader do
  before do
    @home = Dir.mktmpdir
    @cwd = Dir.mktmpdir
    @config = Riffer::Config.new
  end

  after do
    FileUtils.remove_entry(@home)
    FileUtils.remove_entry(@cwd)
  end

  def write_settings(dir, data)
    FileUtils.mkdir_p(File.join(dir, '.riffer'))
    File.write(File.join(dir, '.riffer', 'settings.json'), JSON.generate(data))
  end

  def home_settings
    JSON.parse(File.read(File.join(@home, '.riffer', 'settings.json')))
  end

  def build(host: Riffer::Rig::Hosts::Null.new, env: { 'MOCK_API_KEY' => 'mock-key' }, **keywords)
    Riffer::Rig::Loader.runtime(
      cwd: @cwd, host: host, env: Riffer::Rig::Env.new(env), home: @home, riffer_config: @config, **keywords
    )
  end

  def refusal
    yield
    nil
  rescue Riffer::Rig::Loader::ConfigurationError => e
    e.message
  end

  def tool_names(runtime)
    runtime.agent.tools.map(&:identifier)
  end

  def system_message(runtime)
    runtime.agent.provider.stub_response('All done.')
    runtime.ask('hello')
    runtime.agent.provider.calls.last[:messages].first[:content]
  end

  def write_skill(name)
    dir = File.join(@cwd, '.agents', 'skills', name)
    FileUtils.mkdir_p(dir)
    File.write(File.join(dir, 'SKILL.md'), "---\nname: #{name}\ndescription: Skill #{name}.\n---\nDo #{name}.\n")
  end

  describe '.runtime' do
    it 'returns a Runtime for the working directory' do
      assert_equal @cwd, build(model: 'mock/test').cwd
    end

    it 'loads the bundled tools' do
      assert_equal %w[read write edit bash], tool_names(build(model: 'mock/test'))
    end

    it 'loads the bundled AGENTS.md section' do
      File.write(File.join(@cwd, 'AGENTS.md'), 'PROJECT_RULES')

      assert_includes system_message(build(model: 'mock/test')), 'PROJECT_RULES'
    end

    it 'loads the bundled skills' do
      write_skill('tidy')

      assert_includes build(model: 'mock/test').commands.map(&:name), 'skill:tidy'
    end

    it 'leaves out an extension disabled in home settings' do
      write_settings(@home, { extensions: { disabled: ['bash'] } })

      assert_equal %w[read write edit], tool_names(build(model: 'mock/test'))
    end

    it 'adds up the disabled extensions of both scopes' do
      write_settings(@home, { extensions: { disabled: ['bash'] } })
      write_settings(@cwd, { extensions: { disabled: ['edit'] } })

      assert_equal %w[read write], tool_names(build(model: 'mock/test'))
    end

    it 'leaves out the skills extension with skills: false' do
      write_skill('tidy')

      refute_includes build(model: 'mock/test', skills: false).commands.map(&:name), 'skill:tidy'
    end

    it 'leaves out the AGENTS.md section with agents_md: false' do
      File.write(File.join(@cwd, 'AGENTS.md'), 'PROJECT_RULES')

      refute_includes system_message(build(model: 'mock/test', agents_md: false)), 'PROJECT_RULES'
    end

    it 'hands tools: to the Runtime' do
      assert_equal %w[read], tool_names(build(model: 'mock/test', tools: %w[read]))
    end

    it 'hands max_steps: to the Runtime' do
      assert_equal 3, build(model: 'mock/test', max_steps: 3).agent.config.max_steps
    end

    it 'hands the merged settings to the Runtime' do
      write_settings(@home, { git: { depth: 10, remote: 'origin' } })
      write_settings(@cwd, { git: { depth: 3 } })

      assert_equal({ depth: 3, remote: 'origin' }, build(model: 'mock/test').settings[:git])
    end

    it 'hands the pricing table to the Runtime' do
      write_settings(@home, { models: { 'mock/test' => { input: 3.0, output: 15.0 } } })
      build(model: 'mock/test')

      refute_nil @config.pricing.rates_for('mock/test')
    end

    it 'hands the model options to the Runtime' do
      write_settings(@home, { reasoning: 'high' })

      assert_equal(
        { reasoning: 'high' },
        build(model: 'openai/o3', env: { 'OPENAI_API_KEY' => 'sk' }).agent.config.model_options
      )
    end
  end

  describe 'model selection' do
    it 'takes the model from home settings' do
      write_settings(@home, { model: 'mock/home' })

      assert_equal 'mock/home', build.model
    end

    it 'prefers the project settings model over home' do
      write_settings(@home, { model: 'mock/home' })
      write_settings(@cwd, { model: 'mock/project' })

      assert_equal 'mock/project', build.model
    end

    it 'prefers RIFFER_MODEL over settings' do
      write_settings(@cwd, { model: 'mock/project' })

      assert_equal 'mock/env', build(env: { 'MOCK_API_KEY' => 'k', 'RIFFER_MODEL' => 'mock/env' }).model
    end

    it 'prefers the model keyword over RIFFER_MODEL' do
      assert_equal 'mock/flag',
                   build(model: 'mock/flag', env: { 'MOCK_API_KEY' => 'k', 'RIFFER_MODEL' => 'mock/env' }).model
    end

    it 'rejects a bare model keyword' do
      assert_match(
        %r{\Asonnet is not a provider/name model string; the provider is one of: },
        refusal do
          build(model: 'sonnet')
        end
      )
    end

    it 'rejects a bare settings model' do
      write_settings(@home, { model: 'sonnet' })

      assert_raises(Riffer::Rig::Loader::ConfigurationError) { build }
    end

    it 'rejects a bare RIFFER_MODEL' do
      message = refusal do
        Riffer::Rig::Loader.new(
          cwd: @cwd,
          host: Riffer::Rig::Hosts::Null.new,
          env: Riffer::Rig::Env.load('RIFFER_MODEL' => 'sonnet')
        )
      end

      assert_match(%r{\ARIFFER_MODEL: sonnet is not a provider/name model string}, message)
    end
  end

  describe 'onboarding' do
    it 'raises the configuration error when the null host declines' do
      assert_raises(Riffer::Rig::Loader::ConfigurationError) { build }
    end

    it 'says how to set a model when the host declines' do
      assert_match(/RIFFER_MODEL/, refusal { build })
    end

    it 'asks the host for a model string listing the providers' do
      host = ScriptedHost.new('mock/chosen')
      build(host: host)

      assert_equal 'Which model should riffer use? Enter provider/name, with a provider from: ' \
                   'amazon_bedrock, anthropic, azure_openai, gemini, openai, openrouter',
                   host.questions.first
    end

    it 'builds the Runtime with the answer' do
      assert_equal 'mock/chosen', build(host: ScriptedHost.new('mock/chosen')).model
    end

    it 'writes the answer to home settings' do
      build(host: ScriptedHost.new('mock/chosen'))

      assert_equal 'mock/chosen', home_settings['model']
    end

    it 'keeps the other home settings when writing the answer' do
      write_settings(@home, { reasoning: 'low' })
      build(host: ScriptedHost.new('mock/chosen'))

      assert_equal 'low', home_settings['reasoning']
    end

    it 'rejects a bare answer' do
      assert_raises(Riffer::Rig::Loader::ConfigurationError) { build(host: ScriptedHost.new('sonnet')) }
    end

    it 'writes nothing for a bare answer' do
      refusal { build(host: ScriptedHost.new('sonnet')) }

      refute_path_exists File.join(@home, '.riffer', 'settings.json')
    end

    it 'does not ask when a model is set' do
      host = ScriptedHost.new
      build(host: host, model: 'mock/test')

      assert_empty host.questions
    end
  end

  describe 'credentials' do
    let(:anthropic) { build(model: 'anthropic/claude-sonnet-4-6', env: { 'ANTHROPIC_API_KEY' => 'sk-ant-env' }) }

    it 'assigns the resolved key to the riffer config' do
      anthropic

      assert_equal 'sk-ant-env', @config.anthropic.api_key
    end

    it 'hands the resolved values to the Runtime' do
      assert_equal({ anthropic: { api_key: 'sk-ant-env' } }, anthropic.credentials)
    end

    it 'reads a key stored in the home auth.json' do
      FileUtils.mkdir_p(File.join(@home, '.riffer'))
      File.write(
        File.join(@home, '.riffer', 'auth.json'),
        JSON.generate({ anthropic: { type: 'api_key', api_key: 'sk-ant-stored' } })
      )

      assert_equal(
        { api_key: 'sk-ant-stored' },
        build(model: 'anthropic/claude-sonnet-4-6', env: {}).credentials[:anthropic]
      )
    end

    it 'asks a host that can ask for a missing key' do
      host = ScriptedHost.new('sk-ant-pasted')

      assert_equal(
        { api_key: 'sk-ant-pasted' },
        build(host: host, model: 'anthropic/claude-sonnet-4-6', env: {}).credentials[:anthropic]
      )
    end

    it 'raises the configuration error naming a key the null host cannot supply' do
      assert_match(
        /\Aanthropic has no api_key \(ANTHROPIC_API_KEY\)/,
        refusal { build(model: 'anthropic/claude-sonnet-4-6', env: {}) }
      )
    end
  end
end
