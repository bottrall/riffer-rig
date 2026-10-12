# frozen_string_literal: true

require 'test_helper'

describe Riffer::Rig::Runtime::Hooks do
  def hooks_for(host = Riffer::Rig::Hosts::Mirror.new(Riffer::Rig::Hosts::Null.new), **registered)
    all = Riffer::Rig::Registrar::EVENTS.to_h { |event| [event, registered.fetch(event, [])] }
    Riffer::Rig::Runtime::Hooks.new(all, host)
  end

  it 'passes the payload through with no hooks' do
    assert_equal({ command: 'ls' }, hooks_for.before_tool_call('call_1', 'bash', { command: 'ls' }, 1.5))
  end

  it "feeds a hook's replacement to the next hook" do
    seen = nil
    hooks = hooks_for(
      before_tool_call: [
        ->(event) { event.args.merge(command: 'pwd') },
        ->(event) { seen = event.args[:command] }
      ]
    )
    hooks.before_tool_call('call_1', 'bash', { command: 'ls' }, 1.5)

    assert_equal 'pwd', seen
  end

  it 'returns the last replacement' do
    hooks = hooks_for(before_prompt: [->(event) { "#{event.text}!" }, ->(event) { "#{event.text}?" }])

    assert_equal 'hi!?', hooks.before_prompt('hi')
  end

  it 'ignores a return value of the wrong shape' do
    hooks = hooks_for(before_prompt: [->(_event) { 42 }])

    assert_equal 'hi', hooks.before_prompt('hi')
  end

  it 'accepts a replacement list of messages for a request' do
    replacement = [Riffer::Messages::User.new('hi'), Riffer::Messages::User.new('note')]
    hooks = hooks_for(before_request: [->(_event) { replacement }])

    assert_same replacement, hooks.before_request([Riffer::Messages::User.new('hi')])
  end

  it 'ignores a request replacement that holds anything but messages' do
    messages = [Riffer::Messages::User.new('hi')]
    hooks = hooks_for(before_request: [->(event) { [*event.messages, 'note'] }])

    assert_same messages, hooks.before_request(messages)
  end

  it 'blocks with the reason a hook gives' do
    hooks = hooks_for(before_tool_call: [->(_event) { [:block, 'no force pushes'] }])

    blocked = hooks.before_tool_call('call_1', 'bash', { command: 'git push --force' }, 1.5)

    assert_equal 'no force pushes', blocked.reason
  end

  it 'identifies and stamps the call on the event each hook receives' do
    seen = [] #: Array[Riffer::Rig::Events::_Event]
    probe = ->(event) { seen << event }
    hooks_for(before_tool_call: [probe, probe]).before_tool_call('call_1', 'bash', { command: 'ls' }, 1.5)

    assert_equal [Riffer::Rig::Events::BeforeToolCall.new('call_1', 'bash', { command: 'ls' }, 1.5)] * 2, seen
  end

  it 'blocks on a bare :block with a default reason' do
    hooks = hooks_for(before_tool_call: [->(_event) { :block }])

    assert_equal 'blocked by a before_tool_call hook', hooks.before_tool_call('call_1', 'bash', {}, 1.5).reason
  end

  it 'stops at the first block' do
    later = false
    hooks = hooks_for(before_tool_call: [->(_event) { :block }, ->(_event) { later = true }])
    hooks.before_tool_call('call_1', 'bash', {}, 1.5)

    refute later
  end

  it 'notifies the host when a prompt is blocked' do
    host = Riffer::Rig::Hosts::Mirror.new(Riffer::Rig::Hosts::Null.new)
    hooks_for(host, before_prompt: [->(_event) { [:block, 'not today'] }]).before_prompt('hi')

    assert_equal [Riffer::Rig::Events::Notify.new('not today', :warning)], host.drain
  end

  it 'notifies the host when a request is blocked' do
    host = Riffer::Rig::Hosts::Mirror.new(Riffer::Rig::Hosts::Null.new)
    hooks_for(host, before_request: [->(_event) { [:block, 'offline'] }]).before_request([])

    assert_equal [Riffer::Rig::Events::Notify.new('offline', :warning)], host.drain
  end

  it 'leaves a blocked tool call to the caller' do
    host = Riffer::Rig::Hosts::Mirror.new(Riffer::Rig::Hosts::Null.new)
    hooks_for(host, before_tool_call: [->(_event) { :block }]).before_tool_call('call_1', 'bash', {}, 1.5)

    assert_empty host.drain
  end

  it 'counts a raising hook as no veto' do
    hooks = hooks_for(before_prompt: [->(_event) { raise 'boom' }])

    assert_equal 'hi', hooks.before_prompt('hi')
  end

  it 'reports a raising hook through notify' do
    host = Riffer::Rig::Hosts::Mirror.new(Riffer::Rig::Hosts::Null.new)
    hooks = hooks_for(host, turn_end: [->(_event) { raise 'boom' }])
    hooks.observe(:turn_end, Riffer::Rig::Events::TurnEnd.new(:completed, nil))

    assert_equal [Riffer::Rig::Events::Notify.new('turn_end hook failed: boom', :error)], host.drain
  end

  it 'runs the next hook after one raises' do
    ran = false
    hooks = hooks_for(stream: [->(_event) { raise 'boom' }, ->(_event) { ran = true }])
    hooks.observe(:stream, Riffer::StreamEvents::TextDelta.new('hi'))

    assert ran
  end
end
