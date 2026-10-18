# frozen_string_literal: true

require 'test_helper'

describe Riffer::Rig::Settings::Document do
  it 'ignores a model that is not a string' do
    assert_nil Riffer::Rig::Settings::Document.new({ model: 42 }).model
  end

  it 'reads the model' do
    assert_equal 'openai/o3', Riffer::Rig::Settings::Document.new({ model: 'openai/o3' }).model
  end

  it 'ignores a reasoning level that is not a string' do
    assert_nil Riffer::Rig::Settings::Document.new({ reasoning: 3 }).reasoning
  end

  it 'reads the reasoning level' do
    assert_equal 'high', Riffer::Rig::Settings::Document.new({ reasoning: 'high' }).reasoning
  end

  it 'has no catalog files when the value is not an array' do
    assert_empty Riffer::Rig::Settings::Document.new({ catalog_files: 'models.json' }).catalog_files
  end

  it 'has no catalog files when an entry is not a string' do
    assert_empty Riffer::Rig::Settings::Document.new({ catalog_files: ['models.json', 3] }).catalog_files
  end

  it 'reads the catalog file paths' do
    document = Riffer::Rig::Settings::Document.new({ catalog_files: ['~/.riffer/models.json'] })

    assert_equal ['~/.riffer/models.json'], document.catalog_files
  end

  it 'has no provider blocks when the providers block is not an object' do
    assert_empty Riffer::Rig::Settings::Document.new({ providers: 'azure_openai' }).providers
  end

  it 'ignores a provider block that is not an object' do
    assert_empty Riffer::Rig::Settings::Document.new({ providers: { azure_openai: 'https://azure.test' } }).providers
  end

  it 'drops provider fields that are not strings' do
    fields = { endpoint: 'https://azure.test', timeout: 30 }
    document = Riffer::Rig::Settings::Document.new({ providers: { azure_openai: fields } })

    assert_equal({ 'azure_openai' => { 'endpoint' => 'https://azure.test' } }, document.providers)
  end

  it 'keys the provider blocks by identifier and field name' do
    document = Riffer::Rig::Settings::Document.new({ providers: { azure_openai: { endpoint: 'https://azure.test' } } })

    assert_equal({ 'azure_openai' => { 'endpoint' => 'https://azure.test' } }, document.providers)
  end

  it 'reads the disabled extensions' do
    assert_equal %w[mcp], Riffer::Rig::Settings::Document.new({ extensions: { disabled: ['mcp', 3] } }).disabled
  end

  it 'has no disabled extensions when the list is not an array' do
    assert_empty Riffer::Rig::Settings::Document.new({ extensions: { disabled: 'mcp' } }).disabled
  end

  it 'reads the autoload flag' do
    assert Riffer::Rig::Settings::Document.new({ extensions: { autoload: true } }).autoload
  end

  it 'leaves autoload off unless it is exactly true' do
    refute Riffer::Rig::Settings::Document.new({ extensions: { autoload: 'yes' } }).autoload
  end

  it 'saves sessions by default' do
    assert Riffer::Rig::Settings::Document.new({}).save
  end

  it 'leaves the saving off when sessions.save is false' do
    refute Riffer::Rig::Settings::Document.new({ sessions: { save: false } }).save
  end

  it 'saves sessions when the sessions block is not an object' do
    assert Riffer::Rig::Settings::Document.new({ sessions: 'no' }).save
  end

  it 'has no autoload when the extensions block is not an object' do
    refute Riffer::Rig::Settings::Document.new({ extensions: true }).autoload
  end

  it 'reads the reload mode' do
    assert_equal :manual, Riffer::Rig::Settings::Document.new({ reload: 'manual' }).reload
  end

  it 'defaults the reload mode to auto' do
    assert_equal :auto, Riffer::Rig::Settings::Document.new({}).reload
  end

  it 'leaves the reload mode auto unless it is exactly manual' do
    assert_equal :auto, Riffer::Rig::Settings::Document.new({ reload: 'MANUAL' }).reload
  end

  it 'reads the native tool switches' do
    switches = { web_search: true, code_execution: false, junk: 'yes' }
    document = Riffer::Rig::Settings::Document.new({ tools: { native: switches } })

    assert_equal({ web_search: true }, document.native_tools)
  end

  it 'keeps a switch object' do
    document = Riffer::Rig::Settings::Document.new({ tools: { native: { web_search: { max_uses: 3 } } } })

    assert_equal({ web_search: { max_uses: 3 } }, document.native_tools)
  end

  it 'reads no switches when the tools block is not an object' do
    assert_empty Riffer::Rig::Settings::Document.new({ tools: 'web_search' }).native_tools
  end

  it 'is frozen' do
    assert_predicate Riffer::Rig::Settings::Document.new({}), :frozen?
  end
end
