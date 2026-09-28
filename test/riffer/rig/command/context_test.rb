# frozen_string_literal: true

require 'test_helper'

describe Riffer::Rig::Command::Context do
  before do
    @emitted = []
    @turns = []
    @capable = Class.new(Riffer::Rig::Hosts::Null) do
      define_method(:capabilities) { Set[:ask, :confirm].freeze }
      define_method(:ask) do |question = nil, options: nil, secret: false|
        "#{question}|#{options&.join(',')}|#{secret}"
      end
      define_method(:confirm) { |_question = nil| true }
    end.new
  end

  def context(host: Riffer::Rig::Hosts::Null.new)
    Riffer::Rig::Command::Context.new(
      'log',
      '-n 3',
      runtime: nil,
      host: host,
      settings: { depth: 3 },
      emit: ->(event) { @emitted << event },
      turn: ->(text) { @turns << text }
    )
  end

  it 'reads the args' do
    assert_equal '-n 3', context.args
  end

  it 'reads the settings' do
    assert_equal({ depth: 3 }, context.settings)
  end

  it 'emits a command_output event from say' do
    context.say('three commits')

    assert_equal [Riffer::Rig::Events::CommandOutput.new('log', 'three commits')], @emitted
  end

  it 'returns nil from say' do
    assert_nil context.say('three commits')
  end

  it 'emits an event' do
    context.emit(Riffer::Rig::Events::SkillActivated.new('review'))

    assert_equal [Riffer::Rig::Events::SkillActivated.new('review')], @emitted
  end

  it 'returns nil from emit' do
    assert_nil context.emit(Riffer::Rig::Events::SkillActivated.new('review'))
  end

  it 'sends a user turn from prompt' do
    context.prompt('Review this diff')

    assert_equal ['Review this diff'], @turns
  end

  it 'returns nil from prompt' do
    assert_nil context.prompt('Review this diff')
  end

  it 'returns nil from ask when the host declines it' do
    assert_nil context.ask('Which branch?')
  end

  it 'forwards ask to a host that supports it' do
    assert_equal 'Which branch?|main,dev|true',
                 context(host: @capable).ask('Which branch?', options: %w[main dev], secret: true)
  end

  it 'returns false from confirm when the host declines it' do
    refute context.confirm('Push?')
  end

  it 'forwards confirm to a host that supports it' do
    assert context(host: @capable).confirm('Push?')
  end
end
