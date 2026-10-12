# frozen_string_literal: true

require 'test_helper'
require 'stringio'
require_relative '../../../support/confirming_host'

class ListedSessions
  attr_reader :deleted

  def initialize(rows)
    @rows = rows
    @deleted = []
  end

  def list(_host, all: false)
    @rows.reject { |row| @deleted.include?(row.id) }
  end

  def delete(_host, id)
    @deleted << id
  end
end

class InterruptedInput
  def gets
    raise Interrupt
  end
end

class InterruptedHost
  def confirm(_question = nil)
    raise Interrupt
  end
end

describe Riffer::Rig::Terminal::Picker do
  before do
    @output = StringIO.new
    @renderer = Riffer::Rig::Terminal::Renderer.new(
      io: @output, theme: Riffer::Rig::Terminal::Theme.new(enabled: false)
    )
    @login = session('aaa', 'fix the login bug')
    @tests = session('bbb', 'add picker tests')
  end

  def session(id, title, updated: Time.now, cwd: '/work/project')
    Riffer::Rig::Terminal::Session.new(id: id, title: title, updated: updated, cwd: cwd)
  end

  def pick(rows, typed = '', all: false, host: Riffer::Rig::Hosts::Null.new, input: StringIO.new(typed))
    @sessions = ListedSessions.new(rows)
    picker = Riffer::Rig::Terminal::Picker.new(input: input, renderer: @renderer, host: host, sessions: @sessions)
    picker.open(all: all)
  end

  def row_updated(updated)
    pick([session('aaa', 'fix the login bug', updated: updated)])
    @output.string
  end

  describe '#open' do
    it 'says when there are no saved sessions' do
      pick([])

      assert_includes @output.string, 'No saved sessions.'
    end

    it 'picks nothing when there are no saved sessions' do
      assert_nil pick([])
    end

    it 'numbers the sessions under the header' do
      pick([@login, @tests])

      assert_includes(
        @output.string,
        "#{Riffer::Rig::Terminal::Picker::HEADER}\n  1. fix the login bug — just now\n  2. add picker tests — just now"
      )
    end

    it 'picks nothing when a delete started by Ctrl-D is cancelled' do
      assert_nil pick([@login], "\u{4}\n")
    end

    it 'says when the last session is deleted' do
      pick([@login], "\u{4}\n1\n", host: ConfirmingHost.new([true]))

      assert_includes @output.string, 'No saved sessions.'
    end

    it 'goes on with the sessions left after a delete' do
      assert_same @tests, pick([@login, @tests], "\u{4}\n1\n\n", host: ConfirmingHost.new([true]))
    end

    it 'picks nothing when the read is interrupted' do
      assert_nil pick([@login], input: InterruptedInput.new)
    end

    it 'picks the only session shown on an empty line' do
      assert_same @login, pick([@login], "\n")
    end

    it 'picks nothing on an empty line with several sessions shown' do
      assert_nil pick([@login, @tests], "\n")
    end

    it 'picks the session a number names' do
      assert_same @tests, pick([@login, @tests], "2\n")
    end

    it 'filters by title for any other line, ignoring case' do
      assert_same @login, pick([@login, @tests], "LOGIN\n\n")
    end

    it 'takes a number past the last row as filter text' do
      release = session('ccc', 'cut release 7')

      assert_same release, pick([@login, release], "7\n\n")
    end

    it 'picks nothing when an interrupt escapes the loop' do
      assert_nil pick([@login], "\u{4}\n1\n", host: InterruptedHost.new)
    end
  end

  describe 'the delete prompt' do
    it 'lists the sessions shown under its own header' do
      pick([@login], "\u{4}\n")

      assert_includes @output.string, "#{Riffer::Rig::Terminal::Picker::DELETE_HEADER}\n  1. fix the login bug"
    end

    it 'goes back to the sessions for a line that is not a number' do
      assert_same @login, pick([@login], "\u{4}\nlogin\n\n")
    end

    it 'asks before deleting the numbered session' do
      host = ConfirmingHost.new([false])
      pick([@login, @tests], "\u{4}\n2\n", host: host)

      assert_equal ['Delete "add picker tests"?'], host.questions
    end

    it 'keeps the session when the delete is declined' do
      pick([@login], "\u{4}\n1\n", host: ConfirmingHost.new([false]))

      assert_empty @sessions.deleted
    end

    it 'deletes the session once confirmed' do
      pick([@login, @tests], "\u{4}\n2\n", host: ConfirmingHost.new([true]))

      assert_equal ['bbb'], @sessions.deleted
    end
  end

  describe 'a row' do
    it 'leads with the directory name when listing every directory' do
      pick([@login], all: true)

      assert_includes @output.string, '  1. [project] fix the login bug — just now'
    end

    it 'shows unknown for a session with no update time' do
      assert_includes row_updated(nil), 'fix the login bug — unknown'
    end

    it 'counts a single minute' do
      assert_includes row_updated(Time.now - 60), 'fix the login bug — 1 minute ago'
    end

    it 'counts several minutes' do
      assert_includes row_updated(Time.now - 120), 'fix the login bug — 2 minutes ago'
    end

    it 'counts the hours' do
      assert_includes row_updated(Time.now - (3 * 3_600)), 'fix the login bug — 3 hours ago'
    end

    it 'counts the days' do
      assert_includes row_updated(Time.now - (2 * 86_400)), 'fix the login bug — 2 days ago'
    end

    it 'shows the date past thirty days' do
      assert_includes row_updated(Time.utc(2020, 1, 5)), 'fix the login bug — Jan 5, 2020'
    end
  end
end
