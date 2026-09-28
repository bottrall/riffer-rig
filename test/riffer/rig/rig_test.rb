# frozen_string_literal: true

require 'test_helper'

describe Riffer::Rig do
  def drop(name)
    Riffer::Rig.instance_variable_get(:@extensions).delete(name)
  end

  it 'records an extension in the registry' do
    extension = Riffer::Rig.extension('test_record') { |rig| rig }

    assert_same extension, Riffer::Rig.extensions['test_record']
  ensure
    drop('test_record')
  end

  it 'replaces the extension when a name is re-recorded' do
    Riffer::Rig.extension('test_replace') { |rig| rig }
    second = Riffer::Rig.extension('test_replace') { |rig| rig }

    assert_same second, Riffer::Rig.extensions['test_replace']
  ensure
    drop('test_replace')
  end

  it 'records an extension whose requires is unmet' do
    extension = Riffer::Rig.extension('test_mismatch', requires: '>= 99.0') { |rig| rig }

    assert_same extension, Riffer::Rig.extensions['test_mismatch']
  ensure
    drop('test_mismatch')
  end

  it 'returns the bundled extensions in load order' do
    assert_equal %w[read write edit bash agents_md skills], Riffer::Rig.bundled.map(&:name)
  end

  it 'returns one bundled extension by name' do
    assert_same Riffer::Rig::Bundled::Bash, Riffer::Rig.bundled(:bash)
  end
end
