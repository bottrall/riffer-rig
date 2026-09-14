# frozen_string_literal: true

require 'test_helper'

describe Riffer::Rig::Extension do
  it 'records the block against a registrar' do
    recorded = nil
    extension = Riffer::Rig::Extension.new('git') { |rig| recorded = rig }
    registrar = Riffer::Rig::Registrar.new

    extension.run(registrar)

    assert_same registrar, recorded
  end

  it 'parses requires into a requirement' do
    extension = Riffer::Rig::Extension.new('git', requires: '>= 0.1')

    assert_equal Gem::Requirement.new('>= 0.1'), extension.requires
  end
end
