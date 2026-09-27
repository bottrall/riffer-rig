# frozen_string_literal: true

require 'test_helper'

describe Riffer::Rig::Registrar do
  it 'collects tools in registration order' do
    registrar = Riffer::Rig::Registrar.new('git')
    registrar.tool(Riffer::Rig::Tools::Read)
    registrar.tool(Riffer::Rig::Tools::Bash)

    assert_equal [Riffer::Rig::Tools::Read, Riffer::Rig::Tools::Bash], registrar.tools
  end

  it 'returns a fresh array from tools' do
    registrar = Riffer::Rig::Registrar.new('git')
    registrar.tool(Riffer::Rig::Tools::Read)
    registrar.tools << Riffer::Rig::Tools::Bash

    assert_equal [Riffer::Rig::Tools::Read], registrar.tools
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
end
