# frozen_string_literal: true

require 'test_helper'
require_relative '../../fixtures/mcp_https_server'

describe Riffer::Rig::Runtime do
  before do
    @extension = Riffer::Rig.extension('test_runtime_tools') do |rig|
      rig.tool Riffer::Rig::Tools::Read
      rig.tool Riffer::Rig::Tools::Write
      rig.tool Riffer::Rig::Tools::Edit
      rig.tool Riffer::Rig::Tools::Bash
    end
  end

  after do
    Riffer::Rig.instance_variable_get(:@extensions).delete('test_runtime_tools')
    FileUtils.remove_entry(@skills_dir) if @skills_dir
  end

  def write_skill(root, name)
    FileUtils.mkdir_p(File.join(root, name))
    File.write(File.join(root, name, 'SKILL.md'), "---\nname: #{name}\ndescription: #{name}.\n---\nDo #{name}.\n")
  end

  def skills_dir
    @skills_dir ||= Dir.mktmpdir.tap { |dir| write_skill(dir, 'a') }
  end

  def skills_extension
    dir = skills_dir
    Riffer::Rig::Extension.new('local_skills') do |rig|
      rig.skills { |_runtime| Riffer::Skills::FilesystemBackend.new(dir) }
    end
  end

  def skilled_runtime(**)
    Riffer::Rig::Runtime.new('mock/test', extensions: [skills_extension], **)
  end

  def recording_mcp_registry
    Class.new do
      attr_reader :registered

      def initialize
        @registered = []
      end

      def register(name:, **)
        @registered << name
        Class.new { define_method(:retired?) { false } }.new
      end

      def unregister(name)
        @registered.delete(name)
      end
    end.new
  end

  def serving_mcp(*names)
    Riffer::Rig::Extension.new('serving') { |rig| names.each { |name| rig.mcp(name, url: "https://#{name}.test/mcp") } }
  end

  def spawn_group_job(runtime, command = 'sleep 30')
    jobs = runtime.agent.context[:jobs] #: Riffer::Rig::Tools::Bash::Jobs
    jobs.register(Process.spawn(command, pgroup: true), command, File.open(File::NULL))
  end

  def job_exits(runtime)
    Queue.new.tap { |exits| runtime.on_job_exit { |completion| exits << completion } }
  end

  def usage(input, output)
    Riffer::Providers::TokenUsage.new(input_tokens: input, output_tokens: output)
  end

  it 'mints a uuid_v7 id at construction' do
    runtime = Riffer::Rig::Runtime.new('mock/test', extensions: [@extension])

    assert_match(/\A[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[0-9a-f]{4}-[0-9a-f]{12}\z/, runtime.id)
  end

  it 'gives each runtime its own id' do
    one = Riffer::Rig::Runtime.new('mock/test', extensions: [@extension])
    two = Riffer::Rig::Runtime.new('mock/test', extensions: [@extension])

    refute_equal one.id, two.id
  end

  it 'wraps the given host' do
    host = Class.new(Riffer::Rig::Hosts::Null) { define_method(:capabilities) { Set[:notify].freeze } }.new
    runtime = Riffer::Rig::Runtime.new('mock/test', extensions: [@extension], host: host)

    assert_equal Set[:notify], runtime.host.capabilities
  end

  it 'defaults the cwd to the process working directory' do
    assert_equal Dir.pwd, Riffer::Rig::Runtime.new('mock/test').cwd
  end

  it 'stores credentials as given' do
    credentials = { anthropic: { api_key: 'sk-ant-test' } }
    runtime = Riffer::Rig::Runtime.new('mock/test', extensions: [@extension], credentials: credentials)

    assert_same credentials, runtime.credentials
  end

  it 'hands its model options to the agent' do
    runtime = Riffer::Rig::Runtime.new('mock/test', model_options: { reasoning: 'high' })

    assert_equal({ reasoning: 'high' }, runtime.agent.config.model_options)
  end

  it 'hands the reasoning level to the agent' do
    runtime = Riffer::Rig::Runtime.new('mock/test', reasoning: 'high')

    assert_equal :high, runtime.agent.config.reasoning
  end

  it 'hands off to the agent as a level of its own' do
    runtime = Riffer::Rig::Runtime.new('mock/test', reasoning: 'off')

    assert_equal :off, runtime.agent.config.reasoning
  end

  it 'sends its model options with each request' do
    runtime = Riffer::Rig::Runtime.new('mock/test', model_options: { reasoning: 'high' })
    runtime.agent.provider.stub_response('All done.')
    runtime.ask('hello')

    assert_equal 'high', runtime.agent.provider.calls.last[:reasoning]
  end

  it 'enables the provider option of a native tool the provider supports' do
    runtime = Riffer::Rig::Runtime.new('mock/test', native_tools: { web_search: true })

    assert_equal({ web_search: true }, runtime.agent.config.model_options)
  end

  it 'passes a switch object through as the option value' do
    runtime = Riffer::Rig::Runtime.new('mock/test', native_tools: { web_search: { max_uses: 3 } })

    assert_equal({ web_search: { max_uses: 3 } }, runtime.agent.config.model_options)
  end

  it 'carries the provider option on the request' do
    runtime = Riffer::Rig::Runtime.new('mock/test', native_tools: { web_search: true })
    runtime.agent.provider.stub_response('All done.')
    events = []
    runtime.prompt('search') { |event| events << event }

    assert(events.any?(Riffer::StreamEvents::WebSearchDone))
  end

  it 'drops the switch of a native tool the provider does not support' do
    runtime = Riffer::Rig::Runtime.new('gemini/gem-2.5-pro', native_tools: { web_search: true })

    assert_equal({}, runtime.agent.config.model_options)
  end

  it 'drops the switch of a native tool it does not know' do
    runtime = Riffer::Rig::Runtime.new('mock/test', native_tools: { code_interpreter: true })

    assert_equal({}, runtime.agent.config.model_options)
  end

  it 'adds no provider options without a switch' do
    runtime = Riffer::Rig::Runtime.new('mock/test')

    assert_equal({}, runtime.agent.config.model_options)
  end

  it 'names the agent in the base prompt' do
    runtime = Riffer::Rig::Runtime.new('mock/test', extensions: [@extension])

    assert_includes runtime.agent.instruction_message.content, 'You are riffer, a general-purpose agent.'
  end

  it 'swaps the name inside the base prompt' do
    runtime = Riffer::Rig::Runtime.new('mock/test', extensions: [@extension], name: 'sidekick')

    assert_includes runtime.agent.instruction_message.content, 'You are sidekick, a general-purpose agent.'
  end

  it 'replaces the base prompt with instructions' do
    runtime = Riffer::Rig::Runtime.new('mock/test', extensions: [@extension], instructions: 'CUSTOM_BASE')

    assert_includes runtime.agent.instruction_message.content, 'CUSTOM_BASE'
  end

  it 'drops the default base under custom instructions' do
    runtime = Riffer::Rig::Runtime.new('mock/test', extensions: [@extension], instructions: 'CUSTOM_BASE')

    refute_includes runtime.agent.instruction_message.content, 'general-purpose agent'
  end

  describe 'extension load errors' do
    before do
      @first = Riffer::Rig::Extension.new('first') { |rig| rig.tool Riffer::Rig::Tools::Read }
      @broken = Riffer::Rig::Extension.new('broken') do |rig|
        rig.tool Riffer::Rig::Tools::Write
        raise 'kaboom'
      end
      @last = Riffer::Rig::Extension.new('last') { |rig| rig.tool Riffer::Rig::Tools::Bash }
      @runtime = Riffer::Rig::Runtime.new('mock/test', extensions: [@first, @broken, @last])
    end

    it 'registers the extensions around a raising one' do
      assert_equal [Riffer::Rig::Tools::Read, Riffer::Rig::Tools::Bash], @runtime.agent.tools
    end

    it 'records the raising extension on errors' do
      assert_equal([[@broken, 'kaboom']], @runtime.errors.map { |failure| [failure.extension, failure.error.message] })
    end

    it 'reports the failure with one notify at error level' do
      @runtime.agent.provider.stub_response('All done.')

      assert_equal [Riffer::Rig::Events::Notify.new('Extension broken failed to load: kaboom', :error)],
                   @runtime.prompt('hello').grep(Riffer::Rig::Events::Notify)
    end

    it 'keeps the error out of the model context' do
      @runtime.agent.provider.stub_response('All done.')
      @runtime.ask('hello')

      refute_includes @runtime.agent.provider.calls.last[:messages].to_s, 'kaboom'
    end

    it 'records no errors when every extension loads' do
      assert_empty Riffer::Rig::Runtime.new('mock/test', extensions: [@first, @last]).errors
    end
  end

  describe 'MCP servers' do
    before do
      @server = McpHttpsServer.new
      @ssl_cert_file = ENV.fetch('SSL_CERT_FILE', nil)
      ENV['SSL_CERT_FILE'] = @server.ca_file
      @runtimes = []
    end

    after do
      @runtimes.each(&:close)
      ENV['SSL_CERT_FILE'] = @ssl_cert_file
      @server.stop
    end

    def serving(name = 'web', url: @server.url, **)
      Riffer::Rig::Extension.new("serves_#{name}") { |rig| rig.mcp(name, url: url, **) }
    end

    def runtime(extensions, **)
      Riffer::Rig::Runtime.new('mock/test', extensions: extensions, **).tap { |built| @runtimes << built }
    end

    def tool_names(runtime)
      runtime.agent.tools.map(&:name)
    end

    def notifies(runtime)
      runtime.agent.provider.stub_response('Done.')
      runtime.prompt('go').grep(Riffer::Rig::Events::Notify)
    end

    it 'resolves the auth block of a server from its env' do
      authed = serving(headers: { 'X-Token' => 'Bearer ${api_key}' }, auth: { api_key: 'KAGI_API_KEY' })
      tools = runtime([authed], env: Riffer::Rig::Env.new({ 'KAGI_API_KEY' => 'kagi-key' })).agent.tools

      assert_equal 'Bearer kagi-key', tools.find { |klass| klass.name == 'web__token' }.new.call(context: nil).content
    end

    it 'adds each server tool under riffer MCP naming' do
      assert_equal %w[web__echo web__token], tool_names(runtime([serving]))
    end

    it 'adds the server tools after the extension tools' do
      assert_equal %w[read web__echo web__token], tool_names(runtime([@extension, serving], tools: %w[read]))
    end

    it 'does not filter the server tools by the tools: allowlist' do
      assert_equal %w[web__echo web__token], tool_names(runtime([serving], tools: %w[web__echo]))
    end

    it 'reports a server tool in the tools: allowlist as unknown' do
      notice = Riffer::Rig::Events::Notify.new('Unknown tool in allowlist: web__echo', :warning)

      assert_equal [notice], notifies(runtime([serving], tools: %w[web__echo]))
    end

    it 'runs a server tool the model calls' do
      built = runtime([serving])
      built.agent.provider.stub_response('', tool_calls: [{ name: 'web__echo', arguments: '{"text":"hi"}' }])
      built.agent.provider.stub_response('Echoed.')

      assert_equal 'hi', built.ask('echo hi').messages.grep(Riffer::Messages::Tool).first.content
    end

    it "keeps one Runtime's servers from another Runtime's agent" do
      runtime([serving])

      assert_equal %w[alt__echo alt__token], tool_names(runtime([serving('alt', url: @server.url('alt'))]))
    end

    it 'reports a replaced server through notify at info level' do
      later = Riffer::Rig::Extension.new('later') { |rig| rig.mcp('web', url: @server.url) }
      notice = 'Extension later replaces MCP server web from serves_web'

      assert_equal [Riffer::Rig::Events::Notify.new(notice, :info)], notifies(runtime([serving, later]))
    end
  end

  it 'registers the bundled tool classes through an extension' do
    runtime = Riffer::Rig::Runtime.new('mock/test', extensions: [@extension])

    assert_equal [Riffer::Rig::Tools::Read, Riffer::Rig::Tools::Write, Riffer::Rig::Tools::Edit, Riffer::Rig::Tools::Bash],
                 runtime.agent.tools
  end

  it 'gives a second runtime its own tools' do
    other = Riffer::Rig.extension('test_runtime_other') { |rig| rig.tool Riffer::Rig::Tools::Read }
    Riffer::Rig::Runtime.new('mock/test', extensions: [@extension])
    two = Riffer::Rig::Runtime.new('mock/test', extensions: [other])

    assert_equal [Riffer::Rig::Tools::Read], two.agent.tools
  end

  it 'keeps the process registry shared between runtimes' do
    other = Riffer::Rig.extension('test_runtime_other') { |rig| rig.tool Riffer::Rig::Tools::Read }
    one = Riffer::Rig::Runtime.new('mock/test', extensions: [@extension])
    Riffer::Rig::Runtime.new('mock/test', extensions: [other])

    assert_equal 4, one.agent.tools.length
  end

  it 'filters the registered tools by the allowlist' do
    runtime = Riffer::Rig::Runtime.new('mock/test', extensions: [@extension], tools: %w[read bash])

    assert_equal [Riffer::Rig::Tools::Read, Riffer::Rig::Tools::Bash], runtime.agent.tools
  end

  it 'defaults to an unlimited agent loop' do
    runtime = Riffer::Rig::Runtime.new('mock/test', extensions: [@extension])

    assert_nil runtime.agent.config.max_steps
  end

  it 'forwards max_steps to the agent' do
    runtime = Riffer::Rig::Runtime.new('mock/test', extensions: [@extension], max_steps: 3)

    assert_equal 3, runtime.agent.config.max_steps
  end

  describe 'skills' do
    it 'has no skills context without a skills source' do
      assert_nil Riffer::Rig::Runtime.new('mock/test', extensions: []).agent.context.skills
    end

    it 'passes the Runtime to a skills source' do
      seen = nil
      spy = Riffer::Rig::Extension.new('spy') do |rig|
        rig.skills do |runtime|
          seen = runtime
          Riffer::Skills::FilesystemBackend.new(skills_dir)
        end
      end
      runtime = Riffer::Rig::Runtime.new('mock/test', extensions: [spy])

      assert_same runtime, seen
    end

    it 'merges the skills of every source into the catalog' do
      other = Dir.mktmpdir
      write_skill(other, 'b')
      more = Riffer::Rig::Extension.new('more') { |rig| rig.skills { |_runtime| Riffer::Skills::FilesystemBackend.new(other) } }
      runtime = Riffer::Rig::Runtime.new('mock/test', extensions: [skills_extension, more])

      assert_equal %w[a b], runtime.agent.context.skills.skills.keys
    ensure
      FileUtils.remove_entry(other)
    end

    it 'lists no skill commands when the sources hold no skills' do
      FileUtils.remove_entry(File.join(skills_dir, 'a'))

      assert_equal %w[auth model reasoning cost], skilled_runtime.commands.map(&:name)
    end

    it 're-activates a snapshot skill by name on restore' do
      runtime = skilled_runtime
      runtime.agent.context.skills.activate('a')

      assert skilled_runtime(snapshot: runtime.to_h).agent.context.skills.activated?('a')
    end

    it 'drops a snapshot skill that no longer exists' do
      snapshot = skilled_runtime.to_h.merge(skills: %w[a gone])

      assert_equal %w[a], skilled_runtime(snapshot: snapshot).to_h[:skills]
    end

    it 'lets a later extension replace a skill command by name' do
      mine = Riffer::Rig::Extension.new('mine') { |rig| rig.command('skill:a', description: 'Mine') { |_ctx| nil } }
      runtime = Riffer::Rig::Runtime.new('mock/test', extensions: [skills_extension, mine])

      assert_equal 'Mine', runtime.commands.find { |command| command.name == 'skill:a' }.description
    end
  end

  describe 'bundled extensions' do
    def read_in(dir)
      runtime = Riffer::Rig::Runtime.new('mock/test', extensions: [Riffer::Rig.bundled(:read)], cwd: dir)
      runtime.agent.provider.stub_response('', tool_calls: [{ name: 'read', arguments: '{"path":"note.txt"}' }])
      runtime.agent.provider.stub_response('Done.')
      runtime.ask('read note.txt').messages.find { |message| message.is_a?(Riffer::Messages::Tool) }.content
    end

    def replaced_bash
      Class.new(Riffer::Tool) do
        identifier 'bash'
        description 'A sandboxed shell'
      end
    end

    it 'reads the same relative path from each runtime cwd' do
      Dir.mktmpdir do |one|
        Dir.mktmpdir do |two|
          File.write(File.join(one, 'note.txt'), 'from one')
          File.write(File.join(two, 'note.txt'), 'from two')

          assert_equal ["     1\tfrom one", "     1\tfrom two"], [read_in(one), read_in(two)]
        end
      end
    end

    it 'lets a later extension replace a bundled tool by identifier' do
      sandbox = replaced_bash
      replacement = Riffer::Rig::Extension.new('sandbox') { |rig| rig.tool sandbox }
      tools = %i[read write edit bash].map { |name| Riffer::Rig.bundled(name) }
      runtime = Riffer::Rig::Runtime.new('mock/test', extensions: [*tools, replacement])

      assert_equal(
        [
          Riffer::Rig::Tools::Read,
          Riffer::Rig::Tools::Write,
          Riffer::Rig::Tools::Edit,
          sandbox,
          Riffer::Rig::Tools::Bash::Output,
          Riffer::Rig::Tools::Bash::Kill
        ],
        runtime.agent.tools
      )
    end

    it 'reports the replaced tool through notify at info level' do
      sandbox = replaced_bash
      replacement = Riffer::Rig::Extension.new('sandbox') { |rig| rig.tool sandbox }
      runtime = Riffer::Rig::Runtime.new('mock/test', extensions: [Riffer::Rig.bundled(:bash), replacement])

      assert_equal [Riffer::Rig::Events::Notify.new('Extension sandbox replaces tool bash from bash', :info)],
                   runtime.host.drain
    end

    it 'reports a replaced command through notify' do
      earlier = Riffer::Rig::Extension.new('earlier') { |rig| rig.command('log', description: 'a') { |_ctx| nil } }
      later = Riffer::Rig::Extension.new('later') { |rig| rig.command('log', description: 'b') { |_ctx| nil } }
      runtime = Riffer::Rig::Runtime.new('mock/test', extensions: [earlier, later])

      assert_equal [Riffer::Rig::Events::Notify.new('Extension later replaces command log from earlier', :info)],
                   runtime.host.drain
    end

    it 'reports a replaced prompt section through notify' do
      earlier = Riffer::Rig::Extension.new('earlier') { |rig| rig.prompt(:branch) { 'a' } }
      later = Riffer::Rig::Extension.new('later') { |rig| rig.prompt(:branch) { 'b' } }
      runtime = Riffer::Rig::Runtime.new('mock/test', extensions: [earlier, later])

      notice = Riffer::Rig::Events::Notify.new('Extension later replaces prompt section branch from earlier', :info)

      assert_equal [notice], runtime.host.drain
    end

    it 'notifies nothing when no registration is replaced' do
      runtime = Riffer::Rig::Runtime.new('mock/test', extensions: Riffer::Rig.bundled)

      assert_empty runtime.host.drain
    end
  end

  it 'notifies nothing about the allowlist without one' do
    runtime = Riffer::Rig::Runtime.new('mock/test', extensions: [@extension])

    assert_empty runtime.host.drain
  end

  it 'notifies nothing when every allowlisted name is a registered tool' do
    runtime = Riffer::Rig::Runtime.new('mock/test', extensions: [@extension], tools: %w[read bash])

    assert_empty runtime.host.drain
  end

  it 'reports each allowlisted name no extension registered through notify at warning level' do
    runtime = Riffer::Rig::Runtime.new('mock/test', extensions: [@extension], tools: %w[raed bash nope])

    assert_equal [Riffer::Rig::Events::Notify.new('Unknown tool in allowlist: raed', :warning),
                  Riffer::Rig::Events::Notify.new('Unknown tool in allowlist: nope', :warning)],
                 runtime.host.drain
  end

  describe 'declared settings' do
    before do
      @git = Riffer::Rig::Extension.new('git') do |rig|
        rig.setting :depth, default: 3
        rig.setting :remote, default: 'origin'
        rig.command('show', description: 'Show the settings') { |ctx| ctx.say(ctx.settings.inspect) }
      end
    end

    def settings_output(runtime)
      events = []
      runtime.run_command('show') { |event| events << event }
      events.first.text
    end

    it 'applies a declared default when the settings lack the key' do
      runtime = Riffer::Rig::Runtime.new('mock/test', extensions: [@git])

      assert_equal({ depth: 3, remote: 'origin' }.inspect, settings_output(runtime))
    end

    it 'lets a provided value override the declared default' do
      runtime = Riffer::Rig::Runtime.new('mock/test', extensions: [@git], settings: { git: { depth: 10 } })

      assert_equal({ depth: 10, remote: 'origin' }.inspect, settings_output(runtime))
    end

    it 'shows a command only its own namespace' do
      runtime = Riffer::Rig::Runtime.new(
        'mock/test', extensions: [@git], settings: { model: 'mock/other', other: { depth: 1 } }
      )

      assert_equal({ depth: 3, remote: 'origin' }.inspect, settings_output(runtime))
    end

    it 'exposes the merged settings with declared defaults filled in' do
      runtime = Riffer::Rig::Runtime.new(
        'mock/test', extensions: [@git], settings: { model: 'mock/other', git: { depth: 10 } }
      )

      assert_equal({ model: 'mock/other', git: { depth: 10, remote: 'origin' } }, runtime.settings)
    end

    it 'exposes a table of declared keys per extension' do
      bare = Riffer::Rig::Extension.new('bare') { |rig| rig.tool Riffer::Rig::Tools::Read }
      runtime = Riffer::Rig::Runtime.new('mock/test', extensions: [@git, bare])

      assert_equal({ git: { depth: 3, remote: 'origin' } }, runtime.declared_settings)
    end
  end

  it 'renders no prompt sections when it is given no extensions' do
    Dir.mktmpdir do |cwd|
      File.write(File.join(cwd, 'AGENTS.md'), 'PROJECT_RULES')
      runtime = Riffer::Rig::Runtime.new('mock/test', instructions: 'CUSTOM_BASE', cwd: cwd)
      runtime.agent.provider.stub_response('All done.')
      runtime.ask('hello')

      assert_equal "CUSTOM_BASE\n\nCurrent date: #{Date.today}\nCurrent working directory: #{cwd}",
                   runtime.agent.provider.calls.last[:messages].first[:content]
    end
  end

  it 'lets a later registration of the same section name win' do
    earlier = Riffer::Rig::Extension.new('earlier') { |rig| rig.prompt(:branch) { 'EARLIER' } }
    later = Riffer::Rig::Extension.new('later') { |rig| rig.prompt(:branch) { 'LATER' } }
    runtime = Riffer::Rig::Runtime.new('mock/test', extensions: [earlier, later])
    runtime.agent.provider.stub_response('All done.')
    runtime.ask('hello')

    refute_includes runtime.agent.provider.calls.last[:messages].first[:content], 'EARLIER'
  end

  it 'keeps the later registration of the same section name' do
    earlier = Riffer::Rig::Extension.new('earlier') { |rig| rig.prompt(:branch) { 'EARLIER' } }
    later = Riffer::Rig::Extension.new('later') { |rig| rig.prompt(:branch) { 'LATER' } }
    runtime = Riffer::Rig::Runtime.new('mock/test', extensions: [earlier, later])
    runtime.agent.provider.stub_response('All done.')
    runtime.ask('hello')

    assert_includes runtime.agent.provider.calls.last[:messages].first[:content], 'LATER'
  end

  it 'passes the runtime to a section' do
    sections = Riffer::Rig::Extension.new('sections') { |rig| rig.prompt(:cwd) { |ctx| "In #{ctx.cwd}" } }
    runtime = Riffer::Rig::Runtime.new('mock/test', extensions: [sections], cwd: '/tmp/proj')
    runtime.agent.provider.stub_response('All done.')
    runtime.ask('hello')

    assert_includes runtime.agent.provider.calls.last[:messages].first[:content], 'In /tmp/proj'
  end

  it 'closes a runtime and refuses further prompts' do
    runtime = Riffer::Rig::Runtime.new('mock/test', extensions: [@extension])
    runtime.close

    assert_raises(Riffer::Rig::Runtime::ClosedError) { runtime.prompt('hello') }
  end

  it 'raises on a second prompt while one runs' do
    runtime = Riffer::Rig::Runtime.new('mock/test', extensions: [@extension])
    runtime.agent.provider.stub_response('first')

    assert_raises(Riffer::Rig::Runtime::BusyError) do
      runtime.prompt('hello') do
        runtime.prompt('second').each { |event| event }
      end
    end
  end

  it 'prompts with a block, yielding riffer stream events' do
    runtime = Riffer::Rig::Runtime.new('mock/test', extensions: [@extension])
    runtime.agent.provider.stub_response('All done.')
    events = []
    runtime.prompt('hello') { |event| events << event }

    assert(events.any?(Riffer::StreamEvents::TextDone))
  end

  it 'keeps ask and prompt from colliding' do
    runtime = Riffer::Rig::Runtime.new('mock/test', extensions: [@extension])
    runtime.agent.provider.stub_response('All done.')

    assert_nil runtime.prompt('hello') { |event| event }
  end

  it 'prompts without a block, returning an enumerator' do
    runtime = Riffer::Rig::Runtime.new('mock/test', extensions: [@extension])
    runtime.agent.provider.stub_response('All done.')

    assert_instance_of Enumerator, runtime.prompt('hello')
  end

  it 'is usable again after a turn ends' do
    runtime = Riffer::Rig::Runtime.new('mock/test', extensions: [@extension])
    runtime.agent.provider.stub_response('first')
    runtime.agent.provider.stub_response('second')
    runtime.prompt('hello').each { |event| event }

    assert_equal 'second', runtime.prompt('hello').find { |event| event.is_a?(Riffer::StreamEvents::TextDone) }.content
  end

  it 'opens every prompt with a session_start' do
    runtime = Riffer::Rig::Runtime.new('mock/test', extensions: [@extension])
    runtime.agent.provider.stub_response('All done.')

    first = runtime.prompt('hello').first

    assert_equal(Riffer::Rig::Events::SessionStart.new(runtime.id, :new), first)
  end

  it 'emits session_start once, not on every prompt' do
    runtime = Riffer::Rig::Runtime.new('mock/test', extensions: [@extension])
    runtime.agent.provider.stub_response('first')
    runtime.agent.provider.stub_response('second')
    runtime.prompt('hello').each { |event| event }
    second = runtime.prompt('hello').first

    refute_instance_of Riffer::Rig::Events::SessionStart, second
  end

  it 'mirrors host.notify as a notify event on the stream' do
    runtime = Riffer::Rig::Runtime.new('mock/test', extensions: [@extension])
    runtime.agent.provider.stub_response('All done.')

    notify_events = []
    runtime.host.notify('boom', level: :error)
    runtime.prompt('hello') { |event| notify_events << event if event.is_a?(Riffer::Rig::Events::Notify) }

    assert_equal [Riffer::Rig::Events::Notify.new('boom', :error)], notify_events
  end

  it 're-evaluates a section every turn without a rebuild' do
    branch = 'main'
    sections = Riffer::Rig::Extension.new('sections') { |rig| rig.prompt(:branch) { "Branch: #{branch}" } }
    runtime = Riffer::Rig::Runtime.new('mock/test', extensions: [sections])
    runtime.agent.provider.stub_response('One.')
    runtime.agent.provider.stub_response('Two.')
    runtime.ask('hello')
    branch = 'feature'
    runtime.prompt('again') { |event| event }

    assert_includes runtime.agent.provider.calls.last[:messages].first[:content], 'Branch: feature'
  end

  it 'closes every prompt with a turn_end' do
    usage = Riffer::Providers::TokenUsage.new(input_tokens: 10, output_tokens: 5)
    runtime = Riffer::Rig::Runtime.new('mock/test', extensions: [@extension])
    runtime.agent.provider.stub_response('All done.', token_usage: usage)

    last = nil
    runtime.prompt('hello') { |event| last = event }

    assert_equal(Riffer::Rig::Events::TurnEnd.new(:completed, usage), last)
  end

  it 'reports a max_steps run in turn_end' do
    runtime = Riffer::Rig::Runtime.new('mock/test', extensions: [@extension], tools: %w[read], max_steps: 1)
    runtime.agent.provider.stub_response('', tool_calls: [{ name: 'read', arguments: '{"path":"/tmp/x"}' }])
    runtime.agent.provider.stub_response('second response')

    last = nil
    runtime.prompt('go') { |event| last = event }

    assert_equal :max_steps, last.stop_reason
  end

  describe 'hooks' do
    before do
      echo = Class.new(Riffer::Tool) do
        identifier 'echo'
        description 'Echoes its text'

        params do
          required :text, String
        end

        define_method(:call) { |context:, text:| text("echo: #{text}") } # rubocop:disable Lint/UnusedBlockArgument -- riffer passes context: to every call
      end
      @echo = Riffer::Rig::Extension.new('echo') { |rig| rig.tool echo }
    end

    def runtime_with(&)
      Riffer::Rig::Runtime.new('mock/test', extensions: [@echo, Riffer::Rig::Extension.new('hooks', &)])
    end

    def stub_tool_turn(runtime, text = 'hi')
      runtime.agent.provider.stub_response('', tool_calls: [{ name: 'echo', arguments: { text: text }.to_json }])
      runtime.agent.provider.stub_response('All done.')
    end

    it 'fires session_start with the new reason' do
      events = []
      runtime = runtime_with { |rig| rig.on(:session_start) { |e| events << e } }
      runtime.agent.provider.stub_response('All done.')
      runtime.ask('go')

      assert_equal [Riffer::Rig::Events::SessionStart.new(runtime.id, :new)], events
    end

    it 'fires session_start once across turns' do
      count = 0
      runtime = runtime_with { |rig| rig.on(:session_start) { |_e| count += 1 } }
      runtime.agent.provider.stub_response('One.')
      runtime.agent.provider.stub_response('Two.')
      runtime.ask('go')
      runtime.ask('again')

      assert_equal 1, count
    end

    it 'sends a replacement prompt to the model' do
      runtime = runtime_with { |rig| rig.on(:before_prompt) { |e| "#{e.text} (be brief)" } }
      runtime.agent.provider.stub_response('All done.')
      runtime.ask('go')

      assert_equal 'go (be brief)', runtime.agent.provider.calls.last[:messages].last[:content]
    end

    it 'never calls the model for a blocked prompt' do
      runtime = runtime_with { |rig| rig.on(:before_prompt) { |_e| next :block, 'not now' } }
      runtime.ask('go')

      assert_empty runtime.agent.provider.calls
    end

    it 'keeps a blocked prompt out of the session' do
      runtime = runtime_with { |rig| rig.on(:before_prompt) { |_e| next :block, 'not now' } }
      runtime.ask('go')

      assert_empty runtime.agent.session.messages.grep(Riffer::Messages::User)
    end

    it 'ends a blocked prompt with a guardrail_blocked turn_end' do
      runtime = runtime_with { |rig| rig.on(:before_prompt) { |_e| next :block, 'not now' } }
      last = nil
      runtime.prompt('go') { |event| last = event }

      assert_equal :guardrail_blocked, last.stop_reason
    end

    it 'tells the host why a prompt was blocked' do
      runtime = runtime_with { |rig| rig.on(:before_prompt) { |_e| next :block, 'not now' } }
      notifies = runtime.prompt('go').grep(Riffer::Rig::Events::Notify)

      assert_equal [Riffer::Rig::Events::Notify.new('not now', :warning)], notifies
    end

    it 'fires before_request before each LLM call in a two-step tool turn' do
      count = 0
      runtime = runtime_with { |rig| rig.on(:before_request) { |_e| count += 1 } }
      stub_tool_turn(runtime)
      runtime.ask('go')

      assert_equal 2, count
    end

    it 'fires the second before_request after the tool result' do
      last = nil
      runtime = runtime_with { |rig| rig.on(:before_request) { |e| last = e.messages.last } }
      stub_tool_turn(runtime)
      runtime.ask('go')

      assert_instance_of Riffer::Messages::Tool, last
    end

    it 'fires before_request once for a whole batch of tool results' do
      count = 0
      runtime = runtime_with { |rig| rig.on(:before_request) { |_e| count += 1 } }
      calls = %w[one two].map { |text| { name: 'echo', arguments: { text: text }.to_json } }
      runtime.agent.provider.stub_response('', tool_calls: calls)
      runtime.agent.provider.stub_response('All done.')
      runtime.ask('go')

      assert_equal 2, count
    end

    it 'sends a replacement request payload to the model' do
      runtime = runtime_with do |rig|
        rig.on(:before_request) do |e|
          next unless e.messages.last.is_a?(Riffer::Messages::Tool)

          [*e.messages, Riffer::Messages::User.new('MID_TURN_NOTE')]
        end
      end
      stub_tool_turn(runtime)
      runtime.ask('go')

      assert_equal 'MID_TURN_NOTE', runtime.agent.provider.calls.last[:messages].last[:content]
    end

    it 'interrupts the turn when a later request is blocked' do
      runtime = runtime_with do |rig|
        rig.on(:before_request) { |e| next :block, 'enough' if e.messages.last.is_a?(Riffer::Messages::Tool) }
      end
      stub_tool_turn(runtime)
      outcome = runtime.ask('go').outcome

      assert_equal [:interrupted, 'enough'], [outcome.reason, outcome.detail]
    end

    it 'shows stream hooks every riffer stream event, unchanged' do
      seen = []
      runtime = runtime_with { |rig| rig.on(:stream) { |e| seen << e } }
      stub_tool_turn(runtime)
      streamed = runtime.prompt('go').grep(Riffer::StreamEvents::Base)

      assert_equal streamed.map(&:object_id), seen.map(&:object_id)
    end

    it 'ignores what after_response returns' do
      runtime = runtime_with { |rig| rig.on(:after_response) { |_e| 'IGNORED' } }
      runtime.agent.provider.stub_response('All done.')

      assert_equal 'All done.', runtime.ask('go').content
    end

    it 'fires after_response once per model response' do
      count = 0
      runtime = runtime_with { |rig| rig.on(:after_response) { |_e| count += 1 } }
      stub_tool_turn(runtime)
      runtime.ask('go')

      assert_equal 2, count
    end

    it 'ignores what turn_end returns' do
      runtime = runtime_with { |rig| rig.on(:turn_end) { |_e| :block } }
      runtime.agent.provider.stub_response('All done.')
      last = nil
      runtime.prompt('go') { |event| last = event }

      assert_equal :completed, last.stop_reason
    end

    it 'fires turn_end on ask as well as prompt' do
      reasons = []
      runtime = runtime_with { |rig| rig.on(:turn_end) { |e| reasons << e.stop_reason } }
      runtime.agent.provider.stub_response('All done.')
      runtime.ask('go')

      assert_equal [:completed], reasons
    end

    it 'runs hooks in load order across extensions' do
      order = []
      first = Riffer::Rig::Extension.new('first') { |rig| rig.on(:before_prompt) { |_e| order << :first } }
      second = Riffer::Rig::Extension.new('second') { |rig| rig.on(:before_prompt) { |_e| order << :second } }
      runtime = Riffer::Rig::Runtime.new('mock/test', extensions: [second, first])
      runtime.agent.provider.stub_response('All done.')
      runtime.ask('go')

      assert_equal %i[second first], order
    end
  end

  describe 'tool call events' do
    before do
      @ran = ran = []
      echo = Class.new(Riffer::Tool) do
        identifier 'echo'
        description 'Echoes its text'

        params do
          required :text, String
        end

        define_method(:call) do |context:, text:| # rubocop:disable Lint/UnusedBlockArgument -- riffer passes context: to every call
          ran << text
          text("echo: #{text}")
        end
      end
      @echo = Riffer::Rig::Extension.new('echo') { |rig| rig.tool echo }
    end

    def batch_runtime(*extensions, **)
      runtime = Riffer::Rig::Runtime.new('mock/test', extensions: [@echo, *extensions], **)
      runtime.agent.provider.stub_response('', tool_calls: %w[one two].map { |text| echo_call(text) })
      runtime.agent.provider.stub_response('All done.')
      runtime
    end

    def echo_call(text)
      { name: 'echo', arguments: { text: text }.to_json }
    end

    def tool_event?(event)
      [Riffer::Rig::Events::BeforeToolCall, Riffer::Rig::Events::AfterToolCall].include?(event.class)
    end

    def tool_events(events)
      events.select { |event| tool_event?(event) }
    end

    it 'streams each call of a batch as a before and an after, one call at a time' do
      events = tool_events(batch_runtime.prompt('go'))

      assert_equal(
        [%w[before_tool_call mock_call_0], %w[after_tool_call mock_call_0],
         %w[before_tool_call mock_call_1], %w[after_tool_call mock_call_1]],
        events.map { |event| [event.type.to_s, event.call_id] }
      )
    end

    it 'starts the batch after the last tool call of the response' do
      events = batch_runtime.prompt('go').to_a
      first = events.index { |event| tool_event?(event) }

      assert_empty events[first..].grep(Riffer::StreamEvents::ToolCallDone)
    end

    it 'keeps every tool call event ahead of the response that follows the batch' do
      events = batch_runtime.prompt('go').to_a
      text = events.index { |event| event.is_a?(Riffer::StreamEvents::TextDelta) }

      assert_empty tool_events(events[text..])
    end

    it 'hands a block each event as it happens, before the next tool runs' do
      progress = []
      batch_runtime.prompt('go') { |event| progress << [event.type, @ran.dup] if tool_event?(event) }

      assert_equal(
        [[:before_tool_call, []], [:after_tool_call, ['one']],
         [:before_tool_call, ['one']], [:after_tool_call, %w[one two]]],
        progress
      )
    end

    it 'hands an enumerator consumer a before event before its tool has run' do
      stream = batch_runtime.prompt('go')
      loop { break if stream.next.is_a?(Riffer::Rig::Events::BeforeToolCall) }

      assert_empty @ran
    end

    it 'hands an enumerator consumer an after event before the next tool has run' do
      stream = batch_runtime.prompt('go')
      loop { break if stream.next.is_a?(Riffer::Rig::Events::AfterToolCall) }

      assert_equal ['one'], @ran
    end

    it 'times each call with the injected clock' do
      ticks = 10.0.step(by: 0.5)
      events = tool_events(batch_runtime(clock: -> { ticks.next }).prompt('go'))

      assert_equal(
        [10.5, [11.0, 0.5], 12.0, [12.5, 0.5]],
        events.map { |event| event.is_a?(Riffer::Rig::Events::AfterToolCall) ? [event.at, event.duration] : event.at }
      )
    end

    it 'streams a notify raised inside a tool call next to that call' do
      raiser = Riffer::Rig::Extension.new('raiser') { |rig| rig.on(:before_tool_call) { |_e| raise 'boom' } }
      types = batch_runtime(raiser).prompt('go').filter_map { |event| event.type if event.respond_to?(:type) }

      assert_equal %i[before_tool_call notify after_tool_call], types[types.index(:before_tool_call), 3]
    end

    it 'keeps the tool call events out of the stream hook' do
      seen = []
      observer = Riffer::Rig::Extension.new('observer') { |rig| rig.on(:stream) { |event| seen << event } }
      batch_runtime(observer).ask('go')

      assert_empty tool_events(seen)
    end

    it 'runs the tools under ask, where no one reads the stream' do
      batch_runtime.ask('go')

      assert_equal %w[one two], @ran
    end
  end

  it 'closes a runtime and refuses further asks' do
    runtime = Riffer::Rig::Runtime.new('mock/test', extensions: [@extension])
    runtime.close

    assert_raises(Riffer::Rig::Runtime::ClosedError) { runtime.ask('hello') }
  end

  it 'refuses an ask while a prompt is running' do
    runtime = Riffer::Rig::Runtime.new('mock/test', extensions: [@extension])
    runtime.agent.provider.stub_response('first')
    runtime.agent.provider.stub_response('second')

    assert_raises(Riffer::Rig::Runtime::BusyError) do
      runtime.prompt('hello') do
        runtime.ask('second')
      end
    end
  end

  it 'asks and returns riffer response with the content' do
    runtime = Riffer::Rig::Runtime.new('mock/test', extensions: [@extension])
    runtime.agent.provider.stub_response('All done.')

    response = runtime.ask('hello')

    assert_equal 'All done.', response.content
  end

  it 'asks and reports how the run ended' do
    runtime = Riffer::Rig::Runtime.new('mock/test', extensions: [@extension])
    runtime.agent.provider.stub_response('All done.')

    response = runtime.ask('hello')

    assert_equal :completed, response.outcome.reason
  end

  it 'asks and carries the run token usage' do
    usage = Riffer::Providers::TokenUsage.new(input_tokens: 10, output_tokens: 5)
    runtime = Riffer::Rig::Runtime.new('mock/test', extensions: [@extension])
    runtime.agent.provider.stub_response('All done.', token_usage: usage)

    response = runtime.ask('hello')

    assert_equal usage, response.token_usage
  end

  it 'asks and lists the tool calls the model made' do
    runtime = Riffer::Rig::Runtime.new('mock/test', extensions: [@extension], tools: %w[read])
    runtime.agent.provider.stub_response('', tool_calls: [{ name: 'read', arguments: '{"path":"/tmp/x"}' }])
    runtime.agent.provider.stub_response('The file says hi.')

    response = runtime.ask('read /tmp/x')

    names = response.messages.filter_map do |message|
      next unless message.is_a?(Riffer::Messages::Assistant)

      message.tool_calls.map(&:name)
    end.flatten

    assert_equal ['read'], names
  end

  it 'ends a capped run with the max_steps outcome' do
    runtime = Riffer::Rig::Runtime.new('mock/test', extensions: [@extension], tools: %w[read], max_steps: 1)
    runtime.agent.provider.stub_response('', tool_calls: [{ name: 'read', arguments: '{"path":"/tmp/x"}' }])
    runtime.agent.provider.stub_response('second response')

    response = runtime.ask('go')

    assert_equal :max_steps, response.outcome.reason
  end

  describe 'commands' do
    before do
      @git = Riffer::Rig::Extension.new('git') do |rig|
        rig.command('log', description: 'Recent commits') { |ctx| ctx.say("commits: #{ctx.args}") }
        rig.command('review', description: 'Review the diff') { |ctx| ctx.prompt("Review this diff: #{ctx.args}") }
        rig.command('depth', description: 'Show the depth') { |ctx| ctx.say(ctx.settings.fetch(:depth, 'none').to_s) }
        rig.command('boom', description: 'Always fails') { |_ctx| raise 'kaboom' }
        rig.command('which', description: 'Ask a question') { |ctx| ctx.say(ctx.ask('Which branch?').inspect) }
      end
      @other = Riffer::Rig::Extension.new('other') do |rig|
        rig.command('hello', description: 'Say hello') { |ctx| ctx.say('hello') }
      end
    end

    def command_events(runtime, name, args = '')
      events = []
      runtime.run_command(name, args) { |event| events << event }
      events
    end

    it 'lists names and descriptions in load order' do
      runtime = Riffer::Rig::Runtime.new('mock/test', extensions: [@git, @other])

      assert_equal(
        [['log', 'Recent commits'], ['review', 'Review the diff'], ['depth', 'Show the depth'],
         ['boom', 'Always fails'], ['which', 'Ask a question'], ['hello', 'Say hello']],
        runtime.commands.reject { |command| command.extension == :core }
               .map { |command| [command.name, command.description] }
      )
    end

    it 'lets a later extension replace a command of the same name' do
      later = Riffer::Rig::Extension.new('later') { |rig| rig.command('log', description: 'Later log') { |_ctx| nil } }
      runtime = Riffer::Rig::Runtime.new('mock/test', extensions: [@git, later])

      assert_equal 'Later log', runtime.commands.find { |command| command.name == 'log' }.description
    end

    describe 'the core commands' do
      before do
        @home = Dir.mktmpdir
        @paths = { auth_path: File.join(@home, 'auth.json'), settings_path: File.join(@home, 'settings.json') }
      end

      after do
        FileUtils.remove_entry(@home)
      end

      it 'saves /model to its settings_path' do
        command_events(Riffer::Rig::Runtime.new('mock/test', **@paths), 'model', '--save')

        assert_equal 'mock/test', JSON.parse(File.read(@paths[:settings_path]))['model']
      end

      it 'saves /reasoning to its settings_path' do
        command_events(Riffer::Rig::Runtime.new('mock/test', **@paths), 'reasoning', 'high --save')

        assert_equal 'high', JSON.parse(File.read(@paths[:settings_path]))['reasoning']
      end

      it 'removes /auth credentials from its auth_path' do
        Riffer::Rig::Credentials.store(:openai, { api_key: 'sk-stored' }, **@paths)
        command_events(Riffer::Rig::Runtime.new('mock/test', **@paths), 'auth', 'remove openai')

        assert_equal :missing,
                     Riffer::Rig::Credentials.status(
                       :openai,
                       env: Riffer::Rig::Env.new({}),
                       auth_path: @paths[:auth_path]
                     )
      end

      it 'reads /auth statuses from its env' do
        runtime = Riffer::Rig::Runtime.new('mock/test', env: Riffer::Rig::Env.new('GEMINI_API_KEY' => 'k'), **@paths)

        assert_match(/^gemini\s+env$/, command_events(runtime, 'auth').first.text)
      end
    end

    describe '#install_command' do
      it 'keeps an installed command through a rebuild' do
        runtime = Riffer::Rig::Runtime.new('mock/test')
        command = Riffer::Rig::Command.new('reload', description: 'Reload', extension: :core) { |_ctx| nil }
        runtime.install_command(command)
        runtime.rebuild(extensions: [], settings: {})

        assert_equal(command, runtime.commands.find { |candidate| candidate.name == 'reload' })
      end

      it 'lets an extension command replace an installed one' do
        runtime = Riffer::Rig::Runtime.new('mock/test')
        command = Riffer::Rig::Command.new('log', description: 'Installed log', extension: :core) { |_ctx| nil }
        runtime.install_command(command)
        runtime.rebuild(extensions: [@git], settings: {})

        assert_equal 'Recent commits', runtime.commands.find { |candidate| candidate.name == 'log' }.description
      end
    end

    describe '#install_reload_check' do
      def checked_runtime(seen)
        runtime = Riffer::Rig::Runtime.new('mock/test', extensions: [@extension], tools: %w[read])
        runtime.install_reload_check(->(checked) { seen << checked })
        runtime
      end

      it 'runs the check with the Runtime when a turn starts' do
        seen = []
        runtime = checked_runtime(seen)
        runtime.agent.provider.stub_response('All done.')
        runtime.ask('go')

        assert_equal [runtime], seen
      end

      it 'runs the check again before the request that follows the tool results' do
        seen = []
        runtime = checked_runtime(seen)
        runtime.agent.provider.stub_response('', tool_calls: [{ name: 'read', arguments: '{"path":"/tmp/x"}' }])
        runtime.agent.provider.stub_response('The file says hi.')
        runtime.ask('read /tmp/x')

        assert_equal [runtime, runtime], seen
      end
    end

    it 'refuses a command on a closed Runtime' do
      runtime = Riffer::Rig::Runtime.new('mock/test', extensions: [@git])
      runtime.close

      assert_raises(Riffer::Rig::Runtime::ClosedError) { runtime.run_command('log', '') }
    end

    it 'raises while a prompt runs' do
      runtime = Riffer::Rig::Runtime.new('mock/test', extensions: [@git])
      runtime.agent.provider.stub_response('All done.')

      assert_raises(Riffer::Rig::Runtime::BusyError) do
        runtime.prompt('hello') { runtime.run_command('log', '') }
      end
    end

    it 'keeps the Runtime busy after refusing a nested command' do
      runtime = Riffer::Rig::Runtime.new('mock/test', extensions: [@git])
      runtime.agent.provider.stub_response('All done.')

      assert_raises(Riffer::Rig::Runtime::BusyError) do
        runtime.prompt('hello') do
          runtime.run_command('log', '')
        rescue Riffer::Rig::Runtime::BusyError
          runtime.ask('second')
        end
      end
    end

    it 'reports an unknown command through notify' do
      runtime = Riffer::Rig::Runtime.new('mock/test', extensions: [@git])

      assert_equal [Riffer::Rig::Events::Notify.new('Unknown command: nope', :error)], command_events(runtime, 'nope')
    end

    it 'emits a command_output event from ctx.say' do
      runtime = Riffer::Rig::Runtime.new('mock/test', extensions: [@git])

      assert_equal [Riffer::Rig::Events::CommandOutput.new('log', 'commits: -n 3')],
                   command_events(runtime, 'log', '-n 3')
    end

    it 'sends a user turn to the model from ctx.prompt' do
      runtime = Riffer::Rig::Runtime.new('mock/test', extensions: [@git])
      runtime.agent.provider.stub_response('Looks fine.')
      command_events(runtime, 'review', 'HEAD~1')

      assert_equal 'Review this diff: HEAD~1', runtime.agent.provider.calls.last[:messages].last[:content]
    end

    it 'streams the turn ctx.prompt runs to the block' do
      runtime = Riffer::Rig::Runtime.new('mock/test', extensions: [@git])
      runtime.agent.provider.stub_response('Looks fine.')

      assert_equal :completed, command_events(runtime, 'review').grep(Riffer::Rig::Events::TurnEnd).first.stop_reason
    end

    it 'reads the extension namespace of the settings' do
      runtime = Riffer::Rig::Runtime.new('mock/test', extensions: [@git], settings: { git: { depth: 3 } })

      assert_equal [Riffer::Rig::Events::CommandOutput.new('depth', '3')], command_events(runtime, 'depth')
    end

    it 'gives an empty settings namespace to an extension with none' do
      runtime = Riffer::Rig::Runtime.new('mock/test', extensions: [@git])

      assert_equal [Riffer::Rig::Events::CommandOutput.new('depth', 'none')], command_events(runtime, 'depth')
    end

    it 'returns nil from ctx.ask under the null host' do
      runtime = Riffer::Rig::Runtime.new('mock/test', extensions: [@git])

      assert_equal [Riffer::Rig::Events::CommandOutput.new('which', 'nil')], command_events(runtime, 'which')
    end

    it 'returns nil' do
      runtime = Riffer::Rig::Runtime.new('mock/test', extensions: [@git])

      assert_nil runtime.run_command('log', '')
    end

    it 'reports a raising command through notify' do
      runtime = Riffer::Rig::Runtime.new('mock/test', extensions: [@git])

      assert_equal [Riffer::Rig::Events::Notify.new('Command boom failed: kaboom', :error)],
                   command_events(runtime, 'boom')
    end

    it 'stays usable after a raising command' do
      runtime = Riffer::Rig::Runtime.new('mock/test', extensions: [@git])
      runtime.agent.provider.stub_response('All done.')
      command_events(runtime, 'boom')

      assert_equal :completed, runtime.ask('hello').outcome.reason
    end

    it 'refuses a prompt from inside a command and reports it' do
      nested = Riffer::Rig::Extension.new('nested') do |rig|
        rig.command('nest', description: 'Prompt the runtime directly') { |ctx| ctx.runtime.ask('hi') }
      end
      runtime = Riffer::Rig::Runtime.new('mock/test', extensions: [nested])

      assert_equal 'Command nest failed: a prompt is already running on this Runtime',
                   command_events(runtime, 'nest').first.message
    end
  end

  describe '#model' do
    it 'is the model the Runtime was built with' do
      assert_equal 'mock/test', Riffer::Rig::Runtime.new('mock/test').model
    end

    it 'is the override after assignment' do
      runtime = Riffer::Rig::Runtime.new('mock/test')
      runtime.model = 'mock/other'

      assert_equal 'mock/other', runtime.model
    end

    it 'sends the next request to the assigned model' do
      runtime = Riffer::Rig::Runtime.new('mock/test')
      runtime.model = 'mock/other'
      runtime.agent.provider.stub_response('All done.')
      runtime.ask('hello')

      assert_equal 'other', runtime.agent.provider.calls.last[:model]
    end

    it 'keeps the session across an assignment' do
      runtime = Riffer::Rig::Runtime.new('mock/test')
      session = runtime.agent.session
      runtime.model = 'mock/other'

      assert_same session, runtime.agent.session
    end

    it 'keeps the conversation history across an assignment' do
      runtime = Riffer::Rig::Runtime.new('mock/test')
      runtime.agent.provider.stub_response('First.')
      runtime.ask('hello')
      runtime.model = 'mock/other'
      runtime.agent.provider.stub_response('Second.')
      runtime.ask('again')

      assert_equal(
        %w[hello First. again],
        runtime.agent.provider.calls.last[:messages].drop(1).map { |message| message[:content] }
      )
    end

    it 'keeps the tally across an assignment' do
      runtime = Riffer::Rig::Runtime.new('mock/test')
      runtime.agent.provider.stub_response(
        'First.', token_usage: Riffer::Providers::TokenUsage.new(input_tokens: 10, output_tokens: 5)
      )
      runtime.ask('hello')
      runtime.model = 'mock/other'

      assert_equal 10, runtime.tally.input_tokens
    end

    it 'keeps activated skills across a model switch' do
      runtime = skilled_runtime
      runtime.agent.context.skills.activate('a')
      runtime.model = 'mock/other'

      assert_equal %w[a], runtime.to_h[:skills]
    end

    it 'keeps the model when the assignment names an unknown provider' do
      runtime = Riffer::Rig::Runtime.new('mock/test')
      begin
        runtime.model = 'acme/fast'
      rescue Riffer::ArgumentError
        nil
      end

      assert_equal 'mock/test', runtime.model
    end
  end

  it 're-derives its model options for the new provider on a switch' do
    runtime = Riffer::Rig::Runtime.new('anthropic/claude-sonnet-4-6')

    runtime.model = 'mock/test'

    assert_equal({}, runtime.agent.config.model_options)
  end

  it 'keeps the reasoning level across a switch' do
    runtime = Riffer::Rig::Runtime.new('anthropic/claude-sonnet-4-6', reasoning: 'high')

    runtime.model = 'mock/test'

    assert_equal :high, runtime.agent.config.reasoning
  end

  it 're-derives the provider option for the new provider on a switch' do
    runtime = Riffer::Rig::Runtime.new('mock/test', native_tools: { web_search: true })
    runtime.model = 'gemini/gem-2.5-pro'

    assert_equal({}, runtime.agent.config.model_options)
  end

  describe '#reasoning' do
    it 'is the level from the settings' do
      assert_equal 'high', Riffer::Rig::Runtime.new('mock/test', settings: { reasoning: 'high' }).reasoning
    end

    it 'leaves an unrecognized settings level unread' do
      assert_nil Riffer::Rig::Runtime.new('mock/test', settings: { reasoning: 'turbo' }).reasoning
    end

    it 'is nil without a level anywhere' do
      assert_nil Riffer::Rig::Runtime.new('mock/test').reasoning
    end

    it 'is the override over the settings' do
      runtime = Riffer::Rig::Runtime.new('mock/test', settings: { reasoning: 'low' }, reasoning: 'high')

      assert_equal 'high', runtime.reasoning
    end

    it 'is the level the snapshot restored' do
      runtime = Riffer::Rig::Runtime.new('mock/test', settings: { reasoning: 'low' })
      runtime.reasoning = 'high'
      restored = Riffer::Rig::Runtime.new('mock/test', settings: { reasoning: 'low' }, snapshot: runtime.to_h)

      assert_equal 'high', restored.reasoning
    end
  end

  describe '#reasoning=' do
    it 'carries the switched level to the agent config' do
      runtime = Riffer::Rig::Runtime.new('openai/gpt-5', reasoning: 'low')
      runtime.reasoning = 'high'

      assert_equal :high, runtime.agent.config.reasoning
    end

    it 'keeps the switched level when the model switches' do
      runtime = Riffer::Rig::Runtime.new('openai/gpt-5', settings: { reasoning: 'low' })
      runtime.reasoning = 'high'
      runtime.model = 'openai/o3'

      assert_equal 'high', runtime.reasoning
    end

    it 'carries the switched level to the config the switch lands on' do
      runtime = Riffer::Rig::Runtime.new('openai/gpt-5', settings: { reasoning: 'low' })
      runtime.reasoning = 'high'
      runtime.model = 'openai/o3'

      assert_equal :high, runtime.agent.config.reasoning
    end

    it 'keeps the session across a level switch' do
      runtime = Riffer::Rig::Runtime.new('mock/test')
      session = runtime.agent.session
      runtime.reasoning = 'high'

      assert_same session, runtime.agent.session
    end
  end

  describe '#on_reasoning_change' do
    it 'sends the switch to the subscriber' do
      seen = []
      runtime = Riffer::Rig::Runtime.new('mock/test')
      runtime.on_reasoning_change { |level| seen << level }
      runtime.reasoning = 'high'

      assert_equal %w[high], seen
    end

    it 'sends nothing while no level is switched' do
      seen = []
      runtime = Riffer::Rig::Runtime.new('mock/test')
      runtime.on_reasoning_change { |level| seen << level }

      assert_empty seen
    end
  end

  it 'merges the credentials of a provider into the ones it holds' do
    runtime = Riffer::Rig::Runtime.new('mock/test', credentials: { anthropic: { api_key: 'sk-ant-test' } })
    runtime.merge_credentials(:openai, { api_key: 'sk-test' })

    assert_equal({ anthropic: { api_key: 'sk-ant-test' }, openai: { api_key: 'sk-test' } }, runtime.credentials)
  end

  describe '#rebuild' do
    before do
      @lifecycle = []
      lifecycle = @lifecycle
      @old = Riffer::Rig::Extension.new('old') do |rig|
        rig.tool Riffer::Rig::Tools::Read
        rig.command('old', description: 'The old command') { |ctx| ctx.say('old') }
        rig.prompt(:section) { 'OLD_SECTION' }
        rig.on(:before_prompt) { |_e| lifecycle << :old_hook }
        rig.on(:session_end) { |e| lifecycle << [:old, e] }
      end
      @new = Riffer::Rig::Extension.new('new') do |rig|
        rig.tool Riffer::Rig::Tools::Bash
        rig.command('new', description: 'The new command') { |ctx| ctx.say('new') }
        rig.prompt(:section) { 'NEW_SECTION' }
        rig.on(:before_prompt) { |_e| lifecycle << :new_hook }
        rig.on(:session_start) { |e| lifecycle << [:new, e] }
      end
      @runtime = Riffer::Rig::Runtime.new('mock/test', extensions: [@old])
    end

    def started(runtime)
      usage = Riffer::Providers::TokenUsage.new(input_tokens: 7, output_tokens: 3)
      runtime.agent.provider.stub_response('Before.', token_usage: usage)
      runtime.ask('before')
      runtime
    end

    def rebuilt(runtime = started(@runtime), extensions: [@new], settings: {})
      runtime.rebuild(extensions: extensions, settings: settings)
      runtime
    end

    def next_turn(runtime)
      runtime.agent.provider.stub_response('After.')
      runtime.prompt('after').to_a
    end

    it 'raises on a closed Runtime' do
      @runtime.close

      assert_raises(Riffer::Rig::Runtime::ClosedError) { @runtime.rebuild(extensions: [@new], settings: {}) }
    end

    describe 'with a raising extension in the new list' do
      before do
        @broken = Riffer::Rig::Extension.new('broken') do |rig|
          rig.tool Riffer::Rig::Tools::Write
          raise 'kaboom'
        end
        started(@runtime)
      end

      def attempt
        @runtime.rebuild(extensions: [@new, @broken], settings: { model: 'mock/other' })
      rescue RuntimeError
        nil
      end

      it 'propagates the error' do
        assert_raises(RuntimeError) { @runtime.rebuild(extensions: [@new, @broken], settings: {}) }
      end

      it 'keeps the old tools' do
        attempt

        assert_equal [Riffer::Rig::Tools::Read], @runtime.agent.tools
      end

      it 'keeps the old commands' do
        attempt

        assert_equal %w[auth model reasoning cost old], @runtime.commands.map(&:name)
      end

      it 'keeps the old settings' do
        attempt

        assert_empty @runtime.settings
      end

      it 'fires no lifecycle hooks' do
        @lifecycle.clear
        attempt

        assert_empty @lifecycle
      end

      it 'releases the Runtime for the next rebuild' do
        attempt

        assert_nil @runtime.rebuild(extensions: [@new], settings: {})
      end
    end

    it 'returns nil' do
      assert_nil @runtime.rebuild(extensions: [@new], settings: {})
    end

    it 'swaps in the tools of the new list' do
      assert_equal [Riffer::Rig::Tools::Bash], rebuilt.agent.tools
    end

    it 'swaps in the commands of the new list' do
      assert_equal %w[auth model reasoning cost new], rebuilt.commands.map(&:name)
    end

    it 'lists a skill added before a rebuild' do
      runtime = skilled_runtime
      write_skill(skills_dir, 'b')
      runtime.rebuild(extensions: [skills_extension], settings: {})

      assert_includes runtime.commands.map(&:name), 'skill:b'
    end

    it 'renders the prompt sections of the new list' do
      runtime = rebuilt
      next_turn(runtime)

      assert_includes runtime.agent.provider.calls.last[:messages].first[:content], 'NEW_SECTION'
    end

    it 'runs the hooks of the new list only' do
      runtime = rebuilt
      @lifecycle.clear
      next_turn(runtime)

      assert_equal [:new_hook], @lifecycle
    end

    it 'applies the new settings with the new declared defaults' do
      declaring = Riffer::Rig::Extension.new('git') { |rig| rig.setting :depth, default: 3 }

      runtime = rebuilt(extensions: [declaring], settings: { model: 'mock/other' })

      assert_equal({ model: 'mock/other', git: { depth: 3 } }, runtime.settings)
    end

    it 'keeps the message history' do
      runtime = started(@runtime)
      history = runtime.agent.session.messages.drop(1)

      assert_equal history, rebuilt(runtime).agent.session.messages.drop(1)
    end

    it 'keeps the tally' do
      assert_equal 10, rebuilt.tally.total_tokens
    end

    it 'keeps the /model override' do
      runtime = started(@runtime)
      runtime.model = 'mock/other'

      assert_equal 'mock/other', rebuilt(runtime, settings: { model: 'mock/test' }).model
    end

    it 'keeps the reasoning level' do
      runtime = started(@runtime)
      runtime.reasoning = 'high'

      assert_equal :high, rebuilt(runtime).agent.config.reasoning
    end

    it 'keeps the id' do
      id = @runtime.id

      assert_equal id, rebuilt.id
    end

    it 'keeps the host' do
      host = @runtime.host

      assert_same host, rebuilt.host
    end

    it 'keeps the tool allowlist' do
      runtime = Riffer::Rig::Runtime.new('mock/test', extensions: [@old], tools: %w[read])

      assert_empty rebuilt(runtime).agent.tools
    end

    it 'keeps its model options through a rebuild' do
      runtime = Riffer::Rig::Runtime.new('mock/test', model_options: { reasoning: 'high' })
      runtime.rebuild(extensions: [], settings: {})

      assert_equal({ reasoning: 'high' }, runtime.agent.config.model_options)
    end

    it 'clears the load errors of the old list' do
      broken = Riffer::Rig::Extension.new('broken') { |_rig| raise 'kaboom' }
      runtime = Riffer::Rig::Runtime.new('mock/test', extensions: [broken])

      assert_empty rebuilt(runtime).errors
    end

    it 'unregisters a server the rebuilt list no longer declares' do
      registry = recording_mcp_registry
      runtime = Riffer::Rig::Runtime.new('mock/test', extensions: [serving_mcp('web')], mcp_registry: registry)
      runtime.rebuild(extensions: [], settings: {})

      assert_empty registry.registered
    end

    it 'fires session_end with the reload reason on the old hooks' do
      rebuilt

      assert_includes @lifecycle, [:old, Riffer::Rig::Events::SessionEnd.new(:reload)]
    end

    it 'fires session_start with the reload reason on the new hooks' do
      runtime = rebuilt

      assert_includes @lifecycle, [:new, Riffer::Rig::Events::SessionStart.new(runtime.id, :reload)]
    end

    it 'opens the next turn with session_end then session_start, both for the reload' do
      runtime = rebuilt

      session_end = Riffer::Rig::Events::SessionEnd.new(:reload)
      session_start = Riffer::Rig::Events::SessionStart.new(runtime.id, :reload)

      assert_equal [session_end, session_start], next_turn(runtime).take(2)
    end

    it 'leaves a session that never started to open with session_start new' do
      runtime = rebuilt(@runtime)

      assert_equal Riffer::Rig::Events::SessionStart.new(runtime.id, :new), next_turn(runtime).first
    end

    it 'rebuilds from inside a hook' do
      runtime = nil
      reloading = Riffer::Rig::Extension.new('reloading') do |rig|
        rig.on(:turn_end) { |_e| runtime.rebuild(extensions: [], settings: {}) }
      end
      runtime = Riffer::Rig::Runtime.new('mock/test', extensions: [reloading])
      runtime.agent.provider.stub_response('All done.')
      runtime.prompt('go') { |event| event }

      assert_empty runtime.agent.tools
    end

    it 'rebuilds from inside a command' do
      reloading = Riffer::Rig::Extension.new('reloading') do |rig|
        rig.command('reload', description: 'Rebuild') { |ctx| ctx.runtime.rebuild(extensions: [], settings: {}) }
      end
      runtime = Riffer::Rig::Runtime.new('mock/test', extensions: [reloading])
      runtime.run_command('reload')

      assert_empty runtime.agent.tools
    end

    describe 'providers' do
      before do
        @provider = Riffer::Rig::Extension.new('provider') do |_rig|
          Riffer::Providers::Repository.register(:rig_rebuild) { Riffer::Providers::Mock }
        end
        @on_provider = Riffer::Rig::Runtime.new('rig_rebuild/fast', extensions: [@provider])
      end

      after do
        Riffer::Providers::Repository.unregister(:rig_rebuild)
      end

      it 'keeps a provider registered before the rebuild' do
        assert_equal 'rig_rebuild/fast', rebuilt(@on_provider, extensions: []).model
      end

      it 're-registers a provider idempotently' do
        assert_equal 'rig_rebuild/fast', rebuilt(@on_provider, extensions: [@provider]).model
      end
    end
  end

  describe 'snapshots' do
    def saved_runtime
      runtime = Riffer::Rig::Runtime.new('mock/test', extensions: [@extension])
      runtime.agent.provider.stub_response('Hi there.', token_usage: usage(10, 5))
      runtime.ask('hello')
      runtime
    end

    def restored(snapshot, **)
      Riffer::Rig::Runtime.new('mock/test', extensions: [@extension], snapshot: snapshot, **)
    end

    def first_prompt_events(runtime)
      runtime.agent.provider.stub_response('Again.')
      runtime.prompt('again').to_a
    end

    it 'holds the messages as riffer hashes' do
      runtime = saved_runtime

      assert_equal runtime.agent.session.messages.map(&:to_h), runtime.to_h[:messages]
    end

    it 'holds no model without an override' do
      assert_nil saved_runtime.to_h[:model]
    end

    it 'holds the model override' do
      runtime = saved_runtime
      runtime.model = 'mock/other'

      assert_equal 'mock/other', runtime.to_h[:model]
    end

    it 'holds no reasoning without a switch' do
      assert_nil saved_runtime.to_h[:reasoning]
    end

    it 'holds the reasoning switch' do
      runtime = saved_runtime
      runtime.reasoning = 'high'

      assert_equal 'high', runtime.to_h[:reasoning]
    end

    it 'restores the reasoning switch' do
      runtime = saved_runtime
      runtime.reasoning = 'high'

      assert_equal 'high', restored(runtime.to_h).reasoning
    end

    it 'leaves an unrecognized snapshot level unrestored' do
      saved = saved_runtime.to_h
      saved[:reasoning] = 'turbo'

      assert_nil restored(saved).reasoning
    end

    it 'holds no skills while none are activated' do
      assert_empty saved_runtime.to_h[:skills]
    end

    it 'records a skill the model activated' do
      runtime = skilled_runtime
      runtime.agent.context.skills.activate('a')

      assert_equal %w[a], runtime.to_h[:skills]
    end

    it 'restores the id' do
      snapshot = saved_runtime.to_h

      assert_equal snapshot[:id], restored(snapshot).id
    end

    it 'continues the conversation after a restore' do
      runtime = restored(saved_runtime.to_h)
      runtime.agent.provider.stub_response('Welcome back.')
      runtime.ask('still there?')
      sent = runtime.agent.provider.calls.last[:messages].map { |message| message[:content] }

      assert_equal ['hello', 'Hi there.', 'still there?'], sent.drop(1)
    end

    it 'opens the first prompt after a restore with session_start(reason: :restore)' do
      snapshot = saved_runtime.to_h
      first = first_prompt_events(restored(snapshot)).first

      assert_equal Riffer::Rig::Events::SessionStart.new(snapshot[:id], :restore), first
    end

    it 'delivers session_start(reason: :restore) to hooks' do
      reasons = []
      hooks = Riffer::Rig::Extension.new('restore_hooks') { |rig| rig.on(:session_start) { |e| reasons << e.reason } }
      runtime = Riffer::Rig::Runtime.new('mock/test', extensions: [hooks], snapshot: saved_runtime.to_h)
      first_prompt_events(runtime)

      assert_equal [:restore], reasons
    end

    it 'applies the saved model when its provider has credentials' do
      runtime = saved_runtime
      runtime.model = 'mock/other'

      assert_equal 'mock/other', restored(runtime.to_h, credentials: { mock: {} }).model
    end

    it 'keeps the saved model as the override of the restored Runtime' do
      runtime = saved_runtime
      runtime.model = 'mock/other'

      assert_equal 'mock/other', restored(runtime.to_h, credentials: { mock: {} }).to_h[:model]
    end

    it 'uses the given model when the saved provider has no credentials' do
      runtime = saved_runtime
      runtime.model = 'mock/other'

      assert_equal 'mock/test', restored(runtime.to_h).model
    end

    it 'restores the tally as the sum of the messages token usage' do
      runtime = saved_runtime
      runtime.agent.provider.stub_response('Second.', token_usage: usage(20, 7))
      runtime.ask('again')

      assert_equal usage(30, 12).to_h, restored(runtime.to_h).tally.to_h
    end
  end

  describe '#on_message' do
    it 'fires once per message the turn adds' do
      runtime = Riffer::Rig::Runtime.new('mock/test', extensions: [@extension], tools: %w[read])
      observed = []
      runtime.on_message { |message| observed << message }
      runtime.agent.provider.stub_response('', tool_calls: [{ name: 'read', arguments: '{"path":"/tmp/x"}' }])
      runtime.agent.provider.stub_response('The file says hi.')
      runtime.ask('read /tmp/x')

      assert_equal runtime.agent.session.messages.drop(1), observed
    end

    it 'keeps firing once per message after a model switch' do
      runtime = Riffer::Rig::Runtime.new('mock/test', extensions: [@extension])
      observed = []
      runtime.on_message { |message| observed << message }
      runtime.model = 'mock/other'
      runtime.agent.provider.stub_response('All done.')
      runtime.ask('hello')

      assert_equal 2, observed.length
    end

    it 'fires for a restored Runtime' do
      runtime = restored_for_observer
      observed = []
      runtime.on_message { |message| observed << message }
      runtime.agent.provider.stub_response('All done.')
      runtime.ask('hello')

      assert_equal ['hello', 'All done.'], observed.map(&:content)
    end

    def restored_for_observer
      saved = Riffer::Rig::Runtime.new('mock/test', extensions: [@extension])
      Riffer::Rig::Runtime.new('mock/test', extensions: [@extension], snapshot: saved.to_h)
    end
  end

  describe '#on_model_change' do
    it 'notifies its observers on a switch' do
      runtime = Riffer::Rig::Runtime.new('mock/test')
      seen = []
      runtime.on_model_change { |model| seen << model }
      runtime.model = 'mock/other'

      assert_equal ['mock/other'], seen
    end

    it 'does not notify for the model the Runtime was built with' do
      runtime = Riffer::Rig::Runtime.new('mock/test')
      seen = []
      runtime.on_model_change { |model| seen << model }

      assert_empty seen
    end
  end

  describe '#on_job_exit' do
    before do
      @runtime = Riffer::Rig::Runtime.new('mock/test')
      @exits = job_exits(@runtime)
    end

    after do
      @runtime.close
    end

    it 'calls a subscriber with the completion of a job that exited' do
      job = spawn_group_job(@runtime, 'true')

      assert_equal job.id, @exits.pop(timeout: 5)&.job_id
    end

    it 'drops the exit of a job once the Runtime is closed' do
      spawn_group_job(@runtime)
      @runtime.close

      assert_empty @exits
    end

    it 'returns nil' do
      assert_nil(@runtime.on_job_exit { |completion| completion })
    end
  end

  describe '#running_job_count' do
    before do
      @runtime = Riffer::Rig::Runtime.new('mock/test')
      @exits = job_exits(@runtime)
    end

    after do
      @runtime.close
    end

    it 'is zero without a job' do
      assert_equal 0, @runtime.running_job_count
    end

    it 'counts a running job' do
      spawn_group_job(@runtime)

      assert_equal 1, @runtime.running_job_count
    end

    it 'drops when a job exits with no turn running' do
      spawn_group_job(@runtime, 'true')
      @exits.pop(timeout: 5)

      assert_equal 0, @runtime.running_job_count
    end
  end

  describe '#busy?' do
    before do
      @runtime = Riffer::Rig::Runtime.new('mock/test')
    end

    after do
      @runtime.close
    end

    it 'is false between turns' do
      refute_predicate @runtime, :busy?
    end

    it 'is true while a prompt runs' do
      @runtime.agent.provider.stub_response('Hi.')
      busy = false
      @runtime.prompt('hello') { busy = @runtime.busy? }

      assert busy
    end
  end

  describe '#pending_jobs?' do
    before do
      @runtime = Riffer::Rig::Runtime.new('mock/test')
      @exits = job_exits(@runtime)
    end

    after do
      @runtime.close
    end

    it 'is false without a job' do
      refute_predicate @runtime, :pending_jobs?
    end

    it 'is true while a job runs' do
      spawn_group_job(@runtime)

      assert_predicate @runtime, :pending_jobs?
    end

    it 'stays true for a job that exited until the model is told' do
      spawn_group_job(@runtime, 'true')
      @exits.pop(timeout: 5)

      assert_predicate @runtime, :pending_jobs?
    end

    it 'is false once the model is told of the exit' do
      spawn_group_job(@runtime, 'true')
      @exits.pop(timeout: 5)
      @runtime.agent.provider.stub_response('Noted.')
      @runtime.ask('next')

      refute_predicate @runtime, :pending_jobs?
    end
  end

  describe '#await_job_exit' do
    before do
      @runtime = Riffer::Rig::Runtime.new('mock/test')
      @exits = job_exits(@runtime)
    end

    after do
      @runtime.close
    end

    it 'is true for an exit the model has not been told of' do
      spawn_group_job(@runtime, 'true')
      @exits.pop(timeout: 5)

      assert @runtime.await_job_exit(timeout: 0)
    end

    it 'waits for the next exit without a timeout by default' do
      spawn_group_job(@runtime, 'sleep 0.1')

      assert @runtime.await_job_exit
    end
  end

  describe '#pending_job_exit_count' do
    before do
      @runtime = Riffer::Rig::Runtime.new('mock/test')
      @exits = job_exits(@runtime)
    end

    after do
      @runtime.close
    end

    it 'is zero without an exit' do
      assert_equal 0, @runtime.pending_job_exit_count
    end

    it 'counts an exit no turn has delivered' do
      spawn_group_job(@runtime, 'true')
      @exits.pop(timeout: 5)

      assert_equal 1, @runtime.pending_job_exit_count
    end

    it 'drops once a turn delivers the exit' do
      spawn_group_job(@runtime, 'true')
      @exits.pop(timeout: 5)
      @runtime.ask('next')

      assert_equal 0, @runtime.pending_job_exit_count
    end
  end

  describe 'job exit notifications' do
    before do
      exits = @exits = Queue.new
      job = Class.new(Riffer::Tool) do
        identifier 'job'
        description 'Starts a background job, waits for its exit, then answers as told'

        params do
          required :answer, String
        end

        define_method(:call) do |context:, answer:|
          context[:jobs].register(Process.spawn('true', pgroup: true), 'true', File.open(File::NULL))
          exits.pop(timeout: 5)
          answer == 'fail' ? error('boom') : text(answer)
        end
      end
      @job = Riffer::Rig::Extension.new('job') { |rig| rig.tool job }
      @runtimes = []
    end

    after do
      @runtimes.each(&:close)
    end

    def job_runtime(*extensions, **)
      runtime = Riffer::Rig::Runtime.new('mock/test', extensions: [@extension, @job, *extensions], **)
      runtime.on_job_exit { |completion| @exits << completion }
      @runtimes << runtime
      runtime
    end

    def job_call(answer = 'started')
      { name: 'job', arguments: { answer: answer }.to_json }
    end

    def exiting_mid_turn(answer = 'started')
      runtime = job_runtime
      runtime.agent.provider.stub_response('', tool_calls: [job_call(answer)])
      runtime.agent.provider.stub_response('All done.')
      runtime
    end

    def exiting_on_reply(replies, **)
      remaining = replies
      runtime = nil
      on_reply = lambda do |_event|
        next if remaining.zero?

        remaining -= 1
        spawn_group_job(runtime, 'true')
        @exits.pop(timeout: 5)
      end
      exits_on_reply = Riffer::Rig::Extension.new('exits_on_reply') { |rig| rig.on(:after_response, &on_reply) }
      runtime = job_runtime(exits_on_reply, **)
    end

    def continued_turn
      runtime = exiting_on_reply(1)
      runtime.agent.provider.stub_response('Started it.', token_usage: usage(10, 5))
      runtime.agent.provider.stub_response('It passed.', token_usage: usage(20, 7))
      runtime
    end

    def exited_between_turns(count = 1)
      runtime = job_runtime
      runtime.agent.provider.stub_response('First.')
      runtime.ask('first')
      count.times { spawn_group_job(runtime, 'true') }
      count.times { @exits.pop(timeout: 5) }
      runtime.agent.provider.stub_response('Second.')
      runtime
    end

    def notifications(runtime)
      runtime.agent.session.messages.grep(Riffer::Rig::Runtime::JobNotification)
    end

    def tool_results(runtime)
      runtime.agent.session.messages.grep(Riffer::Messages::Tool)
    end

    describe 'for a job that exits during a turn' do
      it 'leaves the result on the tool call events as the tool returned it' do
        runtime = exiting_mid_turn
        events = []
        runtime.prompt('go') { |event| events << event }

        assert_equal 'started', events.grep(Riffer::Rig::Events::AfterToolCall).last.result.content
      end

      it 'forgets the job once its exit is reported' do
        runtime = exiting_mid_turn
        runtime.ask('go')

        assert_empty runtime.agent.context[:jobs].list
      end

      it 'emits a job_exit event for the exit' do
        runtime = exiting_mid_turn
        events = []
        runtime.prompt('go') { |event| events << event }
        exits = events.grep(Riffer::Rig::Events::JobExit).map { |event| [event.command, event.exit_status] }

        assert_equal [['true', 0]], exits
      end

      it 'appends the notice to the tool result, after the tool\'s own output' do
        runtime = exiting_mid_turn
        runtime.ask('go')
        notice = /\Astarted\n\n<background-job /

        assert_match notice, tool_results(runtime).last.content
      end

      it 'keeps the error of a failed tool result' do
        runtime = exiting_mid_turn('fail')
        runtime.ask('go')
        result = tool_results(runtime).last
        noticed = result.content.include?('<background-job')

        assert_equal ['boom', :execution_error, true], [result.error, result.error_type, noticed]
      end

      it 'appends to the result of the call that just ran when a call id repeats' do
        runtime = job_runtime
        runtime.agent.provider.stub_response('', tool_calls: [{ name: 'read', arguments: '{"path":"/nope"}' }])
        runtime.agent.provider.stub_response('', tool_calls: [job_call])
        runtime.agent.provider.stub_response('All done.')
        runtime.ask('go')
        noticed = tool_results(runtime).map { |result| result.content.include?('<background-job') }

        assert_equal [false, true], noticed
      end

      it 'hands observers the tool result the model receives' do
        runtime = exiting_mid_turn
        observed = []
        runtime.on_message { |message| observed << message }
        runtime.ask('go')

        assert_same tool_results(runtime).last, observed.grep(Riffer::Messages::Tool).last
      end

      it 'reports the exit on the request that follows the tool result' do
        runtime = exiting_mid_turn
        runtime.ask('go')
        sent = runtime.agent.provider.calls.last[:messages].last

        assert_equal [:tool, true], [sent[:role], sent[:content].include?('<command>true</command>')]
      end
    end

    describe 'for a job that exits as the model finishes its reply' do
      it 'stops continuing a turn at the cap' do
        runtime = exiting_on_reply(Riffer::Rig::Runtime::MAX_JOB_CONTINUATIONS + 1)
        runtime.ask('go')

        assert_equal Riffer::Rig::Runtime::MAX_JOB_CONTINUATIONS, notifications(runtime).length
      end

      it 'delivers the exit the cap held back at the start of the next turn' do
        runtime = exiting_on_reply(Riffer::Rig::Runtime::MAX_JOB_CONTINUATIONS + 1)
        runtime.ask('go')
        runtime.ask('again')

        assert_equal(
          [Riffer::Rig::Runtime::JobNotification, Riffer::Messages::User, Riffer::Messages::Assistant],
          runtime.agent.session.messages.last(3).map(&:class)
        )
      end

      it 'keeps the exit for the next turn when the turn did not complete' do
        runtime = exiting_on_reply(1)
        runtime.agent.provider.stub_response('Cut sh', finish_reason: :length)
        runtime.ask('go')

        assert_empty notifications(runtime)
      end

      it 'keeps the exit for the next turn when the turn has used its step limit' do
        runtime = exiting_on_reply(1, max_steps: 1)
        runtime.ask('go')

        assert_empty notifications(runtime)
      end

      it 'delivers the exit the step limit held back at the start of the next turn' do
        runtime = exiting_on_reply(1, max_steps: 1)
        runtime.ask('go')
        runtime.ask('again')

        assert_equal(
          [Riffer::Rig::Runtime::JobNotification, Riffer::Messages::User, Riffer::Messages::Assistant],
          runtime.agent.session.messages.last(3).map(&:class)
        )
      end

      it 'continues the turn while its step limit has steps left' do
        runtime = exiting_on_reply(1, max_steps: 2)
        runtime.ask('go')

        assert_equal 1, notifications(runtime).length
      end

      it 'emits a job_exit event for the exit' do
        events = []
        continued_turn.prompt('go') { |event| events << event }

        assert_equal 1, events.grep(Riffer::Rig::Events::JobExit).length
      end

      it 'continues the turn with a notification after the reply' do
        runtime = continued_turn
        runtime.ask('go')

        assert_equal(
          [Riffer::Messages::User, Riffer::Messages::Assistant, Riffer::Rig::Runtime::JobNotification, Riffer::Messages::Assistant],
          runtime.agent.session.messages.drop(1).map(&:class)
        )
      end

      it 'delivers the notification to observers between the two replies' do
        runtime = continued_turn
        observed = []
        runtime.on_message { |message| observed << message }
        runtime.ask('go')

        assert_equal(
          [Riffer::Messages::Assistant, Riffer::Rig::Runtime::JobNotification, Riffer::Messages::Assistant],
          observed.drop(1).map(&:class)
        )
      end

      it 'runs the reload check again before the request that continues the turn' do
        seen = []
        runtime = continued_turn
        runtime.install_reload_check(->(checked) { seen << checked })
        runtime.ask('go')

        assert_equal [runtime, runtime], seen
      end

      it 'answers with the reply that followed the notification' do
        assert_equal 'It passed.', continued_turn.ask('go').content
      end

      it 'reports the usage of every run of the turn' do
        assert_equal usage(30, 12).to_h, continued_turn.ask('go').token_usage.to_h
      end

      it 'counts the steps of every run of the turn' do
        assert_equal 2, continued_turn.ask('go').steps
      end

      it 'ends the turn once' do
        events = []
        continued_turn.prompt('go') { |event| events << event }

        assert_equal [events.last], events.grep(Riffer::Rig::Events::TurnEnd)
      end
    end

    describe 'for a job that exits between turns' do
      it 'emits a job_exit event for each exit' do
        runtime = exited_between_turns(2)
        events = []
        runtime.prompt('second') { |event| events << event }

        assert_equal 2, events.grep(Riffer::Rig::Events::JobExit).length
      end

      it 'batches several exits into one notification' do
        runtime = exited_between_turns(2)
        runtime.ask('second')
        envelopes = notifications(runtime).map { |notification| notification.content.scan('<background-job ').length }

        assert_equal [2], envelopes
      end

      it 'marks no notification delivered ahead of the next prompt as starting a follow-up' do
        runtime = exited_between_turns
        runtime.ask('second')

        assert_equal [nil], notifications(runtime).map(&:follow_up_exits)
      end

      it 'delivers a notification ahead of the next prompt' do
        runtime = exited_between_turns
        runtime.ask('second')

        assert_equal(
          [Riffer::Rig::Runtime::JobNotification, Riffer::Messages::User, Riffer::Messages::Assistant],
          runtime.agent.session.messages.last(3).map(&:class)
        )
      end

      it 'delivers the notification to observers ahead of the prompt' do
        runtime = exited_between_turns
        observed = []
        runtime.on_message { |message| observed << message }
        runtime.ask('second')

        assert_equal [Riffer::Rig::Runtime::JobNotification, Riffer::Messages::User], observed.first(2).map(&:class)
      end
    end

    describe 'through #follow_up' do
      it 'tells the model of the exit and lets it reply' do
        runtime = exited_between_turns
        runtime.follow_up { |event| event }

        assert_equal(
          [Riffer::Messages::Assistant, Riffer::Rig::Runtime::JobNotification, Riffer::Messages::Assistant],
          runtime.agent.session.messages.last(3).map(&:class)
        )
      end

      it 'emits a job_exit event for each exit' do
        runtime = exited_between_turns(2)
        events = []
        runtime.follow_up { |event| events << event }

        assert_equal 2, events.grep(Riffer::Rig::Events::JobExit).length
      end

      it 'marks the notification as starting a follow-up of that many exits' do
        runtime = exited_between_turns(2)
        runtime.follow_up { |event| event }

        assert_equal [2], notifications(runtime).map(&:follow_up_exits)
      end

      it 'never calls the model with no exit to tell' do
        runtime = exited_between_turns(0)
        runtime.follow_up { |event| event }

        assert_equal 1, runtime.agent.provider.calls.length
      end

      it 'ends a follow-up with no exit to tell as completed' do
        runtime = exited_between_turns(0)
        events = []
        runtime.follow_up { |event| events << event }

        assert_equal :completed, events.last.stop_reason
      end
    end

    describe 'on the wire' do
      def request_behind_last_reply(runtime)
        runtime.ask('go')
        runtime.agent.session.messages[...-1]
      end

      def request_roles(adapter, messages)
        # Allocated because an adapter's initialize insists on its SDK, which
        # the bundle leaves out for Bedrock and the converters never touch.
        provider = Riffer::Providers::Repository.find(adapter).allocate
        params = provider.send(:build_request_params, provider.send(:merge_consecutive_messages, messages), 'model', {})
        (params[:messages] || params[:contents] || params[:input]).map { |entry| entry[:role] || entry[:type] }
      end

      # Bedrock and Gemini reject two turns of one role in a row, the tightest
      # rule any adapter's API applies, so a request that alternates is valid
      # for every one of them.
      adapters = Riffer::Providers::Repository::REPO.keys - [:mock]
      shapes = {
        'a notice on a tool result' => :exiting_mid_turn,
        'a notification after a reply' => :continued_turn,
        'a notification ahead of a prompt' => :exited_between_turns
      }
      adapters.product(shapes.to_a).each do |adapter, (shape, runtime)|
        it "alternates roles for #{adapter} with #{shape}" do
          roles = request_roles(adapter, request_behind_last_reply(send(runtime)))

          assert_empty(roles.each_cons(2).select { |one, other| one == other })
        end
      end
    end
  end

  describe '#cancel' do
    before do
      started = @started = Queue.new
      release = @release = Queue.new
      gate = Class.new(Riffer::Tool) do
        identifier 'gate'
        description 'Blocks until the test releases it'

        define_method(:call) do |**|
          started << true
          release.pop
          text('released')
        end
      end
      @gate_extension = Riffer::Rig.extension('test_runtime_cancel') { |rig| rig.tool gate }
      @runtime = Riffer::Rig::Runtime.new('mock/test', extensions: [@gate_extension])
      @runtime.agent.provider.stub_response(
        '', tool_calls: [{ name: 'gate', arguments: '{}' }, { name: 'gate', arguments: '{}' }]
      )
      @runtime.agent.provider.stub_response('after the cancel')
    end

    after do
      Riffer::Rig.instance_variable_get(:@extensions).delete('test_runtime_cancel')
    end

    def cancel_mid_tool
      Thread.new do
        @started.pop
        @runtime.cancel
        @release.close
      end
    end

    def cancelled_turn_events
      canceller = cancel_mid_tool
      events = []
      @runtime.prompt('go') { |event| events << event }
      canceller.join
      events
    end

    it 'sets the cancel flag a running tool polls' do
      @runtime.cancel

      assert_predicate @runtime.agent.context[:cancel_flag], :set?
    end

    it 'ends the turn with the cancelled stop reason' do
      assert_equal :cancelled, cancelled_turn_events.last.stop_reason
    end

    it 'emits the riffer interrupt event with the cancelled reason' do
      interrupt = cancelled_turn_events.find { |event| event.is_a?(Riffer::StreamEvents::Interrupt) }

      assert_equal :cancelled, interrupt.reason
    end

    it 'heals the tool calls the cancel orphaned' do
      cancelled_turn_events
      healed = @runtime.agent.session.messages.grep(Riffer::Messages::Tool).find do |message|
        message.tool_call_id == 'mock_call_1'
      end

      assert_equal :interrupted, healed.error_type
    end

    it 'prompts again after a cancelled turn' do
      cancelled_turn_events

      assert_equal :completed, @runtime.ask('again').outcome.reason
    end

    it 'reports a cancelled ask as interrupted with the cancelled detail' do
      canceller = cancel_mid_tool
      outcome = @runtime.ask('go').outcome
      canceller.join

      assert_equal [:interrupted, 'cancelled'], [outcome.reason, outcome.detail]
    end

    describe 'from inside one of the turn\'s own callbacks' do
      def cancel_and_block
        lambda do |*|
          @cancelling.cancel
          # Where an abort would land were the callback not shielded.
          sleep(0)
        end
      end

      def cancelling_on(hook)
        on_hook = cancel_and_block
        extension = Riffer::Rig::Extension.new('canceller') { |rig| rig.on(hook, &on_hook) }
        @cancelling = Riffer::Rig::Runtime.new('mock/test', extensions: [extension])
      end

      it 'records the prompt a before_prompt hook was vetting' do
        cancelling_on(:before_prompt).ask('go')

        assert_equal ['go'], @cancelling.agent.session.messages.grep(Riffer::Messages::User).map(&:content)
      end

      it 'forwards the event a stream hook was observing' do
        events = []
        cancelling_on(:stream).prompt('go') { |event| events << event }

        assert_includes events.map(&:class), Riffer::StreamEvents::TextDelta
      end

      it 'delivers the message to the observers after the one that cancelled' do
        @cancelling = Riffer::Rig::Runtime.new('mock/test')
        on_assistant = cancel_and_block
        seen = []
        @cancelling.on_message { |message| on_assistant.call if message.is_a?(Riffer::Messages::Assistant) }
        @cancelling.on_message { |message| seen << message.role }
        @cancelling.ask('go')

        assert_equal %i[user assistant], seen
      end
    end

    describe 'while the turn is stalled' do
      before do
        @stalling = Riffer::Rig::Runtime.new('mock/test', extensions: [@gate_extension])
        @stalled = Queue.new
      end

      def script_stream(*steps)
        @stalling.agent.provider.define_singleton_method(:execute_stream) do |params, yielder|
          step = steps.shift
          step ? step.call(yielder) : super(params, yielder)
        end
      end

      # A step that leaves the request to the provider's stubbed response.
      def stubbed
        nil
      end

      def stall_after(*deltas)
        lambda do |yielder|
          deltas.each { |delta| yielder << Riffer::StreamEvents::TextDelta.new(delta) }
          @stalled << true
          # Stands in for the provider's HTTP read.
          Queue.new.pop(timeout: 5)
        end
      end

      def cancel_once_stalled
        Thread.new do
          @stalled.pop
          @stalling.cancel
        end
      end

      def aborted_turn_events
        canceller = cancel_once_stalled
        events = []
        @stalling.prompt('go') { |event| events << event }
        canceller.join
        events
      end

      def aborted_ask
        canceller = cancel_once_stalled
        response = @stalling.ask('go')
        canceller.join
        response
      end

      def replies
        @stalling.agent.session.messages.grep(Riffer::Messages::Assistant).map(&:content)
      end

      it 'heals the tool calls an abort inside a tool orphaned' do
        stalled = @stalled
        exposed = Class.new(Riffer::Tool) do
          identifier 'exposed'
          description 'Blocks with the abort let through, as a provider SDK call inside a tool does'

          define_method(:call) do |**|
            stalled << true
            Thread.handle_interrupt(Object => :immediate) { Queue.new.pop(timeout: 5) }
            text('released')
          end
        end
        extension = Riffer::Rig::Extension.new('exposed') { |rig| rig.tool exposed }
        @stalling = Riffer::Rig::Runtime.new('mock/test', extensions: [extension])
        @stalling.agent.provider.stub_response('', tool_calls: [{ name: 'exposed', arguments: '{}' }])
        aborted_turn_events

        assert_equal :interrupted, @stalling.agent.session.messages.grep(Riffer::Messages::Tool).first.error_type
      end

      it 'records no reply when nothing had streamed' do
        script_stream(stall_after)
        aborted_turn_events

        assert_empty replies
      end

      it 'records no reply for whitespace alone' do
        script_stream(stall_after("\n\n"))
        aborted_turn_events

        assert_empty replies
      end

      it 'keeps the text streamed so far as the reply' do
        script_stream(stall_after('one ', 'two '))
        aborted_turn_events

        assert_equal ['one two '], replies
      end

      it 'keeps only the reply in flight' do
        @release.close
        @stalling.agent.provider.stub_response('Looking.', tool_calls: [{ name: 'gate', arguments: '{}' }])
        script_stream(stubbed, stall_after('two'))
        aborted_turn_events

        assert_equal ['Looking.', 'two'], replies
      end

      it 'forgets what a failed turn streamed' do
        failing = lambda do |yielder|
          yielder << Riffer::StreamEvents::TextDelta.new('stale')
          raise 'boom'
        end
        script_stream(failing, stall_after)
        begin
          @stalling.ask('go')
        rescue RuntimeError
          nil
        end
        aborted_turn_events

        assert_empty replies
      end

      it 'delivers the partial reply to message observers' do
        delivered = []
        @stalling.on_message { |message| delivered << message }
        script_stream(stall_after('one ', 'two '))
        aborted_turn_events

        assert_equal 'one two ', delivered.last.content
      end

      it 'emits the riffer interrupt event with the cancelled reason' do
        script_stream(stall_after)
        interrupt = aborted_turn_events.find { |event| event.is_a?(Riffer::StreamEvents::Interrupt) }

        assert_equal :cancelled, interrupt.reason
      end

      it 'answers an aborted ask with the partial reply' do
        script_stream(stall_after('one '))

        assert_equal 'one ', aborted_ask.content
      end

      it 'reports an aborted ask as interrupted with the cancelled detail' do
        script_stream(stall_after('one '))
        outcome = aborted_ask.outcome

        assert_equal [:interrupted, 'cancelled'], [outcome.reason, outcome.detail]
      end

      it 'ends a turn waiting on its first token with the cancelled stop reason' do
        script_stream(stall_after)

        assert_equal :cancelled, aborted_turn_events.last.stop_reason
      end

      it 'prompts again after an aborted turn' do
        script_stream(stall_after('one '))
        aborted_turn_events

        assert_equal :completed, @stalling.ask('again').outcome.reason
      end
    end

    it 'leaves a background job running to its own exit' do
      runtime = Riffer::Rig::Runtime.new('mock/test', extensions: [@extension])
      exits = job_exits(runtime)
      spawn_group_job(runtime, 'sleep 0.2')
      runtime.cancel
      exited = exits.pop(timeout: 5)
      runtime.close

      assert_equal 0, exited&.exit_status
    end

    it 'returns nil' do
      assert_nil @runtime.cancel
    end

    it 'is a no-op when idle' do
      @release.close
      @runtime.cancel

      assert_equal :completed, @runtime.ask('go').outcome.reason
    end
  end

  describe '#tally' do
    before do
      @riffer_config = Riffer.config
      # Riffer's providers price usage from the global Riffer.config, so the
      # tests swap in a fresh one rather than leak the catalog into other tests.
      Riffer.instance_variable_set(:@config, Riffer::Config.new)
      Riffer.config.catalog_files = [catalog_file]
    end

    after do
      FileUtils.remove_entry(File.dirname(catalog_file))
      Riffer.instance_variable_set(:@config, @riffer_config)
    end

    def catalog_file
      @catalog_file ||= begin
        path = File.join(Dir.mktmpdir, 'catalog.json')
        File.write(
          path,
          JSON.generate(
            version: 1,
            models: { 'mock/test' => { pricing: { input: 3.0, output: 15.0, cache_write: 3.75, cache_read: 0.3 } } }
          )
        )
        path
      end
    end

    def priced_runtime
      runtime = Riffer::Rig::Runtime.new('mock/test', extensions: [@extension])
      runtime.agent.provider.stub_response(
        'One.', token_usage: Riffer::Providers::TokenUsage.new(input_tokens: 1_000_000, output_tokens: 200_000)
      )
      runtime.agent.provider.stub_response(
        'Two.',
        token_usage: Riffer::Providers::TokenUsage.new(
          input_tokens: 2_000_000, output_tokens: 100_000, cache_write_tokens: 500_000, cache_read_tokens: 1_000_000
        )
      )
      runtime
    end

    it 'is nil before the first turn' do
      assert_nil priced_runtime.tally
    end

    it 'sums usage across turns' do
      runtime = priced_runtime
      runtime.ask('hello')
      runtime.prompt('again') { |event| event }

      assert_equal(
        { input_tokens: 3_000_000, output_tokens: 300_000, cache_write_tokens: 500_000, cache_read_tokens: 1_000_000 },
        runtime.tally.to_h.except(:cost)
      )
    end
  end

  describe '#close' do
    it 'kills and reaps outstanding background jobs on close' do
      runtime = Riffer::Rig::Runtime.new('mock/test', extensions: [@extension])
      job = spawn_group_job(runtime)
      runtime.close

      assert_raises(Errno::ECHILD) { Process.wait(job.pid) }
    end

    it 'leaves no watcher thread on close' do
      runtime = Riffer::Rig::Runtime.new('mock/test', extensions: [@extension])
      threads = Thread.list
      spawn_group_job(runtime)
      runtime.close

      assert_empty Thread.list - threads
    end

    it 'unregisters every server on close' do
      registry = recording_mcp_registry
      runtime = Riffer::Rig::Runtime.new('mock/test', extensions: [serving_mcp('web', 'alt')], mcp_registry: registry)
      runtime.close

      assert_empty registry.registered
    end

    it 'fires session_end with the close reason' do
      events = []
      hooks = Riffer::Rig::Extension.new('hooks') { |rig| rig.on(:session_end) { |e| events << e } }
      runtime = Riffer::Rig::Runtime.new('mock/test', extensions: [hooks])
      runtime.agent.provider.stub_response('All done.')
      runtime.ask('go')
      runtime.close
      runtime.close

      assert_equal [Riffer::Rig::Events::SessionEnd.new(:close)], events
    end

    it 'skips session_end for a session that never started' do
      events = []
      hooks = Riffer::Rig::Extension.new('hooks') { |rig| rig.on(:session_end) { |e| events << e } }
      runtime = Riffer::Rig::Runtime.new('mock/test', extensions: [hooks])
      runtime.close

      assert_empty events
    end
  end
end
