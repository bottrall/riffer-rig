# frozen_string_literal: true

require 'test_helper'

describe Riffer::Rig::Terminal::Replay do
  def entry(message, seconds = nil)
    recorded_at = seconds && Riffer::Rig::Stores::Timestamp.dump(Time.utc(2026, 10, 11) + seconds)
    Riffer::Rig::Stores::MessageEntry.new(message: message.to_h, recorded_at: recorded_at)
  end

  def user(content)
    Riffer::Messages::User.new(content)
  end

  def assistant(content, usage: nil)
    Riffer::Messages::Assistant.new(content, token_usage: usage)
  end

  def calling(content, usage: nil)
    call = Riffer::Messages::Assistant::ToolCall.new(call_id: 'call_1', name: 'read', arguments: '{}')
    Riffer::Messages::Assistant.new(content, tool_calls: [call], token_usage: usage)
  end

  def result
    Riffer::Messages::Tool.new('ok', tool_call_id: 'call_1', name: 'read')
  end

  def notification(follow_up_exits: nil)
    Riffer::Rig::Runtime::JobNotification.new('<background-job id="a1b2c3d4">', follow_up_exits: follow_up_exits)
  end

  def follow_up
    [*exchange, entry(notification(follow_up_exits: 1), 60), entry(assistant('Passed.'), 67)]
  end

  def usage(input, output)
    Riffer::Providers::TokenUsage.new(input_tokens: input, output_tokens: output)
  end

  def exchange
    [entry(user('Go'), 0), entry(assistant('Done.'), 41)]
  end

  def notice
    "\n  #{Riffer::Rig::Terminal::Replay::NOTICE}\n"
  end

  def replay(recorded, color: false, width: nil)
    theme = Riffer::Rig::Terminal::Theme.new(enabled: color)
    Riffer::Rig::Terminal::Replay.call(recorded, theme: theme, width: width)
  end

  describe '.call' do
    it 'replays nothing for a session that recorded no message' do
      assert_empty replay([])
    end

    it 'replays a turn a job notification continued as one turn' do
      recorded = [
        entry(user('Go'), 0),
        entry(assistant('Started.'), 5),
        entry(notification, 30),
        entry(assistant('Passed.'), 41)
      ]

      assert_equal "\n› Go\n\n  Passed.\n\n  2 steps · 00:41\n", replay(recorded)
    end

    it 'replays no job notification delivered ahead of a prompt as a turn' do
      recorded = [*exchange, entry(notification, 60), entry(user('Again'), 60), entry(assistant('Fixed.'), 67)]

      assert_equal(
        "\n› Go\n\n  Done.\n\n  1 step · 00:41\n\n› Again\n\n  Fixed.\n\n  1 step · 00:07\n",
        replay(recorded)
      )
    end

    it 'replays a turn a job exit started as its own turn' do
      assert_equal(
        "\n› Go\n\n  Done.\n\n  1 step · 00:41\n\n  1 background job exited\n\n  Passed.\n\n  1 step · 00:07\n",
        replay(follow_up)
      )
    end

    it 'replays each turn as a user line, an answer and a stat footer' do
      recorded = [
        entry(user('refactor the picker'), 0),
        entry(assistant('The picker uses the registrar now.'), 41),
        entry(user('also fix the flaky test'), 60),
        entry(assistant('Fixed it.'), 67)
      ]
      first = "\n› refactor the picker\n\n  The picker uses the registrar now.\n\n  1 step · 00:41\n"

      assert_equal "#{first}\n› also fix the flaky test\n\n  Fixed it.\n\n  1 step · 00:07\n", replay(recorded)
    end

    it 'keeps a turn apart from the unreadable prompt recorded after it' do
      recorded = [*exchange, entry({ role: 'user' }, 60), entry(assistant('Lost.'), 67)]

      assert_equal "\n› Go\n\n  Done.\n\n  1 step · 00:41\n#{notice}", replay(recorded)
    end

    it 'wraps a replayed prompt to the width' do
      recorded = [entry(user('refactor the picker now'), 0), entry(assistant('Done.'), 41)]

      assert_equal "\n› refactor the\n  picker now\n\n  Done.\n\n  1 step · 00:41\n", replay(recorded, width: 16)
    end

    it 'wraps a replayed answer to the width' do
      recorded = [entry(user('Go'), 0), entry(assistant('The picker now reads its rows.'), 41)]

      assert_equal "\n› Go\n\n  The picker now reads\n  its rows.\n\n  1 step · 00:41\n", replay(recorded, width: 24)
    end

    it 'closes with a notice when a turn could not be replayed' do
      recorded = [entry(user('Earlier')), entry(assistant('Unstamped.')), *exchange]

      assert_equal "\n› Go\n\n  Done.\n\n  1 step · 00:41\n#{notice}", replay(recorded)
    end

    it 'dims the notice' do
      dimmed = "\n\e[2m  Turns recorded by an older version or damaged on disk are not shown.\e[0m\n"

      assert_equal dimmed, replay([entry(user('Earlier'))], color: true)
    end
  end

  describe '.turn' do
    it 'does not replay a turn whose first entry is unstamped' do
      assert_equal notice, replay([entry(user('Go')), entry(assistant('Done.'), 41)])
    end

    it 'does not replay a turn whose last entry is unstamped' do
      assert_equal notice, replay([entry(user('Go'), 0), entry(assistant('Done.'))])
    end

    it 'does not replay what was recorded before the first prompt' do
      recorded = [entry(assistant('Hello.'), 0), *exchange]

      assert_equal "\n› Go\n\n  Done.\n\n  1 step · 00:41\n#{notice}", replay(recorded)
    end

    it 'leaves out the requests between the prompt and the answer' do
      recorded = [entry(user('Go'), 0), entry(calling('Looking.'), 5), entry(result, 6), entry(assistant('Done.'), 41)]

      assert_equal "\n› Go\n\n  Done.\n\n  2 steps · 00:41\n", replay(recorded)
    end

    it 'prints the footer alone for a turn that ended without an answer' do
      recorded = [entry(user('Go'), 0), entry(calling('Let me look.'), 5), entry(result, 41)]

      assert_equal "\n› Go\n\n  1 step · 00:41\n", replay(recorded)
    end

    it 'takes a reply without text for no answer' do
      assert_equal "\n› Go\n\n  1 step · 00:41\n", replay([entry(user('Go'), 0), entry(assistant(" \n"), 41)])
    end

    it 'shows the last of the replies a turn recorded' do
      recorded = [entry(user('Go'), 0), entry(assistant('Half a sen'), 5), entry(assistant('Done.'), 41)]

      assert_equal "\n› Go\n\n  Done.\n\n  2 steps · 00:41\n", replay(recorded)
    end

    it 'takes the wall time from the first entry of the turn to its last' do
      recorded = [entry(user('Go'), 5), entry(calling(''), 6), entry(result, 7), entry(assistant('Done.'), 130)]

      assert_equal "\n› Go\n\n  Done.\n\n  2 steps · 02:05\n", replay(recorded)
    end

    it 'sums the usage the requests of the turn reported' do
      recorded = [
        entry(user('Go'), 0),
        entry(calling('', usage: usage(100, 20)), 5),
        entry(result, 6),
        entry(assistant('Done.', usage: usage(150, 30)), 41)
      ]

      assert_equal "\n› Go\n\n  Done.\n\n  2 steps · 00:41 · ↑250 · ↓50\n", replay(recorded)
    end
  end

  describe '.heading' do
    it 'paints the job exit line of a turn a job exit started grey' do
      recorded = [entry(notification(follow_up_exits: 2), 0), entry(assistant('Passed.'), 7)]
      painted = "\n\e[38;2;138;139;154m  2 background jobs exited\e[0m\n\n  Passed.\n\n\e[2m  1 step · 00:07\e[0m\n"

      assert_equal painted, replay(recorded, color: true)
    end
  end

  describe '.message' do
    it 'does not replay a turn holding a message without text' do
      assert_equal notice, replay([entry(user('Go'), 0), entry({ role: 'assistant' }, 41)])
    end

    it 'does not replay a turn holding a message riffer fails to rebuild' do
      damaged = { role: 'assistant', content: 'Done.', tool_calls: 'none' }

      assert_equal notice, replay([entry(user('Go'), 0), entry(damaged, 41)])
    end
  end
end
