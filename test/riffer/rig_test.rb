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

  it 'keeps the bundled extensions out of the registry' do
    bundled_names = Riffer::Rig.bundled.map(&:name)

    assert_empty Riffer::Rig.extensions.keys & bundled_names
  end

  it 'returns the credentials applied for an identifier' do
    Riffer::Rig::Credentials.apply(:test_rig_credentials, { key: 'secret' })

    assert_equal({ key: 'secret' }, Riffer::Rig.credentials(:test_rig_credentials))
  ensure
    Riffer::Rig::Credentials.instance_variable_get(:@applied).delete(:test_rig_credentials)
  end

  it 'returns every bundled extension when no name is given' do
    assert_equal Riffer::Rig::Bundled::BY_NAME.values, Riffer::Rig.bundled
  end

  it 'returns one bundled extension by name' do
    assert_same Riffer::Rig::Bundled::Bash, Riffer::Rig.bundled(:bash)
  end

  it 'raises for an unknown bundled name' do
    assert_raises(KeyError) { Riffer::Rig.bundled(:missing) }
  end
end
