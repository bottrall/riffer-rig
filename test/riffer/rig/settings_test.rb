# frozen_string_literal: true

require 'test_helper'

describe Riffer::Rig::Settings do
  describe '.merge' do
    it 'lets the project override home key by key' do
      merged = Riffer::Rig::Settings.merge({ model: 'anthropic/a', reasoning: 'low' }, { model: 'openai/b' })

      assert_equal({ model: 'openai/b', reasoning: 'low' }, merged)
    end

    it 'merges nested extension namespaces key by key' do
      merged = Riffer::Rig::Settings.merge({ git: { depth: 10, remote: 'origin' } }, { git: { depth: 3 } })

      assert_equal({ depth: 3, remote: 'origin' }, merged[:git])
    end

    it 'replaces a project value that is not a namespace whole' do
      merged = Riffer::Rig::Settings.merge({ git: { depth: 10 } }, { git: 'off' })

      assert_equal 'off', merged[:git]
    end

    it 'takes a project namespace whole over a home value that is not a namespace' do
      merged = Riffer::Rig::Settings.merge({ git: 'off' }, { git: { depth: 3 } })

      assert_equal({ depth: 3 }, merged[:git])
    end

    it 'keeps a home MCP server the project does not name' do
      home = { mcp: { servers: { docs: { url: 'https://docs.test' } } } }
      project = { mcp: { servers: { web: { url: 'https://web.test' } } } }

      assert_equal %i[docs web], Riffer::Rig::Settings.merge(home, project).dig(:mcp, :servers).keys
    end

    it 'keeps the home MCP servers when the project mcp table names none' do
      home = { mcp: { servers: { docs: { url: 'https://docs.test' } } } }

      assert_equal home[:mcp], Riffer::Rig::Settings.merge(home, { mcp: {} })[:mcp]
    end

    it 'replaces a home MCP server of the same name whole' do
      home = { mcp: { servers: { docs: { url: 'https://home.test', headers: { Authorization: 'secret' } } } } }
      project = { mcp: { servers: { docs: { url: 'https://project.test' } } } }

      assert_equal(
        { url: 'https://project.test' },
        Riffer::Rig::Settings.merge(home, project).dig(:mcp, :servers, :docs)
      )
    end

    it 'takes a project mcp value whole when it is not a server table' do
      merged = Riffer::Rig::Settings.merge({ mcp: { servers: { docs: { url: 'https://home.test' } } } }, { mcp: 'off' })

      assert_equal 'off', merged[:mcp]
    end

    it 'adds up the disabled lists of both scopes' do
      merged = Riffer::Rig::Settings.merge(
        { extensions: { disabled: %w[mcp] } },
        { extensions: { disabled: %w[skills mcp] } }
      )

      assert_equal %w[mcp skills], merged.dig(:extensions, :disabled)
    end

    it 'leaves the other extensions keys alone when adding up the disabled lists' do
      merged = Riffer::Rig::Settings.merge(
        { extensions: { disabled: %w[mcp], autoload: true } },
        { extensions: { disabled: %w[skills] } }
      )

      assert merged.dig(:extensions, :autoload)
    end

    it 'keeps the home disabled list when the project extensions is not a namespace' do
      merged = Riffer::Rig::Settings.merge({ extensions: { disabled: %w[mcp] } }, { extensions: 'off' })

      assert_equal %w[mcp], merged.dig(:extensions, :disabled)
    end

    it 'puts the home catalog files before the project ones' do
      merged = Riffer::Rig::Settings.merge(
        { catalog_files: ['~/.riffer/models.json'] },
        { catalog_files: ['.riffer/models.json'] }
      )

      assert_equal ['~/.riffer/models.json', '.riffer/models.json'], merged[:catalog_files]
    end

    it 'keeps the home catalog files when the project sets none' do
      merged = Riffer::Rig::Settings.merge({ catalog_files: ['~/.riffer/models.json'] }, {})

      assert_equal ['~/.riffer/models.json'], merged[:catalog_files]
    end

    it 'replaces a catalog files value that is not an array with the project one' do
      merged = Riffer::Rig::Settings.merge({ catalog_files: 'models.json' }, { catalog_files: ['.riffer/models.json'] })

      assert_equal ['.riffer/models.json'], merged[:catalog_files]
    end
  end
end
