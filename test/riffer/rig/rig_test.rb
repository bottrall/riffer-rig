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

  it 'returns no credentials outside a prompt' do
    assert_nil Riffer::Rig.credentials(:anthropic)
  end

  it 'returns the current Runtime credentials inside a prompt' do
    runtime = Riffer::Rig::Runtime.new('mock/test', credentials: { anthropic: { api_key: 'sk-ant-test' } })
    runtime.agent.provider.stub_response('All done.')
    values = nil
    runtime.prompt('hello') { values = Riffer::Rig.credentials(:anthropic) }

    assert_equal({ api_key: 'sk-ant-test' }, values)
  end

  it 'returns no credentials for a provider the current Runtime holds none for' do
    runtime = Riffer::Rig::Runtime.new('mock/test', credentials: { anthropic: { api_key: 'sk-ant-test' } })
    runtime.agent.provider.stub_response('All done.')
    values = :unset
    runtime.prompt('hello') { values = Riffer::Rig.credentials(:openai) }

    assert_nil values
  end
end
