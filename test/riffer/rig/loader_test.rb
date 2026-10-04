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

class ConfirmingHost
  extend Forwardable

  def_delegators :@null, :progress

  attr_reader :questions #: Array[String?]
  attr_reader :notifications #: Array[[Symbol, String]]

  # @rbs answers: Array[untyped]
  # @rbs return: void
  def initialize(answers = [])
    @null = Riffer::Rig::Hosts::Null.new
    @answers = answers
    @questions = []
    @notifications = []
  end

  # @rbs return: Set[Symbol]
  def capabilities
    Set[:ask, :confirm, :notify]
  end

  # @rbs question: String?
  # @rbs options: Array[untyped]?
  # @rbs secret: bool
  # @rbs return: untyped
  def ask(question = nil, options: nil, secret: false)
    @questions << question
    @answers.shift
  end

  # @rbs question: String?
  # @rbs return: untyped
  def confirm(question = nil)
    @questions << question
    @answers.shift
  end

  # @rbs message: String
  # @rbs level: Symbol
  # @rbs return: void
  def notify(message, level: :info)
    @notifications << [level, message]
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

  def write_rig(scope, body)
    root = scope == :home ? @home : @cwd
    FileUtils.mkdir_p(File.join(root, '.riffer'))
    File.write(File.join(root, '.riffer', 'rig.rb'), body)
  end

  def trust_file
    File.join(@home, '.riffer', 'trust.json')
  end

  def project_rig_path
    File.expand_path(File.join(@cwd, '.riffer', 'rig.rb'))
  end

  def home_rig_path
    File.expand_path(File.join(@home, '.riffer', 'rig.rb'))
  end

  def fixture_gem_file
    dir = File.join(@home, 'gems', 'fixture')
    FileUtils.mkdir_p(dir)
    File.write(File.join(dir, 'extension.rb'), <<~RUBY)
      class FixtureProbeTool < Riffer::Tool
        identifier 'fixture_probe'
        description 'fixture'
        def call(context:) = text('fixture')
      end
      Riffer::Rig.extension('fixture') { |rig| rig.tool FixtureProbeTool }
    RUBY
    File.expand_path(File.join(dir, 'extension.rb'))
  end

  def new_loader(host: Riffer::Rig::Hosts::Null.new, env: { 'MOCK_API_KEY' => 'mock-key' })
    Riffer::Rig::Loader.new(
      cwd: @cwd, host: host, env: Riffer::Rig::Env.new(env), home: @home, riffer_config: @config
    )
  end

  def with_gem_files(paths)
    original = Gem.method(:find_files)
    Gem.define_singleton_method(:find_files) { |_glob| paths }
    yield
  ensure
    Gem.define_singleton_method(:find_files, original)
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
      options = Riffer::Rig::Settings.method(:model_options)
      Riffer::Rig::Settings.define_singleton_method(:model_options) { |*_args| { reasoning: 'high' } }
      model_options = build(model: 'mock/test').agent.config.model_options
      Riffer::Rig::Settings.define_singleton_method(:model_options, options)

      assert_equal({ reasoning: 'high' }, model_options)
    end

    it 'hands the native tool switches to the Runtime' do
      write_settings(@home, { tools: { native: { web_search: true } } })

      assert_equal({ web_search: true }, build(model: 'mock/test').agent.config.model_options)
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

  describe 'rig.rb files' do
    it 'loads the home file before the project file' do
      write_rig(:home, '')
      write_rig(:project, '')
      loader = new_loader(host: ConfirmingHost.new([true]))
      loader.runtime(model: 'mock/test')

      assert_equal [home_rig_path, project_rig_path], loader.tracked_files
    end

    it 'appends the extensions the files record after the bundle' do
      write_rig(:home, <<~RUBY)
        class ProbeTool < Riffer::Tool
          identifier 'probe'
          description 'probe'
          def call(context:) = text('probe')
        end
        Riffer::Rig.extension('probe') { |rig| rig.tool ProbeTool }
      RUBY
      names = tool_names(build(model: 'mock/test'))

      assert_operator names.index('probe'), :>, names.index('bash')
    end

    it 'records a require_relative from rig.rb as a tracked file' do
      FileUtils.mkdir_p(File.join(@cwd, '.riffer'))
      File.write(File.join(@cwd, '.riffer', 'local.rb'), 'Riffer::Rig.extension("local") { |rig| }')
      File.write(project_rig_path, "require_relative 'local'")
      loader = new_loader(host: ConfirmingHost.new([true]))
      loader.runtime(model: 'mock/test')

      assert_equal [File.expand_path(File.join(@cwd, '.riffer', 'local.rb')), project_rig_path], loader.tracked_files
    end

    it 'drops required gem paths from the tracked files' do
      write_rig(:project, "require 'json'")
      loader = new_loader(host: ConfirmingHost.new([true]))
      loader.runtime(model: 'mock/test')

      assert_equal [project_rig_path], loader.tracked_files
    end

    it 'reports a raising rig.rb through notify' do
      write_rig(:project, 'raise "boom"')
      host = ConfirmingHost.new([true])
      build(host: host, model: 'mock/test')

      assert_equal [[:error, "#{project_rig_path} failed to load: boom"]], host.notifications
    end

    it "keeps the other file's extensions when one file raises" do
      write_rig(:home, <<~RUBY)
        class ProbeTool < Riffer::Tool
          identifier 'probe'
          description 'probe'
          def call(context:) = text('probe')
        end
        Riffer::Rig.extension('probe') { |rig| rig.tool ProbeTool }
      RUBY
      write_rig(:project, 'raise "boom"')

      assert_includes tool_names(build(host: ConfirmingHost.new([true]), model: 'mock/test')), 'probe'
    end

    it 'skips the extensions a raising file recorded' do
      write_rig(:home, <<~RUBY)
        class DoomedProbeTool < Riffer::Tool
          identifier 'doomed_probe'
          description 'doomed'
          def call(context:) = text('doomed')
        end
        Riffer::Rig.extension('doomed') { |rig| rig.tool DoomedProbeTool }
        raise 'boom'
      RUBY

      refute_includes tool_names(build(model: 'mock/test')), 'doomed_probe'
    end
  end

  describe 'trust' do
    it 'asks to confirm a project file the first time it is seen' do
      write_rig(:project, '')
      host = ConfirmingHost.new([true])
      build(host: host, model: 'mock/test')

      assert_equal ["Trust #{project_rig_path}?"], host.questions
    end

    it 'stores the answer by absolute path' do
      write_rig(:project, '')
      build(host: ConfirmingHost.new([true]), model: 'mock/test')

      assert_equal({ project_rig_path => true }, JSON.parse(File.read(trust_file)))
    end

    it 'does not ask again once an answer is stored' do
      write_rig(:project, '')
      build(host: ConfirmingHost.new([true]), model: 'mock/test')
      second = ConfirmingHost.new([true])
      build(host: second, model: 'mock/test')

      assert_empty second.questions
    end

    it 'skips a declined project file and its extensions' do
      write_rig(:project, <<~RUBY)
        class DeclinedProbeTool < Riffer::Tool
          identifier 'declined_probe'
          description 'declined'
          def call(context:) = text('declined')
        end
        Riffer::Rig.extension('declined') { |rig| rig.tool DeclinedProbeTool }
      RUBY

      refute_includes tool_names(build(host: ConfirmingHost.new([false]), model: 'mock/test')), 'declined_probe'
    end

    it 'does not re-ask a declined file' do
      write_rig(:project, '')
      host = ConfirmingHost.new([false, true])
      build(host: host, model: 'mock/test')
      build(host: host, model: 'mock/test')

      assert_equal 1, host.questions.size
    end

    it 'reports nothing to the host for a declined file' do
      write_rig(:project, '')
      host = ConfirmingHost.new([false])
      build(host: host, model: 'mock/test')

      assert_empty host.notifications
    end

    it 'never asks about the home file' do
      write_rig(:home, '')
      host = ConfirmingHost.new([true])
      build(host: host, model: 'mock/test')

      assert_empty host.questions
    end

    it 'skips the project file for a host that cannot confirm' do
      write_rig(:project, <<~RUBY)
        class NullProbeTool < Riffer::Tool
          identifier 'null_probe'
          description 'null'
          def call(context:) = text('null')
        end
        Riffer::Rig.extension('null_probe') { |rig| rig.tool NullProbeTool }
      RUBY

      refute_includes tool_names(build(model: 'mock/test')), 'null_probe'
    end

    it 'does not record a decline from a host that cannot confirm' do
      write_rig(:project, '')
      build(model: 'mock/test')

      refute_path_exists trust_file
    end
  end

  describe 'autoload' do
    it 'requires riffer/rig/extension from the gems Gem.find_files finds' do
      write_settings(@home, { extensions: { autoload: true } })
      gem_file = fixture_gem_file
      runtime = nil
      with_gem_files([gem_file]) { runtime = build(model: 'mock/test') }

      assert_includes tool_names(runtime), 'fixture_probe'
    end

    it 'stays off by default' do
      fixture_gem_file
      build(model: 'mock/test')

      refute_includes tool_names(build(model: 'mock/test')), 'fixture_probe'
    end

    it 'skips the rig.rb files with extensions: false' do
      write_rig(:home, <<~RUBY)
        class SkippedProbeTool < Riffer::Tool
          identifier 'skipped_probe'
          description 'skipped'
          def call(context:) = text('skipped')
        end
        Riffer::Rig.extension('skipped') { |rig| rig.tool SkippedProbeTool }
      RUBY
      write_rig(:project, '')
      host = ConfirmingHost.new([true])
      runtime = build(host: host, model: 'mock/test', extensions: false)

      refute_includes tool_names(runtime), 'skipped_probe'
    end

    it 'skips autoload with extensions: false' do
      write_settings(@home, { extensions: { autoload: true } })
      gem_file = fixture_gem_file
      runtime = nil
      with_gem_files([gem_file]) { runtime = build(model: 'mock/test', extensions: false) }

      refute_includes tool_names(runtime), 'fixture_probe'
    end
  end

  describe 'sdk' do
    def with_sdk_absent_and_installable
      gem_specs = Gem::Specification.method(:find_by_name)
      bundler = Riffer::Rig::SDK.method(:bundler?)
      Gem::Specification.define_singleton_method(:find_by_name) { |*_args| raise Gem::LoadError, 'not installed' }
      Riffer::Rig::SDK.define_singleton_method(:bundler?) { false }
      yield
    ensure
      Gem::Specification.define_singleton_method(:find_by_name, gem_specs)
      Riffer::Rig::SDK.define_singleton_method(:bundler?, bundler)
    end

    it 'builds the Runtime for a provider that needs no SDK gem' do
      with_sdk_absent_and_installable do
        runtime = build(model: 'gemini/gem-2.5-pro', env: { 'GEMINI_API_KEY' => 'k' })

        assert_equal 'gemini/gem-2.5-pro', runtime.model
      end
    end

    it 'reports a declined install instead of building the Runtime' do
      with_sdk_absent_and_installable do
        assert_match(
          /\Aopenai is not installed; install it with gem install openai/,
          refusal { build(model: 'openai/o3', env: { 'OPENAI_API_KEY' => 'sk' }) }
        )
      end
    end
  end

  describe 'credentials' do
    let(:gemini) { build(model: 'gemini/gem-2.5-pro', env: { 'GEMINI_API_KEY' => 'sk-gem-env' }) }

    it 'assigns the resolved key to the riffer config' do
      gemini

      assert_equal 'sk-gem-env', @config.gemini.api_key
    end

    it 'hands the resolved values to the Runtime' do
      assert_equal({ gemini: { api_key: 'sk-gem-env' } }, gemini.credentials)
    end

    it 'reads a key stored in the home auth.json' do
      FileUtils.mkdir_p(File.join(@home, '.riffer'))
      File.write(
        File.join(@home, '.riffer', 'auth.json'),
        JSON.generate({ gemini: { type: 'api_key', api_key: 'sk-gem-stored' } })
      )

      assert_equal({ api_key: 'sk-gem-stored' }, build(model: 'gemini/gem-2.5-pro', env: {}).credentials[:gemini])
    end

    it 'asks a host that can ask for a missing key' do
      host = ScriptedHost.new('sk-gem-pasted')

      assert_equal(
        { api_key: 'sk-gem-pasted' },
        build(host: host, model: 'gemini/gem-2.5-pro', env: {}).credentials[:gemini]
      )
    end

    it 'raises the configuration error naming a key the null host cannot supply' do
      assert_match(
        /\Agemini has no api_key \(GEMINI_API_KEY\)/,
        refusal { build(model: 'gemini/gem-2.5-pro', env: {}) }
      )
    end
  end

  describe 'extension providers' do
    after do
      Riffer::Rig::Providers.unregister(:acme)
      Riffer::Rig::Providers.unregister(:globex)
    end

    def write_provider_rig(identifier, class_name, setup)
      fields = setup ? ", setup: #{setup}" : ''
      write_rig(:home, <<~RUBY)
        class #{class_name} < Riffer::Providers::Mock
          attr_reader :credentials

          private

          def build_request_params(messages, model, options)
            @credentials = Riffer::Rig.credentials(#{identifier.to_s.inspect})
            super
          end
        end
        Riffer::Rig.extension('#{identifier}') { |rig| rig.provider(#{identifier.to_s.inspect}#{fields}) { #{class_name} } }
      RUBY
    end

    it 'resolves a registered provider\'s setup field from its env var' do
      write_provider_rig(
        :acme,
        'AcmeRigProvider',
        "{ fields: [{ name: :api_key, env: ['ACME_API_KEY'], secret: true, required: true }] }"
      )
      build(model: 'mock/test')

      assert_equal(
        { acme: { api_key: 'sk-acme' } },
        build(model: 'acme/foo', env: { 'ACME_API_KEY' => 'sk-acme' }).credentials
      )
    end

    it 'reads the credentials through Riffer::Rig.credentials during a request' do
      write_provider_rig(
        :acme,
        'AcmeRigProvider',
        "{ fields: [{ name: :api_key, env: ['ACME_API_KEY'], secret: true, required: true }] }"
      )
      build(model: 'mock/test')
      runtime = build(model: 'acme/foo', env: { 'ACME_API_KEY' => 'sk-acme' })
      runtime.agent.provider.stub_response('All done.')
      runtime.ask('hello')

      assert_equal({ api_key: 'sk-acme' }, runtime.agent.provider.credentials)
    end

    it 'resolves a setup-less provider through the generic fallback' do
      write_provider_rig(:globex, 'GlobexRigProvider', nil)
      build(model: 'mock/test')

      assert_equal(
        { api_key: 'sk-globex' },
        build(model: 'globex/foo', env: { 'GLOBEX_API_KEY' => 'sk-globex' }).credentials[:globex]
      )
    end

    it 'keeps one entry when a reload registers the provider again' do
      write_provider_rig(:acme, 'AcmeRigProvider', nil)
      build(model: 'mock/test')
      second = build(model: 'acme/foo', env: { 'ACME_API_KEY' => 'sk-acme' })

      assert_same second.agent.provider.class, Riffer::Providers::Repository.find(:acme)
    end

    it 'lists extension providers in the onboarding question' do
      Riffer::Rig::Registrar.new('acme').provider(:acme) { Riffer::Providers::Mock }
      host = ScriptedHost.new('mock/test')
      build(host: host)

      assert_match(/with a provider from: .*acme/, host.questions.first)
    end
  end

  describe '#reload' do
    def probe_rig(identifier)
      <<~RUBY
        class ProbeTool < Riffer::Tool
          identifier '#{identifier}'
          description 'probe'
          def call(context:) = text('probe')
        end
        Riffer::Rig.extension('probe') { |rig| rig.tool ProbeTool }
      RUBY
    end

    def bump(path)
      stamp = File.mtime(path) + 10
      File.utime(stamp, stamp, path)
    end

    def tool_added
      write_rig(:project, probe_rig('probe'))
      host = ConfirmingHost.new([true])
      loader = new_loader(host: host)
      runtime = loader.runtime(model: 'mock/test')
      usage = Riffer::Providers::TokenUsage.new(input_tokens: 7, output_tokens: 3)
      runtime.agent.provider.stub_response('Before.', token_usage: usage)
      runtime.ask('before')
      runtime.model = 'mock/other'
      File.write(project_rig_path, probe_rig('probe_next'))
      [loader, runtime, host]
    end

    def raising_rig
      write_rig(:project, probe_rig('probe'))
      host = ConfirmingHost.new([true])
      loader = new_loader(host: host)
      runtime = loader.runtime(model: 'mock/test')
      File.write(project_rig_path, 'raise "boom"')
      [loader, runtime, host]
    end

    it 'is installed as a command' do
      assert_includes build(model: 'mock/test').commands.map(&:name), 'reload'
    end

    it 'registers a tool added to a tracked file' do
      loader, runtime, = tool_added
      loader.reload(runtime, force: true)

      assert_includes tool_names(runtime), 'probe_next'
    end

    it 'keeps the message history' do
      loader, runtime, = tool_added
      history = runtime.agent.session.messages.drop(1)
      loader.reload(runtime, force: true)

      assert_equal history, runtime.agent.session.messages.drop(1)
    end

    it 'keeps the tally' do
      loader, runtime, = tool_added
      loader.reload(runtime, force: true)

      assert_equal 10, runtime.tally.total_tokens
    end

    it 'keeps the /model override' do
      loader, runtime, = tool_added
      loader.reload(runtime, force: true)

      assert_equal 'mock/other', runtime.model
    end

    it 'reports the rebuilt runtime' do
      loader, runtime, = tool_added
      reloaded = loader.reload(runtime, force: true)

      assert_same runtime, reloaded
    end

    it 'replaces a re-recorded extension rather than duplicating it' do
      loader, runtime, = tool_added
      loader.reload(runtime, force: true)

      assert_equal ['probe_next'], tool_names(runtime).grep(/\Aprobe/)
    end

    it 'reloads without force when a tracked file changed' do
      loader, runtime, = tool_added
      bump(project_rig_path)
      loader.reload(runtime)

      assert_includes tool_names(runtime), 'probe_next'
    end

    it 'skips the reload when no tracked file changed' do
      write_rig(:project, probe_rig('probe'))
      host = ConfirmingHost.new([true])
      loader = new_loader(host: host)
      runtime = loader.runtime(model: 'mock/test')
      marker = File.join(@cwd, 'reload_marker')
      File.write(project_rig_path, "File.write(#{marker.inspect}, 'attempted')\nraise 'boom'")
      bump(project_rig_path)
      loader.reload(runtime)
      FileUtils.rm_f(marker)
      loader.reload(runtime)

      refute_path_exists marker
    end

    it 'abandons the reload when a rig.rb raises' do
      loader, runtime, = raising_rig
      reloaded = loader.reload(runtime, force: true)

      assert_match(/failed to load: boom\z/, reloaded)
    end

    it 'keeps the live registrar when a rig.rb raises on reload' do
      loader, runtime, = raising_rig
      loader.reload(runtime, force: true)

      assert_equal ['probe'], tool_names(runtime).grep(/\Aprobe/)
    end

    it 'notifies once when a rig.rb raises on reload' do
      loader, runtime, host = raising_rig
      loader.reload(runtime, force: true)

      assert_equal [[:error, "#{project_rig_path} failed to load: boom"]], host.notifications
    end

    it 're-reads settings changed on disk' do
      write_settings(@home, { git: { depth: 10 } })
      loader = new_loader
      runtime = loader.runtime(model: 'mock/test')
      write_settings(@home, { git: { depth: 3 } })
      loader.reload(runtime, force: true)

      assert_equal({ depth: 3 }, runtime.settings[:git])
    end

    it 'drops the extensions of a deleted rig.rb' do
      write_rig(:project, probe_rig('probe'))
      loader = new_loader(host: ConfirmingHost.new([true]))
      runtime = loader.runtime(model: 'mock/test')
      FileUtils.rm(project_rig_path)
      loader.reload(runtime, force: true)

      assert_empty tool_names(runtime).grep(/\Aprobe/)
    end

    it 'confirms a project rig.rb appearing mid-session' do
      host = ConfirmingHost.new([true])
      loader = new_loader(host: host)
      runtime = loader.runtime(model: 'mock/test')
      write_rig(:project, probe_rig('probe'))
      loader.reload(runtime, force: true)

      assert_equal ["Trust #{project_rig_path}?"], host.questions
    end

    it 'reports Reloaded from /reload' do
      write_rig(:project, probe_rig('probe'))
      loader = new_loader(host: ConfirmingHost.new([true]))
      runtime = loader.runtime(model: 'mock/test')
      File.write(project_rig_path, probe_rig('probe_next'))
      events = []
      runtime.run_command('reload') { |event| events << event }

      assert_equal [Riffer::Rig::Events::CommandOutput.new('reload', 'Reloaded')], events
    end

    it 'stays installed after the rebuild it triggers' do
      write_rig(:project, probe_rig('probe'))
      loader = new_loader(host: ConfirmingHost.new([true]))
      runtime = loader.runtime(model: 'mock/test')
      runtime.run_command('reload')
      events = []
      runtime.run_command('reload') { |event| events << event }

      assert_equal [Riffer::Rig::Events::CommandOutput.new('reload', 'Reloaded')], events
    end
  end
end
