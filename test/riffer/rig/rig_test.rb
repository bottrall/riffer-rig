# frozen_string_literal: true

require 'test_helper'

class Riffer::RigTest < Minitest::Test
  def test_extension_records_an_extension_in_the_registry
    extension = Riffer::Rig.extension('test_record') { |rig| rig }

    assert_same extension, Riffer::Rig.extensions['test_record']
  ensure
    Riffer::Rig.instance_variable_get(:@extensions).delete('test_record')
  end

  def test_re_recording_a_name_replaces_the_extension
    Riffer::Rig.extension('test_replace') { |rig| rig }
    second = Riffer::Rig.extension('test_replace') { |rig| rig }

    assert_same second, Riffer::Rig.extensions['test_replace']
  ensure
    Riffer::Rig.instance_variable_get(:@extensions).delete('test_replace')
  end

  def test_requires_mismatch_raises_a_load_error
    assert_raises(Riffer::ArgumentError) do
      Riffer::Rig.extension('test_mismatch', requires: '>= 99.0') { |rig| rig }
    end
  ensure
    Riffer::Rig.instance_variable_get(:@extensions).delete('test_mismatch')
  end

  def test_requires_mismatch_names_the_requirement
    Riffer::Rig.extension('test_mismatch', requires: '>= 99.0') { |rig| rig }
  rescue Riffer::ArgumentError => e
    assert_includes e.message, 'requires riffer-rig >= 99.0'
  else
    flunk 'expected Riffer::ArgumentError'
  ensure
    Riffer::Rig.instance_variable_get(:@extensions).delete('test_mismatch')
  end
end
