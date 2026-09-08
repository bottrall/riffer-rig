# frozen_string_literal: true

require 'test_helper'

class Riffer::Rig::ExtensionTest < Minitest::Test
  def test_records_the_block_against_a_registrar
    recorded = nil
    extension = Riffer::Rig::Extension.new('git') { |rig| recorded = rig }
    registrar = Riffer::Rig::Registrar.new

    extension.run(registrar)

    assert_same registrar, recorded
  end

  def test_requires_is_parsed_into_a_requirement
    extension = Riffer::Rig::Extension.new('git', requires: '>= 0.1')

    assert_equal Gem::Requirement.new('>= 0.1'), extension.requires
  end
end
