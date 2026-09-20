# frozen_string_literal: true

require 'test_helper'

describe Riffer::Rig::Registrar do
  it 'collects tools in registration order' do
    registrar = Riffer::Rig::Registrar.new
    registrar.tool(Riffer::Rig::Tools::Read)
    registrar.tool(Riffer::Rig::Tools::Bash)

    assert_equal [Riffer::Rig::Tools::Read, Riffer::Rig::Tools::Bash], registrar.tools
  end

  it 'returns a fresh array from tools' do
    registrar = Riffer::Rig::Registrar.new
    registrar.tool(Riffer::Rig::Tools::Read)
    registrar.tools << Riffer::Rig::Tools::Bash

    assert_equal [Riffer::Rig::Tools::Read], registrar.tools
  end

  it 'collects prompt sections in registration order' do
    registrar = Riffer::Rig::Registrar.new
    registrar.prompt(:first) { 'one' }
    registrar.prompt(:second) { 'two' }

    assert_equal %i[first second], registrar.prompts.keys
  end

  it 'replaces a prompt section registered again under the same name' do
    registrar = Riffer::Rig::Registrar.new
    registrar.prompt(:branch) { 'earlier' }
    later = proc { 'later' }
    registrar.prompt(:branch, &later)

    assert_equal({ branch: later }, registrar.prompts)
  end

  it 'returns a fresh hash from prompts' do
    registrar = Riffer::Rig::Registrar.new
    registrar.prompt(:branch) { 'main' }
    registrar.prompts.clear

    assert_equal %i[branch], registrar.prompts.keys
  end
end
