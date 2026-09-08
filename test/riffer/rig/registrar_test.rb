# frozen_string_literal: true

require 'test_helper'

class Riffer::Rig::RegistrarTest < Minitest::Test
  def test_collects_tools_in_registration_order
    registrar = Riffer::Rig::Registrar.new
    registrar.tool(Riffer::Rig::Tools::Read)
    registrar.tool(Riffer::Rig::Tools::Bash)

    assert_equal [Riffer::Rig::Tools::Read, Riffer::Rig::Tools::Bash], registrar.tools
  end

  def test_tools_returns_a_fresh_array
    registrar = Riffer::Rig::Registrar.new
    registrar.tool(Riffer::Rig::Tools::Read)
    registrar.tools << Riffer::Rig::Tools::Bash

    assert_equal [Riffer::Rig::Tools::Read], registrar.tools
  end
end
