# frozen_string_literal: true

require 'test_helper'

describe 'Riffer::Rig::Bundled::Mcp' do
  def registered(settings)
    registrar = Riffer::Rig::Registrar.new('mcp', settings)
    Riffer::Rig::Bundled::Mcp.run(registrar)
    registrar
  end

  it 'is named mcp' do
    assert_equal 'mcp', Riffer::Rig::Bundled::Mcp.name
  end

  it 'declares every server under servers' do
    settings = { servers: { docs: { url: 'https://docs.example/mcp' }, web: { url: 'https://web.example/mcp' } } }

    assert_equal %w[docs web], registered(settings).mcp_servers.keys
  end

  it 'passes the url and headers with string header names' do
    settings = { servers: { web: { url: 'https://web.example/mcp', headers: { 'X-Token': 't' } } } }

    assert_equal(
      Riffer::Rig::Mcp::Declaration.new(url: 'https://web.example/mcp', headers: { 'X-Token' => 't' }),
      registered(settings).mcp_servers.fetch('web')
    )
  end

  it 'gives a server without headers none' do
    assert_empty registered({ servers: { web: { url: 'https://web.example/mcp' } } }).mcp_servers.fetch('web').headers
  end

  it 'declares nothing without servers' do
    assert_empty registered({}).mcp_servers
  end

  it 'fails to load a server without a url' do
    assert_raises(KeyError) { registered({ servers: { docs: { headers: {} } } }) }
  end
end
