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

    it 'replaces a home MCP server of the same name whole' do
      home = { mcp: { servers: { docs: { url: 'https://home.test', headers: { Authorization: 'secret' } } } } }
      project = { mcp: { servers: { docs: { url: 'https://project.test' } } } }

      assert_equal(
        { url: 'https://project.test' },
        Riffer::Rig::Settings.merge(home, project).dig(:mcp, :servers, :docs)
      )
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
  end
end
