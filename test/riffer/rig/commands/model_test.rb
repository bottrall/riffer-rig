# frozen_string_literal: true

require 'test_helper'

describe Riffer::Rig::Commands::Model do
  def command_events(runtime, args)
    events = []
    runtime.run_command('model', args) { |event| events << event }
    events
  end

  def output(text)
    Riffer::Rig::Events::CommandOutput.new('model', text)
  end

  it 'is listed in the Runtime commands' do
    assert_includes Riffer::Rig::Runtime.new('mock/test').commands.map(&:name), 'model'
  end

  it 'switches the Runtime model' do
    runtime = Riffer::Rig::Runtime.new('mock/test')
    command_events(runtime, 'mock/other')

    assert_equal 'mock/other', runtime.model
  end

  it 'reports the new model' do
    assert_equal [output('Model: mock/other')], command_events(Riffer::Rig::Runtime.new('mock/test'), 'mock/other')
  end

  it 'reports the current model without arguments' do
    assert_equal [output('Model: mock/test')], command_events(Riffer::Rig::Runtime.new('mock/test'), '')
  end

  it 'sends the next request to the new model' do
    runtime = Riffer::Rig::Runtime.new('mock/test')
    command_events(runtime, 'mock/other')
    runtime.agent.provider.stub_response('All done.')
    runtime.ask('hello')

    assert_equal 'other', runtime.agent.provider.calls.last[:model]
  end

  it 'keeps the conversation history' do
    runtime = Riffer::Rig::Runtime.new('mock/test')
    runtime.agent.provider.stub_response('First.')
    runtime.ask('hello')
    command_events(runtime, 'mock/other')
    runtime.agent.provider.stub_response('Second.')
    runtime.ask('again')

    assert_equal(
      %w[hello First. again],
      runtime.agent.provider.calls.last[:messages].drop(1).map { |message| message[:content] }
    )
  end

  it 'keeps the tally' do
    runtime = Riffer::Rig::Runtime.new('mock/test')
    runtime.agent.provider.stub_response(
      'First.', token_usage: Riffer::Providers::TokenUsage.new(input_tokens: 10, output_tokens: 5)
    )
    runtime.ask('hello')
    command_events(runtime, 'mock/other')

    assert_equal 10, runtime.tally.input_tokens
  end

  it 'rejects a bare name with the providers in the command output' do
    assert_equal(
      [output(
        'Use /model provider/name, with a provider from: ' \
        'amazon_bedrock, anthropic, azure_openai, gemini, openai, openrouter'
      )],
      command_events(Riffer::Rig::Runtime.new('mock/test'), 'sonnet')
    )
  end

  it 'keeps the model after rejecting a bare name' do
    runtime = Riffer::Rig::Runtime.new('mock/test')
    command_events(runtime, 'sonnet')

    assert_equal 'mock/test', runtime.model
  end

  it 'rejects an unknown provider with the providers in the command output' do
    assert_equal(
      [output(
        'Use /model provider/name, with a provider from: ' \
        'amazon_bedrock, anthropic, azure_openai, gemini, openai, openrouter'
      )],
      command_events(Riffer::Rig::Runtime.new('mock/test'), 'acme/fast')
    )
  end

  it 'refuses a provider without credentials through notify' do
    assert_equal(
      [Riffer::Rig::Events::Notify.new(
        'Not switching to anthropic/claude-sonnet-4-6: anthropic has no api_key in credentials', :error
      )],
      command_events(Riffer::Rig::Runtime.new('mock/test'), 'anthropic/claude-sonnet-4-6')
    )
  end

  it 'keeps the model after refusing a provider without credentials' do
    runtime = Riffer::Rig::Runtime.new('mock/test')
    command_events(runtime, 'anthropic/claude-sonnet-4-6')

    assert_equal 'mock/test', runtime.model
  end

  it 'refuses a provider missing a required credential field' do
    runtime = Riffer::Rig::Runtime.new('mock/test', credentials: { azure_openai: { api_key: 'key' } })

    assert_equal 'Not switching to azure_openai/gpt-5: azure_openai has no endpoint in credentials',
                 command_events(runtime, 'azure_openai/gpt-5').first.message
  end

  it 'rejects --save as not available in this host' do
    assert_equal [Riffer::Rig::Events::Notify.new('/model --save is not available in this host', :error)],
                 command_events(Riffer::Rig::Runtime.new('mock/test'), 'mock/other --save')
  end

  it 'keeps the model after rejecting --save' do
    runtime = Riffer::Rig::Runtime.new('mock/test')
    command_events(runtime, 'mock/other --save')

    assert_equal 'mock/test', runtime.model
  end
end
