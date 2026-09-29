# frozen_string_literal: true

require 'test_helper'

describe Riffer::Rig::Mcp do
  it 'keeps a home server the project does not name' do
    home = { servers: { docs: { url: 'https://docs.example/mcp' } } }
    project = { servers: { web: { url: 'https://web.example/mcp' } } }

    assert_equal %i[docs web], Riffer::Rig::Mcp.merge(home, project)[:servers].keys
  end

  it 'lets the project replace a home server of the same name whole' do
    home = { servers: { docs: { url: 'https://docs.example/mcp', headers: { 'X-Token': 'home' } } } }
    project = { servers: { docs: { url: 'https://project.example/mcp' } } }

    assert_equal({ url: 'https://project.example/mcp' }, Riffer::Rig::Mcp.merge(home, project)[:servers][:docs])
  end

  it 'takes the servers of whichever scope has them' do
    home = { servers: { docs: { url: 'https://docs.example/mcp' } } }

    assert_equal home, Riffer::Rig::Mcp.merge(home, {})
  end
end
