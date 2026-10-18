# frozen_string_literal: true

require 'test_helper'
require 'json'
require 'forwardable'
require_relative '../../support/confirming_host'
require_relative '../../support/prompter_pty'
require_relative '../../support/rig_files'

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

class RecordingStore
  attr_reader :appended #: Array[[String, Hash[Symbol, untyped]]]

  def initialize
    @appended = [] #: Array[[String, Riffer::Rig::Stores::entry]]
  end

  def append(id, entry)
    @appended << [id, entry]
  end

  def read(_id)
    []
  end

  def list(_cwd: nil)
    []
  end

  def delete(_id)
    nil
  end
end

# A store whose listing order is the reverse of the wrapped store's, proving
# the Loader picks by the header's `updated` and not by position.
class ReversedStore
  def initialize(store)
    @store = store
  end

  def append(id, entry)
    @store.append(id, entry)
  end

  def read(id)
    @store.read(id)
  end

  def list(cwd: nil)
    @store.list(cwd: cwd).reverse
  end

  def delete(id)
    @store.delete(id)
  end
end

LOADER_OPTION_KEYS = %i[model reasoning extensions skills agents_md tools max_steps].freeze

describe Riffer::Rig::Loader do
  include RigFiles

  before do
    @home = Dir.mktmpdir
    @cwd = Dir.mktmpdir
    @config = Riffer::Config.new
  end

  after do
    @pty&.close
    FileUtils.remove_entry(@home)
    FileUtils.remove_entry(@cwd)
  end

  def at_the_terminal_footer(keys)
    @pty = PrompterPty.new
    @pty.answering(keys) { yield @pty.host }
  end

  def write_settings(dir, data)
    FileUtils.mkdir_p(File.join(dir, '.riffer'))
    File.write(File.join(dir, '.riffer', 'settings.json'), JSON.generate(data))
  end

  def write_catalog(dir, data)
    path = File.join(dir, 'models.json')
    File.write(path, JSON.generate(data))
    path
  end

  def home_settings
    JSON.parse(File.read(File.join(@home, '.riffer', 'settings.json')))
  end

  def malform_settings(dir)
    path = File.join(dir, '.riffer', 'settings.json')
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, '{"reasoning":"low",}')
    "#{path} is not valid JSON at line 1 column 20"
  end

  def build(host: Riffer::Rig::Hosts::Null.new, env: { 'MOCK_API_KEY' => 'mock-key' }, **keywords)
    Riffer::Rig::Loader.runtime(
      cwd: @cwd,
      host: host,
      env: Riffer::Rig::Env.new(env),
      home: @home,
      riffer_config: @config,
      options: Riffer::Rig::Loader::Options.new(**keywords.slice(*LOADER_OPTION_KEYS)),
      **keywords.except(*LOADER_OPTION_KEYS)
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

  def loader(store: Riffer::Rig::Stores::JSONL.new(home: @home), host: Riffer::Rig::Hosts::Null.new)
    Riffer::Rig::Loader.new(
      cwd: @cwd,
      host: host,
      env: Riffer::Rig::Env.new({ 'MOCK_API_KEY' => 'mock-key', 'RIFFER_MODEL' => 'mock/test' }),
      home: @home,
      riffer_config: @config,
      store: store
    )
  end

  def turn(runtime, text = 'hello')
    runtime.agent.provider.stub_response('All done.')
    runtime.ask(text)
  end

  def save_session(text = 'hello')
    runtime = loader.runtime(Riffer::Rig::Loader::Options.new(model: 'mock/test'))
    turn(runtime, text)
    runtime
  end

  def save_entries(id, entries)
    store = Riffer::Rig::Stores::JSONL.new(home: @home)
    entries.each { |entry| store.append(id, entry) }
  end

  def header(id, model = 'mock/test', cwd: @cwd)
    Riffer::Rig::Stores::Header.new(
      schema_version: 1,
      id: id,
      cwd: cwd,
      created_at: '2026-01-01T00:00:00Z',
      model: model,
      riffer_rig_version: '0.9.0',
      riffer_version: '0.49.0',
      title: 'hello'
    )
  end

  def session_path(id)
    Dir.glob(File.join(@home, '.riffer', 'sessions', '*', "#{id}.jsonl")).first
  end

  def age(path, seconds)
    time = Time.at(seconds)
    File.utime(time, time, path)
  end

  describe '.runtime' do
    it 'returns a Runtime for the working directory' do
      assert_equal @cwd, build(model: 'mock/test').cwd
    end
  end

  describe '#initialize' do
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

    it 'roots the default store at home' do
      saved = save_session

      assert_equal [saved.id], new_loader.list.map(&:id)
    end
  end

  describe '#runtime' do
    describe 'malformed settings' do
      it 'raises the configuration error naming the home file' do
        malformed = malform_settings(@home)

        assert_equal(malformed, refusal { build(model: 'mock/test') })
      end

      it 'raises the configuration error naming the project file' do
        malformed = malform_settings(@cwd)

        assert_equal(malformed, refusal { build(model: 'mock/test') })
      end

      it 'raises the configuration error naming a file whose model is not a string' do
        write_settings(@cwd, { model: 5 })

        assert_equal(
          "#{File.join(@cwd, '.riffer', 'settings.json')} sets \"model\" to a value that is not a string",
          refusal { build(model: 'mock/test') }
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

      it 'restores the snapshot model over RIFFER_MODEL' do
        snapshot = { id: 'saved', messages: [], model: 'mock/saved', skills: [] }

        assert_equal 'mock/saved',
                     build(snapshot: snapshot, env: { 'MOCK_API_KEY' => 'k', 'RIFFER_MODEL' => 'mock/env' }).model
      end

      it 'prefers the model keyword over the snapshot model' do
        snapshot = { id: 'saved', messages: [], model: 'mock/saved', skills: [] }

        assert_equal 'mock/flag', build(snapshot: snapshot, model: 'mock/flag').model
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
    end

    describe 'reasoning selection' do
      it 'takes the reasoning level from the settings' do
        write_settings(@home, { reasoning: 'high' })

        assert_equal 'high', build(model: 'openai/o3', env: { 'OPENAI_API_KEY' => 'sk' }).reasoning
      end

      it 'prefers RIFFER_REASONING over the settings' do
        write_settings(@home, { reasoning: 'low' })

        assert_equal(
          'high',
          build(model: 'openai/o3', env: { 'OPENAI_API_KEY' => 'sk', 'RIFFER_REASONING' => 'high' }).reasoning
        )
      end

      it 'prefers the reasoning keyword over RIFFER_REASONING' do
        assert_equal(
          'high',
          build(
            model: 'openai/o3',
            reasoning: 'high',
            env: { 'OPENAI_API_KEY' => 'sk', 'RIFFER_REASONING' => 'low' }
          ).reasoning
        )
      end

      it 'hands the level in effect to the agent config' do
        write_settings(@home, { reasoning: 'high' })
        runtime = build(model: 'openai/o3', env: { 'OPENAI_API_KEY' => 'sk' })

        assert_equal :high, runtime.agent.config.reasoning
      end

      it 'rejects a reasoning keyword riffer does not accept' do
        assert_equal(
          'turbo is not a reasoning level; riffer accepts: off low medium high xhigh max',
          refusal { build(model: 'openai/o3', reasoning: 'turbo', env: { 'OPENAI_API_KEY' => 'sk' }) }
        )
      end

      it 'rejects a RIFFER_REASONING riffer does not accept' do
        assert_equal(
          'RIFFER_REASONING: turbo is not a reasoning level; riffer accepts: off low medium high xhigh max',
          refusal { build(model: 'openai/o3', env: { 'OPENAI_API_KEY' => 'sk', 'RIFFER_REASONING' => 'turbo' }) }
        )
      end

      it 'rejects RIFFER_REASONING even when the settings also set a level' do
        write_settings(@home, { reasoning: 'high' })

        assert_raises(Riffer::Rig::Loader::ConfigurationError) do
          build(model: 'openai/o3', env: { 'OPENAI_API_KEY' => 'sk', 'RIFFER_REASONING' => 'turbo' })
        end
      end

      it 'takes off from the settings as a level of its own' do
        write_settings(@home, { reasoning: 'off' })

        assert_equal :off, build(model: 'openai/o3', env: { 'OPENAI_API_KEY' => 'sk' }).agent.config.reasoning
      end

      it 'leaves an unrecognized settings level at the model default' do
        write_settings(@home, { reasoning: 'turbo' })
        runtime = build(model: 'openai/o3', env: { 'OPENAI_API_KEY' => 'sk' })

        assert_nil runtime.agent.config.reasoning
      end

      it 'restores the snapshot reasoning over RIFFER_REASONING' do
        snapshot = { id: 'saved', messages: [], model: nil, reasoning: 'low', skills: [] }

        assert_equal(
          'low',
          build(
            snapshot: snapshot,
            model: 'openai/o3',
            env: { 'OPENAI_API_KEY' => 'sk', 'RIFFER_REASONING' => 'high' }
          ).reasoning
        )
      end

      it 'carries the snapshot reasoning to the agent config' do
        snapshot = { id: 'saved', messages: [], model: nil, reasoning: 'low', skills: [] }
        runtime = build(snapshot: snapshot, model: 'openai/o3', env: { 'OPENAI_API_KEY' => 'sk' })

        assert_equal :low, runtime.agent.config.reasoning
      end

      it 'ignores a snapshot reasoning that is not a string' do
        snapshot = { id: 'saved', messages: [], model: nil, reasoning: 3, skills: [] }

        assert_equal(
          'high',
          build(
            snapshot: snapshot,
            model: 'openai/o3',
            env: { 'OPENAI_API_KEY' => 'sk', 'RIFFER_REASONING' => 'high' }
          ).reasoning
        )
      end

      it 'prefers the reasoning keyword over the snapshot reasoning' do
        snapshot = { id: 'saved', messages: [], model: nil, reasoning: 'low', skills: [] }

        assert_equal(
          'high',
          build(snapshot: snapshot, model: 'openai/o3', reasoning: 'high', env: { 'OPENAI_API_KEY' => 'sk' }).reasoning
        )
      end

      it 'drops a snapshot reasoning level riffer does not accept' do
        snapshot = { id: 'saved', messages: [], model: nil, reasoning: 'turbo', skills: [] }
        runtime = build(snapshot: snapshot, model: 'openai/o3', env: { 'OPENAI_API_KEY' => 'sk' })

        assert_nil runtime.agent.config.reasoning
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

      it 'does not ask a host that cannot ask' do
        host = ScriptedHost.new('mock/chosen')
        host.define_singleton_method(:capabilities) { Set[:confirm] }
        refusal { build(host: host) }

        assert_empty host.questions
      end

      it 'builds the Runtime with the answer' do
        assert_equal 'mock/chosen', build(host: ScriptedHost.new('mock/chosen')).model
      end

      it 'builds the Runtime with the answer typed at the terminal footer' do
        runtime = at_the_terminal_footer("mock/chosen\r") { |host| build(host: host) }

        assert_equal 'mock/chosen', runtime.model
      end

      it 'writes the answer to home settings' do
        build(host: ScriptedHost.new('mock/chosen'))

        assert_equal 'mock/chosen', home_settings['model']
      end

      it 'raises the configuration error when home settings turn malformed while the host is asked' do
        host = ScriptedHost.new
        malformed = nil
        malform = -> { malformed = malform_settings(@home) }
        host.define_singleton_method(:ask) do |_question = nil, **|
          malform.call
          'mock/chosen'
        end
        refused = refusal { build(host: host) }

        assert_equal malformed, refused
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

      it 'builds the Runtime once the SDK gem is present' do
        assert_equal 'openai/o3', build(model: 'openai/o3', env: { 'OPENAI_API_KEY' => 'sk' }).model
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
      it 'hands the resolved values to the Runtime' do
        assert_equal(
          { gemini: { api_key: 'sk-gem-env' } },
          build(model: 'gemini/gem-2.5-pro', env: { 'GEMINI_API_KEY' => 'sk-gem-env' }).credentials
        )
      end

      it 'stores a key the host supplies in home auth.json' do
        build(model: 'gemini/gem-2.5-pro', env: {}, host: ScriptedHost.new('sk-gem-pasted'))

        assert_equal(
          'sk-gem-pasted',
          JSON.parse(File.read(File.join(@home, '.riffer', 'auth.json')))['gemini']['api_key']
        )
      end

      it 'stores a key typed at the terminal footer in home auth.json' do
        at_the_terminal_footer("sk-gem-typed\r") { |host| build(model: 'gemini/gem-2.5-pro', env: {}, host: host) }

        assert_equal(
          'sk-gem-typed',
          JSON.parse(File.read(File.join(@home, '.riffer', 'auth.json')))['gemini']['api_key']
        )
      end

      it 'raises the configuration error naming a key the null host cannot supply' do
        assert_match(
          /\Agemini has no api_key \(GEMINI_API_KEY\)/,
          refusal { build(model: 'gemini/gem-2.5-pro', env: {}) }
        )
      end
    end

    it 'loads the bundled tools' do
      assert_equal %w[read write edit bash bash_output bash_kill], tool_names(build(model: 'mock/test'))
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

    describe 'rig.rb files' do
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

      it 'loads a project rig.rb trusted at the terminal footer' do
        write_rig(:project, <<~RUBY)
          class FooterTrustedTool < Riffer::Tool
            identifier 'footer_trusted'
            description 'probe'
            def call(context:) = text('probe')
          end
          Riffer::Rig.extension('footer_trusted') { |rig| rig.tool FooterTrustedTool }
        RUBY
        runtime = at_the_terminal_footer("y\r") { |host| build(host: host, model: 'mock/test') }

        assert_includes tool_names(runtime), 'footer_trusted'
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

      it 'skips autoload with extensions: false' do
        write_settings(@home, { extensions: { autoload: true } })
        gem_file = fixture_gem_file
        runtime = nil
        with_gem_files([gem_file]) { runtime = build(model: 'mock/test', extensions: false) }

        refute_includes tool_names(runtime), 'fixture_probe'
      end
    end

    it 'loads extra extensions with the bundle' do
      extra = Riffer::Rig::Extension.new('extra_loader') { |rig| rig.command('ping', description: 'Pings') { |_ctx| nil } }
      runtime = build(model: 'mock/test', extra_extensions: [extra])

      assert(runtime.commands.any? { |command| command.name == 'ping' })
    end

    describe 'session store' do
      before { @store = RecordingStore.new }

      def entries
        @store.appended.map { |_id, entry| entry }
      end

      it 'records the model skill activations' do
        write_skill('a')
        runtime = build(store: @store, model: 'mock/test')
        runtime.agent.provider.stub_response('', tool_calls: [{ name: 'skill_activate', arguments: '{"name":"a"}' }])
        runtime.agent.provider.stub_response('Done.')
        runtime.ask('use skill a')

        assert_equal(['a'], entries.grep(Riffer::Rig::Stores::SkillEntry).map(&:skill))
      end

      it 'names the default-store file after the runtime id' do
        runtime = build(model: 'mock/test')
        turn(runtime)
        path = File.join(@home, '.riffer', 'sessions', '*', "#{runtime.id}.jsonl")

        refute_empty Dir.glob(path)
      end

      it 'writes nothing with store: nil' do
        runtime = build(store: nil, model: 'mock/test')
        turn(runtime)

        assert_empty Dir.glob(File.join(@home, '.riffer', 'sessions', '**', '*'))
      end

      it 'writes nothing when sessions.save is false' do
        FileUtils.mkdir_p(File.join(@home, '.riffer'))
        File.write(File.join(@home, '.riffer', 'settings.json'), JSON.generate({ sessions: { save: false } }))
        runtime = build(store: @store, model: 'mock/test')
        turn(runtime)

        assert_empty @store.appended
      end
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

    it 'hands the catalog files to the riffer config' do
      catalog = write_catalog(@home, version: 1, models: { 'mock/test' => { pricing: { input: 3.0, output: 15.0 } } })
      write_settings(@home, { catalog_files: [catalog] })
      build(model: 'mock/test')

      assert_in_delta 3.0, @config.catalog.rates_for('mock/test').input
    end

    it 'hands the reasoning level to the agent' do
      write_settings(@home, { reasoning: 'high' })

      assert_equal :high, build(model: 'mock/test').agent.config.reasoning
    end

    it 'hands the native tool switches to the Runtime' do
      write_settings(@home, { tools: { native: { web_search: true } } })

      assert_equal({ web_search: true }, build(model: 'mock/test').agent.config.model_options)
    end

    it 'installs the reload command' do
      assert_includes build(model: 'mock/test').commands.map(&:name), 'reload'
    end

    it 'installs /trace over the store it records to' do
      runtime = build(store: Riffer::Rig::Stores::JSONL.new(home: @home), model: 'mock/test')
      runtime.agent.provider.stub_response('Done.')
      runtime.ask('read them')
      events = []
      runtime.run_command('trace') { |event| events << event }

      assert_includes events.first.text, 'read them'
    end

    it 'installs no /trace with store: nil' do
      runtime = build(store: nil, model: 'mock/test')

      refute_includes runtime.commands.map(&:name), 'trace'
    end

    it 'installs no /trace when sessions.save is false' do
      write_settings(@home, { sessions: { save: false } })
      runtime = build(store: RecordingStore.new, model: 'mock/test')

      refute_includes runtime.commands.map(&:name), 'trace'
    end
  end

  describe '#continue' do
    it 'continues nothing with a nil store' do
      assert_nil loader(store: nil).continue
    end

    it 'continues nothing when no session matches the cwd' do
      save_entries('other', [header('other', cwd: '/other')])

      assert_nil loader.continue
    end

    it 'continues the most recently updated session' do
      first = save_session('first')
      second = save_session('second')
      age(session_path(first.id), 1000)

      assert_equal second.id, loader.continue.id
    end

    it 'continues the most recently updated even when list is unordered' do
      first = save_session('first')
      second = save_session('second')
      age(session_path(first.id), 1000)

      assert_equal second.id, loader(store: ReversedStore.new(Riffer::Rig::Stores::JSONL.new(home: @home))).continue.id
    end

    it 'continues with the session history' do
      save_session('welcome back')
      resumed = loader.continue
      contents = resumed.agent.session.messages.map(&:content)

      assert_equal ['welcome back', 'All done.'], contents
    end
  end

  describe '#resume' do
    it 'resumes nothing with a nil store' do
      assert_nil loader(store: nil).resume('aaa')
    end

    it 'returns nil for an unknown id' do
      assert_nil loader.resume('nope')
    end

    it 'resumes a session by id' do
      saved = save_session

      assert_equal saved.id, loader.resume(saved.id).id
    end

    it 'loads extra extensions into the resumed session' do
      saved = save_session
      extra = Riffer::Rig::Extension.new('extra_resume') { |rig| rig.command('ping', description: 'Pings') { |_ctx| nil } }
      resumed = loader.resume(saved.id, extra_extensions: [extra])

      assert(resumed.commands.any? { |command| command.name == 'ping' })
    end

    it 'rewrites no header when resuming' do
      saved = save_session
      resumed = loader.resume(saved.id)
      turn(resumed, 'again')

      types = File.readlines(session_path(saved.id)).map { |line| JSON.parse(line, symbolize_names: true)[:type] }

      assert_equal 1, types.count('header')
    end
  end

  describe '#messages' do
    it 'replays no messages with a nil store' do
      assert_empty loader(store: nil).messages('aaa')
    end

    it 'replays the messages of a session in recorded order' do
      saved = save_session('welcome back')
      contents = loader.messages(saved.id).map { |message| message[:content] }

      assert_equal ['welcome back', 'All done.'], contents
    end
  end

  describe '#list' do
    it 'lists nothing with a nil store' do
      assert_empty loader(store: nil).list
    end

    it 'lists the sessions of this cwd' do
      save_session

      assert_equal([@cwd], loader.list.map(&:cwd))
    end

    it 'escapes the cwd scope with all: true' do
      save_session
      save_entries('elsewhere', [header('elsewhere', cwd: '/elsewhere')])

      assert_equal ['/elsewhere', @cwd], loader.list(all: true).map(&:cwd).sort
    end
  end

  describe '#delete' do
    it 'deletes nothing with a nil store' do
      assert_nil loader(store: nil).delete('aaa')
    end

    it 'deletes a session' do
      saved = save_session
      loader.delete(saved.id)

      assert_nil session_path(saved.id)
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
      runtime = loader.runtime(Riffer::Rig::Loader::Options.new(model: 'mock/test'))
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
      runtime = loader.runtime(Riffer::Rig::Loader::Options.new(model: 'mock/test'))
      File.write(project_rig_path, 'raise "boom"')
      [loader, runtime, host]
    end

    def with_raising_credentials
      Riffer::Rig::Credentials.define_singleton_method(:resolve) { |*_args, **_kwargs| raise 'credential boom' }
      yield
    ensure
      Riffer::Rig::Credentials.singleton_class.remove_method(:resolve)
    end

    it 'skips the reload when no tracked file changed' do
      write_rig(:project, probe_rig('probe'))
      host = ConfirmingHost.new([true])
      loader = new_loader(host: host)
      runtime = loader.runtime(Riffer::Rig::Loader::Options.new(model: 'mock/test'))
      marker = File.join(@cwd, 'reload_marker')
      File.write(project_rig_path, "File.write(#{marker.inspect}, 'attempted')\nraise 'boom'")
      bump(project_rig_path)
      loader.reload(runtime)
      FileUtils.rm_f(marker)
      loader.reload(runtime)

      refute_path_exists marker
    end

    it 'tracks no files with extensions: false' do
      write_settings(@home, { git: { depth: 10 } })
      loader = new_loader
      runtime = loader.runtime(Riffer::Rig::Loader::Options.new(model: 'mock/test', extensions: false))
      write_settings(@home, { git: { depth: 3 } })
      write_rig(:project, probe_rig('probe'))
      loader.reload(runtime)

      assert_equal({ depth: 10 }, runtime.settings[:git])
    end

    it 'reloads without force when a tracked file changed' do
      loader, runtime, = tool_added
      bump(project_rig_path)
      loader.reload(runtime)

      assert_includes tool_names(runtime), 'probe_next'
    end

    it 're-reads settings changed on disk' do
      write_settings(@home, { git: { depth: 10 } })
      loader = new_loader
      runtime = loader.runtime(Riffer::Rig::Loader::Options.new(model: 'mock/test'))
      write_settings(@home, { git: { depth: 3 } })
      loader.reload(runtime, force: true)

      assert_equal({ depth: 3 }, runtime.settings[:git])
    end

    it 'reports settings malformed on disk' do
      loader = new_loader
      runtime = loader.runtime(Riffer::Rig::Loader::Options.new(model: 'mock/test'))
      malformed = malform_settings(@home)

      assert_equal malformed, loader.reload(runtime, force: true)
    end

    it 'holds an unforced reload under a manual reload keyword when settings are malformed' do
      write_rig(:project, probe_rig('probe'))
      loader = new_loader(host: ConfirmingHost.new([true]))
      runtime = loader.runtime(Riffer::Rig::Loader::Options.new(model: 'mock/test'), reload: :manual)
      malform_settings(@home)
      bump(project_rig_path)

      assert_same runtime, loader.reload(runtime)
    end

    it 'keeps extra extensions through a reload' do
      extra = Riffer::Rig::Extension.new('extra_loader') { |rig| rig.command('ping', description: 'Pings') { |_ctx| nil } }
      loader = new_loader
      runtime = loader.runtime(Riffer::Rig::Loader::Options.new(model: 'mock/test'), extra_extensions: [extra])
      loader.reload(runtime, force: true)

      assert(runtime.commands.any? { |command| command.name == 'ping' })
    end

    it 'skips rediscovery with extensions: false' do
      loader = new_loader(host: ConfirmingHost.new([true]))
      runtime = loader.runtime(Riffer::Rig::Loader::Options.new(model: 'mock/test', extensions: false))
      write_rig(:project, probe_rig('probe'))
      loader.reload(runtime, force: true)

      assert_empty tool_names(runtime).grep(/\Aprobe/)
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

    it 'keeps recording skill activations after a reload' do
      write_skill('a')
      store = RecordingStore.new
      loader = loader(store: store)
      runtime = loader.runtime(Riffer::Rig::Loader::Options.new(model: 'mock/test'))
      loader.reload(runtime, force: true)
      runtime.agent.provider.stub_response('', tool_calls: [{ name: 'skill_activate', arguments: '{"name":"a"}' }])
      runtime.agent.provider.stub_response('Done.')
      runtime.ask('use skill a')

      assert_equal(['a'], store.appended.map(&:last).grep(Riffer::Rig::Stores::SkillEntry).map(&:skill))
    end

    it 'reports credentials the reload cannot resolve' do
      loader = new_loader
      runtime = loader.runtime(Riffer::Rig::Loader::Options.new(model: 'mock/test'))
      runtime.model = 'gemini/gem-2.5-pro'

      assert_match(/\Agemini has no api_key \(GEMINI_API_KEY\)/, loader.reload(runtime, force: true))
    end

    it 'registers a tool added to a tracked file' do
      loader, runtime, = tool_added
      loader.reload(runtime, force: true)

      assert_includes tool_names(runtime), 'probe_next'
    end

    it 'reports the rebuilt runtime' do
      loader, runtime, = tool_added
      reloaded = loader.reload(runtime, force: true)

      assert_same runtime, reloaded
    end

    it 'reports a raise during the reload instead of propagating it' do
      write_rig(:project, probe_rig('probe'))
      loader = new_loader(host: ConfirmingHost.new([true]))
      runtime = loader.runtime(Riffer::Rig::Loader::Options.new(model: 'mock/test'))
      File.write(project_rig_path, probe_rig('probe_next'))
      with_raising_credentials do
        reloaded = loader.reload(runtime, force: true)

        assert_match(/credential boom\z/, reloaded)
      end
    end

    it 'advances the snapshot when a reload raises' do
      write_rig(:project, probe_rig('probe'))
      loader = new_loader(host: ConfirmingHost.new([true]))
      runtime = loader.runtime(Riffer::Rig::Loader::Options.new(model: 'mock/test'))
      marker = File.join(@cwd, 'reload_marker')
      File.write(project_rig_path, probe_rig('probe_next') + "File.write(#{marker.inspect}, 'executed')\n")
      with_raising_credentials { loader.reload(runtime, force: true) }
      FileUtils.rm_f(marker)
      loader.reload(runtime)

      refute_path_exists marker
    end
  end

  describe 'automatic reload' do
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

    def built_with(host, **keywords)
      write_rig(:project, probe_rig('probe'))
      loader = new_loader(host: host)
      runtime = loader.runtime(Riffer::Rig::Loader::Options.new(model: 'mock/test'), **keywords)
      [loader, runtime]
    end

    it 'reloads a tracked file changed before a turn' do
      _loader, runtime = built_with(ConfirmingHost.new([true]))
      File.write(project_rig_path, probe_rig('probe_next'))
      turn(runtime)

      assert_includes tool_names(runtime), 'probe_next'
    end

    it 'does not retry a failed reload on the next request' do
      _loader, runtime = built_with(ConfirmingHost.new([true]))
      File.write(project_rig_path, "raise 'boom'")
      stamp = File.mtime(project_rig_path)
      turn(runtime)
      File.write(project_rig_path, probe_rig('probe_next'))
      File.utime(stamp, stamp, project_rig_path)
      turn(runtime)

      assert_empty tool_names(runtime).grep(/\Aprobe_next/)
    end

    it 'skips the check under a manual reload keyword' do
      _loader, runtime = built_with(ConfirmingHost.new([true]), reload: :manual)
      File.write(project_rig_path, probe_rig('probe_next'))
      turn(runtime)

      assert_empty tool_names(runtime).grep(/\Aprobe_next/)
    end

    it 'keeps /reload under a manual reload keyword' do
      _loader, runtime = built_with(ConfirmingHost.new([true]), reload: :manual)
      File.write(project_rig_path, probe_rig('probe_next'))
      runtime.run_command('reload')

      assert_includes tool_names(runtime), 'probe_next'
    end

    it 'skips the check when the setting says manual' do
      write_settings(@home, { reload: 'manual' })
      _loader, runtime = built_with(ConfirmingHost.new([true]))
      File.write(project_rig_path, probe_rig('probe_next'))
      turn(runtime)

      assert_empty tool_names(runtime).grep(/\Aprobe_next/)
    end

    it 'lets the project setting override home' do
      write_settings(@home, { reload: 'manual' })
      write_settings(@cwd, { reload: 'auto' })
      _loader, runtime = built_with(ConfirmingHost.new([true]))
      File.write(project_rig_path, probe_rig('probe_next'))
      turn(runtime)

      assert_includes tool_names(runtime), 'probe_next'
    end

    it 'lets the keyword override the setting' do
      write_settings(@home, { reload: 'manual' })
      _loader, runtime = built_with(ConfirmingHost.new([true]), reload: :auto)
      File.write(project_rig_path, probe_rig('probe_next'))
      turn(runtime)

      assert_includes tool_names(runtime), 'probe_next'
    end

    it 'stops reloading when the setting flips to manual mid-session' do
      _loader, runtime = built_with(ConfirmingHost.new([true]))
      write_settings(@home, { reload: 'manual' })
      File.write(project_rig_path, probe_rig('probe_next'))
      turn(runtime)

      assert_empty tool_names(runtime).grep(/\Aprobe_next/)
    end

    it 'reports settings that turn malformed mid-session' do
      host = ConfirmingHost.new([true])
      _loader, runtime = built_with(host)
      malformed = malform_settings(@home)
      File.write(project_rig_path, probe_rig('probe_next'))
      turn(runtime)

      assert_equal [[:error, malformed]], host.notifications
    end
  end
end
