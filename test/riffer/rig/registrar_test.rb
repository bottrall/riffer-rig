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
end
