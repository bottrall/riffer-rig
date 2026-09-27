# frozen_string_literal: true

require 'test_helper'

describe Riffer::Rig::Runtime::Handlers do
  def handlers_for(host = Riffer::Rig::Hosts::Mirror.new(Riffer::Rig::Hosts::Null.new), **registered)
    all = Riffer::Rig::Registrar::EVENTS.to_h { |event| [event, registered.fetch(event, [])] }
    Riffer::Rig::Runtime::Handlers.new(all, host)
  end

  it 'passes the payload through with no handlers' do
    assert_equal({ command: 'ls' }, handlers_for.before_tool_call('bash', { command: 'ls' }))
  end

  it "feeds a handler's replacement to the next handler" do
    seen = nil
    handlers = handlers_for(
      before_tool_call: [
        ->(event) { event.args.merge(command: 'pwd') },
        ->(event) { seen = event.args[:command] }
      ]
    )
    handlers.before_tool_call('bash', { command: 'ls' })

    assert_equal 'pwd', seen
  end

  it 'returns the last replacement' do
    handlers = handlers_for(before_prompt: [->(event) { "#{event.text}!" }, ->(event) { "#{event.text}?" }])

    assert_equal 'hi!?', handlers.before_prompt('hi')
  end

  it 'ignores a return value of the wrong shape' do
    handlers = handlers_for(before_prompt: [->(_event) { 42 }])

    assert_equal 'hi', handlers.before_prompt('hi')
  end

  it 'blocks with the reason a handler gives' do
    handlers = handlers_for(before_tool_call: [->(_event) { [:block, 'no force pushes'] }])

    assert_equal 'no force pushes', handlers.before_tool_call('bash', { command: 'git push --force' }).reason
  end

  it 'blocks on a bare :block with a default reason' do
    handlers = handlers_for(before_tool_call: [->(_event) { :block }])

    assert_equal 'blocked by a before_tool_call handler', handlers.before_tool_call('bash', {}).reason
  end

  it 'stops at the first block' do
    later = false
    handlers = handlers_for(before_tool_call: [->(_event) { :block }, ->(_event) { later = true }])
    handlers.before_tool_call('bash', {})

    refute later
  end

  it 'notifies the host when a prompt is blocked' do
    host = Riffer::Rig::Hosts::Mirror.new(Riffer::Rig::Hosts::Null.new)
    handlers_for(host, before_prompt: [->(_event) { [:block, 'not today'] }]).before_prompt('hi')

    assert_equal [Riffer::Rig::Events::Notify.new('not today', :warning)], host.drain
  end

  it 'leaves a blocked tool call to the caller' do
    host = Riffer::Rig::Hosts::Mirror.new(Riffer::Rig::Hosts::Null.new)
    handlers_for(host, before_tool_call: [->(_event) { :block }]).before_tool_call('bash', {})

    assert_empty host.drain
  end

  it 'counts a raising handler as no veto' do
    handlers = handlers_for(before_prompt: [->(_event) { raise 'boom' }])

    assert_equal 'hi', handlers.before_prompt('hi')
  end

  it 'reports a raising handler through notify' do
    host = Riffer::Rig::Hosts::Mirror.new(Riffer::Rig::Hosts::Null.new)
    handlers = handlers_for(host, turn_end: [->(_event) { raise 'boom' }])
    handlers.observe(:turn_end, Riffer::Rig::Events::TurnEnd.new(:completed, nil))

    assert_equal [Riffer::Rig::Events::Notify.new('turn_end handler failed: boom', :error)], host.drain
  end

  it 'runs the next handler after one raises' do
    ran = false
    handlers = handlers_for(stream: [->(_event) { raise 'boom' }, ->(_event) { ran = true }])
    handlers.observe(:stream, Riffer::StreamEvents::TextDelta.new('hi'))

    assert ran
  end
end
