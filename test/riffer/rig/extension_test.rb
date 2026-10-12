# frozen_string_literal: true

require 'test_helper'

describe Riffer::Rig::Extension do
  it 'parses requires into a requirement' do
    extension = Riffer::Rig::Extension.new('git', requires: '>= 0.1')

    assert_equal Gem::Requirement.new('>= 0.1'), extension.requires
  end

  it 'has no requirement without requires' do
    assert_nil Riffer::Rig::Extension.new('git').requires
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

  it 'records the block against a registrar' do
    recorded = nil
    extension = Riffer::Rig::Extension.new('git') { |rig| recorded = rig }
    registrar = Riffer::Rig::Registrar.new('git')

    extension.run(registrar)

    assert_same registrar, recorded
  end

  describe '#trial' do
    it 'returns the mismatch of an unmet requirement' do
      extension = Riffer::Rig::Extension.new('git', requires: '>= 99') { |_rig| nil }

      assert_same extension.mismatch, extension.trial({})
    end

    it 'leaves the block of an unmet requirement unrun' do
      ran = false
      Riffer::Rig::Extension.new('git', requires: '>= 99') { |_rig| ran = true }.trial({})

      refute ran
    end

    it 'returns the collision of a name that is a core settings key' do
      extension = Riffer::Rig::Extension.new('model') { |_rig| nil }

      assert_instance_of Riffer::Rig::Registrar::NameCollisionError, extension.trial({})
    end

    it 'returns the registrar the block ran against' do
      recorded = nil
      registrar = Riffer::Rig::Extension.new('git') { |rig| recorded = rig }.trial({})

      assert_same registrar, recorded
    end

    it "hands the registrar the extension's settings namespace" do
      extension = Riffer::Rig::Extension.new('git') { |_rig| nil }

      assert_equal({ depth: 3 }, extension.trial({ git: { depth: 3 }, other: { depth: 9 } }).settings)
    end

    it 'hands the registrar empty settings when the namespace is absent' do
      extension = Riffer::Rig::Extension.new('git') { |_rig| nil }

      assert_equal({}, extension.trial({ other: { depth: 9 } }).settings)
    end

    it 'returns the error a raising block raised' do
      extension = Riffer::Rig::Extension.new('git') { |_rig| raise 'boom' }

      assert_equal 'boom', extension.trial({}).message
    end
  end
end
