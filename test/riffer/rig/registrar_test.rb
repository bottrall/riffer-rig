# frozen_string_literal: true

require 'test_helper'

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

    assert_equal 'git', registrar.commands['log'].extension
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

  it 'collects declared settings with their defaults' do
    registrar = Riffer::Rig::Registrar.new('git')
    registrar.setting(:depth, default: 3)
    registrar.setting(:remote, default: 'origin')

    assert_equal({ depth: 3, remote: 'origin' }, registrar.settings)
  end

  it 'returns a fresh hash from settings' do
    registrar = Riffer::Rig::Registrar.new('git')
    registrar.setting(:depth, default: 3)
    registrar.settings.clear

    assert_equal({ depth: 3 }, registrar.settings)
  end

  it 'finds no collision for an extension name outside the core keys' do
    assert_nil Riffer::Rig::Registrar.new('git').collision
  end

  it 'rejects an extension named after a core settings key' do
    assert_equal 'extension name mcp collides with a core settings key',
                 Riffer::Rig::Registrar.new('mcp').collision.message
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
end
