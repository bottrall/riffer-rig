# frozen_string_literal: true

require 'test_helper'
class AcmeSeamProvider < Riffer::Providers::Mock; end # rubocop:disable Rig/NoInheritance -- riffer builds providers through Riffer::Providers::Base subclasses

describe Riffer::Rig::Registrar do
  it 'collects tools in registration order' do
    registrar = Riffer::Rig::Registrar.new('git')
    registrar.tool(Riffer::Rig::Tools::Read)
    registrar.tool(Riffer::Rig::Tools::Bash)

    assert_equal [Riffer::Rig::Tools::Read, Riffer::Rig::Tools::Bash], registrar.tools.values
  end

  it 'keys tools by their identifier' do
    registrar = Riffer::Rig::Registrar.new('git')
    registrar.tool(Riffer::Rig::Tools::Read)

    assert_equal %w[read], registrar.tools.keys
  end

  it 'replaces a tool registered again under the same identifier' do
    registrar = Riffer::Rig::Registrar.new('git')
    later = Class.new(Riffer::Tool) { identifier 'read' }
    registrar.tool(Riffer::Rig::Tools::Read)
    registrar.tool(later)

    assert_equal({ 'read' => later }, registrar.tools)
  end

  it 'returns a fresh hash from tools' do
    registrar = Riffer::Rig::Registrar.new('git')
    registrar.tool(Riffer::Rig::Tools::Read)
    registrar.tools.clear

    assert_equal %w[read], registrar.tools.keys
  end

  it 'collects prompt sections in registration order' do
    registrar = Riffer::Rig::Registrar.new('git')
    registrar.prompt(:first) { 'one' }
    registrar.prompt(:second) { 'two' }

    assert_equal %i[first second], registrar.prompts.keys
  end

  it 'replaces a prompt section registered again under the same name' do
    registrar = Riffer::Rig::Registrar.new('git')
    registrar.prompt(:branch) { 'earlier' }
    later = proc { 'later' }
    registrar.prompt(:branch, &later)

    assert_equal({ branch: later }, registrar.prompts)
  end

  it 'returns a fresh hash from prompts' do
    registrar = Riffer::Rig::Registrar.new('git')
    registrar.prompt(:branch) { 'main' }
    registrar.prompts.clear

    assert_equal %i[branch], registrar.prompts.keys
  end

  it 'collects skills sources in registration order' do
    registrar = Riffer::Rig::Registrar.new('git')
    first = proc { Riffer::Skills::FilesystemBackend.new('/one') }
    second = proc { Riffer::Skills::FilesystemBackend.new('/two') }
    registrar.skills(&first)
    registrar.skills(&second)

    assert_equal [first, second], registrar.skill_sources
  end

  it 'returns a fresh array from skill_sources' do
    registrar = Riffer::Rig::Registrar.new('git')
    registrar.skills { Riffer::Skills::FilesystemBackend.new('/one') }
    registrar.skill_sources.clear

    assert_equal 1, registrar.skill_sources.length
  end

  it 'collects commands in registration order' do
    registrar = Riffer::Rig::Registrar.new('git')
    registrar.command('log', description: 'Recent commits') { |_ctx| nil }
    registrar.command('review', description: 'Review the diff') { |_ctx| nil }

    assert_equal %w[log review], registrar.commands.keys
  end

  it 'builds a command with its description' do
    registrar = Riffer::Rig::Registrar.new('git')
    registrar.command('log', description: 'Recent commits') { |_ctx| nil }

    assert_equal 'Recent commits', registrar.commands['log'].description
  end

  it 'stamps a command with the extension it came from' do
    registrar = Riffer::Rig::Registrar.new('git')
    registrar.command('log', description: 'Recent commits') { |_ctx| nil }

    assert_equal :git, registrar.commands['log'].extension
  end

  it 'replaces a command registered again under the same name' do
    registrar = Riffer::Rig::Registrar.new('git')
    registrar.command('log', description: 'earlier') { |_ctx| nil }
    registrar.command('log', description: 'later') { |_ctx| nil }

    assert_equal %w[later], registrar.commands.values.map(&:description)
  end

  it 'returns a fresh hash from commands' do
    registrar = Riffer::Rig::Registrar.new('git')
    registrar.command('log', description: 'Recent commits') { |_ctx| nil }
    registrar.commands.clear

    assert_equal %w[log], registrar.commands.keys
  end

  it 'names the extension it collects for' do
    assert_equal 'git', Riffer::Rig::Registrar.new('git').extension
  end

  it 'lists every registration by kind and name' do
    registrar = Riffer::Rig::Registrar.new('git')
    registrar.tool(Riffer::Rig::Tools::Bash)
    registrar.prompt(:branch) { 'main' }
    registrar.command('log', description: 'Recent commits') { |_ctx| nil }

    assert_equal ['tool bash', 'prompt section branch', 'command log'], registrar.registrations
  end

  it 'lists a declared MCP server among the registrations' do
    registrar = Riffer::Rig::Registrar.new('docs')
    registrar.mcp('docs', url: 'https://docs.example/mcp')

    assert_equal ['MCP server docs'], registrar.registrations
  end

  it 'collects declared settings with their defaults' do
    registrar = Riffer::Rig::Registrar.new('git')
    registrar.setting(:depth, default: 3)
    registrar.setting(:remote, default: 'origin')

    assert_equal({ depth: 3, remote: 'origin' }, registrar.declared_settings)
  end

  it 'returns a fresh hash from declared_settings' do
    registrar = Riffer::Rig::Registrar.new('git')
    registrar.setting(:depth, default: 3)
    registrar.declared_settings.clear

    assert_equal({ depth: 3 }, registrar.declared_settings)
  end

  it 'reads the given settings namespace over the declared defaults' do
    registrar = Riffer::Rig::Registrar.new('git', { depth: 10 })
    registrar.setting(:depth, default: 3)
    registrar.setting(:remote, default: 'origin')

    assert_equal({ depth: 10, remote: 'origin' }, registrar.settings)
  end

  it 'collects MCP servers by name' do
    registrar = Riffer::Rig::Registrar.new('docs')
    registrar.mcp('docs', url: 'https://docs.example/mcp', headers: { 'Authorization' => 'Bearer t' })

    assert_equal(
      {
        'docs' => Riffer::Rig::Mcp::Declaration.new(
          url: 'https://docs.example/mcp', headers: { 'Authorization' => 'Bearer t' }
        )
      },
      registrar.mcp_servers
    )
  end

  it 'gives an MCP server no headers by default' do
    registrar = Riffer::Rig::Registrar.new('docs')
    registrar.mcp('docs', url: 'https://docs.example/mcp')

    assert_empty registrar.mcp_servers.fetch('docs').headers
  end

  it 'gives an MCP server no auth by default' do
    registrar = Riffer::Rig::Registrar.new('docs')
    registrar.mcp('docs', url: 'https://docs.example/mcp')

    assert_empty registrar.mcp_servers.fetch('docs').auth
  end

  it 'collects the auth block with each env name wrapped' do
    registrar = Riffer::Rig::Registrar.new('docs')
    registrar.mcp('docs', url: 'https://docs.example/mcp', auth: { api_key: 'DOCS_API_KEY' })

    assert_equal({ api_key: ['DOCS_API_KEY'] }, registrar.mcp_servers.fetch('docs').auth)
  end

  it 'keeps an auth block already given as arrays of env names' do
    registrar = Riffer::Rig::Registrar.new('docs')
    registrar.mcp('docs', url: 'https://docs.example/mcp', auth: { api_key: %w[DOCS_API_KEY DOCS_TOKEN] })

    assert_equal({ api_key: %w[DOCS_API_KEY DOCS_TOKEN] }, registrar.mcp_servers.fetch('docs').auth)
  end

  it 'lets a later declaration of an MCP server replace the earlier one' do
    registrar = Riffer::Rig::Registrar.new('docs')
    registrar.mcp('docs', url: 'https://docs.example/mcp')
    registrar.mcp('docs', url: 'https://other.example/mcp')

    assert_equal 'https://other.example/mcp', registrar.mcp_servers.fetch('docs').url
  end

  it 'declares a stdio MCP server from its command' do
    registrar = Riffer::Rig::Registrar.new('docs')
    registrar.mcp('local', command: 'echo', args: ['--flag'], env: { 'TOKEN' => 't' })

    assert_equal(
      Riffer::Rig::Mcp::Declaration.new(command: 'echo', args: ['--flag'], env: { 'TOKEN' => 't' }),
      registrar.mcp_servers.fetch('local')
    )
  end

  it 'refuses an MCP declaration with neither a url nor a command' do
    registrar = Riffer::Rig::Registrar.new('docs')

    assert_raises(ArgumentError) { registrar.mcp('local') }
  end

  it 'refuses an MCP declaration with both a url and a command' do
    registrar = Riffer::Rig::Registrar.new('docs')

    assert_raises(ArgumentError) { registrar.mcp('local', url: 'https://docs.example/mcp', command: 'echo') }
  end

  it 'finds no collision for an extension name outside the core keys' do
    assert_nil Riffer::Rig::Registrar.new('git').collision
  end

  it 'rejects an extension named after a core settings key' do
    assert_equal 'extension name model collides with a core settings key',
                 Riffer::Rig::Registrar.new('model').collision.message
  end

  it 'collects hooks per event in registration order' do
    registrar = Riffer::Rig::Registrar.new('git')
    first = proc { :first }
    second = proc { :second }
    registrar.on(:before_tool_call, &first)
    registrar.on(:before_tool_call, &second)

    assert_equal [first, second], registrar.hooks[:before_tool_call]
  end

  it 'starts every event with no hooks' do
    assert_equal Riffer::Rig::Registrar::EVENTS.to_h { |event| [event, []] }, Riffer::Rig::Registrar.new('git').hooks
  end

  it 'rejects an unknown event' do
    registrar = Riffer::Rig::Registrar.new('git')

    assert_raises(Riffer::ArgumentError) { registrar.on(:before_everything) { nil } }
  end

  it 'returns fresh arrays from hooks' do
    registrar = Riffer::Rig::Registrar.new('git')
    registrar.on(:stream) { nil }
    registrar.hooks[:stream].clear

    assert_equal 1, registrar.hooks[:stream].length
  end

  describe 'provider' do
    after do
      Riffer::Rig::Providers.unregister(:acme)
    end

    it 'registers the class process-wide with riffer\'s repository' do
      Riffer::Rig::Registrar.new('acme').provider(:acme) { AcmeSeamProvider }

      assert_same AcmeSeamProvider, Riffer::Providers::Repository.find(:acme)
    end

    it 'keeps one entry when registered again' do
      registrar = Riffer::Rig::Registrar.new('acme')
      registrar.provider(:acme) { AcmeSeamProvider }
      registrar.provider(:acme) { AcmeSeamProvider }

      assert_same AcmeSeamProvider, Riffer::Providers::Repository.find(:acme)
    end

    it 'resolves a setup-less registration through the generic fallback' do
      Riffer::Rig::Registrar.new('acme').provider(:acme) { AcmeSeamProvider }

      assert_equal(
        [[:api_key, ['ACME_API_KEY']]],
        Riffer::Rig::ProviderSetup.for(:acme).fields.map do |field|
          [field.name, field.env]
        end
      )
    end

    it 'converts a setup hash into fields' do
      Riffer::Rig::Registrar.new('acme').provider(
        :acme,
        setup: {
          url: 'https://example.com/keys',
          fields: [{ name: :api_key, env: ['ACME_API_KEY'], secret: true, required: true }]
        }
      ) { AcmeSeamProvider }

      assert_equal(
        [[:api_key, ['ACME_API_KEY'], true, true]],
        Riffer::Rig::ProviderSetup.registered_setup(:acme).fields.map do |field|
          [field.name, field.env, field.secret, field.required]
        end
      )
    end

    it 'converts a setup hash\'s url' do
      Riffer::Rig::Registrar.new('acme').provider(
        :acme,
        setup: { url: 'https://example.com/keys', fields: [{ name: :api_key, env: ['ACME_API_KEY'] }] }
      ) { AcmeSeamProvider }

      assert_equal 'https://example.com/keys', Riffer::Rig::ProviderSetup.registered_setup(:acme).url
    end

    it 'freezes the converted setup' do
      Riffer::Rig::Registrar.new('acme').provider(
        :acme,
        setup: { fields: [{ name: :api_key, env: ['ACME_API_KEY'], secret: true, required: true }] }
      ) { AcmeSeamProvider }

      assert_predicate Riffer::Rig::ProviderSetup.registered_setup(:acme), :frozen?
    end

    it 'gives a registered provider no setup by default' do
      Riffer::Rig::Registrar.new('acme').provider(:acme) { AcmeSeamProvider }

      assert_nil Riffer::Rig::Providers.setup(:acme)
    end

    it 'gives two Runtimes the same registered prefix' do
      extension = Riffer::Rig.extension('acme') { |rig| rig.provider(:acme) { AcmeSeamProvider } }
      Riffer::Rig::Runtime.new('acme/first', extensions: [extension])
      second = Riffer::Rig::Runtime.new('acme/second', extensions: [extension])

      assert_instance_of AcmeSeamProvider, second.agent.provider
    end
  end
end
