# frozen_string_literal: true

require 'test_helper'

describe Riffer::Rig::Extension do
  it 'records the block against a registrar' do
    recorded = nil
    extension = Riffer::Rig::Extension.new('git') { |rig| recorded = rig }
    registrar = Riffer::Rig::Registrar.new('git')

    extension.run(registrar)

    assert_same registrar, recorded
  end

  it 'parses requires into a requirement' do
    extension = Riffer::Rig::Extension.new('git', requires: '>= 0.1')

    assert_equal Gem::Requirement.new('>= 0.1'), extension.requires
  end

  it 'records an unmet requirement as a mismatch' do
    extension = Riffer::Rig::Extension.new('git', requires: '>= 99')

    assert_instance_of Riffer::Rig::Extension::RequirementError, extension.mismatch
  end

  it 'names the requirement and the version in the mismatch' do
    extension = Riffer::Rig::Extension.new('git', requires: '>= 99')

    assert_equal "extension git requires riffer-rig >= 99, found #{Riffer::Rig::VERSION}", extension.mismatch.message
  end

  it 'has no mismatch when the requirement is met' do
    extension = Riffer::Rig::Extension.new('git', requires: "= #{Riffer::Rig::VERSION}")

    assert_nil extension.mismatch
  end

  it 'has no mismatch without a requirement' do
    assert_nil Riffer::Rig::Extension.new('git').mismatch
  end
end
