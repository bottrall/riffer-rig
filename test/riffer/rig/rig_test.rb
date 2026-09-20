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

  it 'raises on a requires mismatch' do
    assert_raises(Riffer::ArgumentError) do
      Riffer::Rig.extension('test_mismatch', requires: '>= 99.0') { |rig| rig }
    end
  ensure
    drop('test_mismatch')
  end

  it 'names the requirement in the mismatch error' do
    Riffer::Rig.extension('test_mismatch', requires: '>= 99.0') { |rig| rig }
  rescue Riffer::ArgumentError => e
    assert_includes e.message, 'requires riffer-rig >= 99.0'
  else
    flunk 'expected Riffer::ArgumentError'
  ensure
    drop('test_mismatch')
  end
end
