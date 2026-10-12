# frozen_string_literal: true

require 'test_helper'
require 'stringio'
require_relative '../../../support/confirming_host'

class PickerInput
  def initialize(lines)
    @lines = lines.dup
  end

  def gets
    line = @lines.shift
    raise Interrupt if line == :interrupt

    line && "#{line}\n"
  end
end

class PickerSessions
  attr_reader :scopes, :deleted

  def initialize(rows)
    @rows = rows
    @scopes = []
    @deleted = []
  end

  def list(_host, all: false)
    @scopes << all
    @rows
  end

  def delete(_host, id)
    @deleted << id
    @rows = @rows.reject { |row| row.id == id }
  end
end

class PickerInterruptedHost
  def confirm(_question = nil)
    raise Interrupt
  end
end

describe Riffer::Rig::Terminal::Picker do
  def session(title, updated: nil, cwd: '/work/proj')
    Riffer::Rig::Terminal::Session.new(id: "id-#{title}", title: title, updated: updated, cwd: cwd)
  end

  def ctrl_d = Riffer::Rig::Terminal::Picker::EOT

  def pick(rows, lines, all: false, host: ConfirmingHost.new)
    @output = StringIO.new
    @host = host
    @sessions = PickerSessions.new(rows)
    Riffer::Rig::Terminal::Picker.new(
      input: PickerInput.new(lines),
      renderer: Riffer::Rig::Terminal::Renderer.new(
        io: @output,
        theme: Riffer::Rig::Terminal::Theme.new(enabled: false)
      ),
      host: @host,
      sessions: @sessions
    ).open(all: all)
  end

  def rendered(rows, lines = [''], **)
    pick(rows, lines, **)
    @output.string
  end

  describe '#open' do
    it 'lists the sessions in the requested scope' do
      pick([session('alpha')], [''], all: true)

      assert_equal [true], @sessions.scopes
    end

    it 'says so when there are no saved sessions' do
      assert_includes rendered([]), Riffer::Rig::Terminal::Picker::EMPTY
    end

    it 'returns nothing when there are no saved sessions' do
      assert_nil pick([], ['1'])
    end

    it 'shows the header' do
      assert_includes rendered([session('alpha')]), Riffer::Rig::Terminal::Picker::HEADER
    end

    it 'numbers the sessions' do
      assert_includes rendered([session('alpha'), session('beta')]), '2. beta'
    end

    it 'narrows the list to the titles matching the filter, ignoring case' do
      output = rendered([session('alpha'), session('Beta')], ['BET', ''])

      assert_includes output, '1. Beta'
    end

    it 'enters delete mode on Ctrl-D' do
      output = rendered([session('alpha')], [ctrl_d, nil])

      assert_includes output, Riffer::Rig::Terminal::Picker::DELETE_HEADER
    end

    it 'enters delete mode when the input closes' do
      output = rendered([session('alpha')], [nil, nil])

      assert_includes output, Riffer::Rig::Terminal::Picker::DELETE_HEADER
    end

    it 'returns nothing when delete mode is cancelled' do
      assert_nil pick([session('alpha')], [ctrl_d, nil])
    end

    it 'carries on with the remaining sessions after a delete' do
      beta = session('beta')

      assert_same beta, pick([session('alpha'), beta], [ctrl_d, '1', ''], host: ConfirmingHost.new([true]))
    end

    it 'says so when the last session is deleted' do
      output = rendered([session('alpha')], [ctrl_d, '1'], host: ConfirmingHost.new([true]))

      assert_includes output, Riffer::Rig::Terminal::Picker::EMPTY
    end

    it 'returns nothing when the last session is deleted' do
      assert_nil pick([session('alpha')], [ctrl_d, '1', '1'], host: ConfirmingHost.new([true]))
    end

    it 'returns nothing when interrupted at the prompt' do
      assert_nil pick([session('alpha')], [:interrupt, '1'])
    end

    it 'switches to the single match on Enter' do
      beta = session('beta')

      assert_same beta, pick([session('alpha'), beta], ['bet', ''])
    end

    it 'returns nothing on Enter with several matches' do
      assert_nil pick([session('alpha'), session('beta')], [''])
    end

    it 'returns nothing on Enter with no matches' do
      assert_nil pick([session('alpha')], ['zzz', ''])
    end

    it 'switches to the session with the typed number' do
      beta = session('beta')

      assert_same beta, pick([session('alpha'), beta], ['2'])
    end

    it 'numbers against the filtered list' do
      beta = session('beta')

      assert_same beta, pick([session('alpha'), beta], %w[bet 1])
    end

    it 'treats an out-of-range number as filter text' do
      route = session('route 66')

      assert_same route, pick([session('alpha'), route], ['66', ''])
    end

    it 'returns nothing when interrupted outside the prompt' do
      assert_nil pick([session('alpha')], [ctrl_d, '1', '1'], host: PickerInterruptedHost.new)
    end
  end

  describe 'delete mode' do
    it 'numbers the sessions the filter left showing' do
      pick([session('alpha'), session('beta')], ['bet', ctrl_d, '1', nil, nil], host: ConfirmingHost.new([true]))

      assert_equal ['id-beta'], @sessions.deleted
    end

    it 'cancels when interrupted at the prompt' do
      assert_nil pick([session('alpha')], [ctrl_d, :interrupt, '1'])
    end

    it 'deletes nothing on a line that is not a number' do
      pick([session('alpha')], [ctrl_d, 'alpha', ''], host: ConfirmingHost.new([true]))

      assert_empty @sessions.deleted
    end

    it 'returns to the picker on a line that is not a number' do
      alpha = session('alpha')

      assert_same alpha, pick([alpha], [ctrl_d, 'alpha', ''])
    end

    it 'deletes nothing on an out-of-range number' do
      pick([session('alpha')], [ctrl_d, '7', ''], host: ConfirmingHost.new([true]))

      assert_empty @sessions.deleted
    end

    it 'asks before deleting, naming the session' do
      pick([session('alpha')], [ctrl_d, '1', ''])

      assert_equal ['Delete "alpha"?'], @host.questions
    end

    it 'deletes nothing when the confirmation is declined' do
      pick([session('alpha')], [ctrl_d, '1', ''], host: ConfirmingHost.new([false]))

      assert_empty @sessions.deleted
    end

    it 'returns to the picker when the confirmation is declined' do
      alpha = session('alpha')

      assert_same alpha, pick([alpha], [ctrl_d, '1', ''], host: ConfirmingHost.new([false]))
    end

    it 'deletes the confirmed session' do
      pick([session('alpha'), session('beta')], [ctrl_d, '2', nil, nil], host: ConfirmingHost.new([true]))

      assert_equal ['id-beta'], @sessions.deleted
    end

    it 'reports the delete' do
      output = rendered([session('alpha'), session('beta')], [ctrl_d, '2', ''], host: ConfirmingHost.new([true]))

      assert_includes output, Riffer::Rig::Terminal::Picker::DELETED
    end

    it 'relists in the same scope after a delete' do
      pick([session('alpha'), session('beta')], [ctrl_d, '2', ''], all: true, host: ConfirmingHost.new([true]))

      assert_equal [true, true], @sessions.scopes
    end
  end

  describe 'a row' do
    it 'omits the project when listing one project' do
      assert_includes rendered([session('alpha', cwd: '/work/proj')]), '1. alpha — '
    end

    it 'leads with the project directory when listing every project' do
      assert_includes rendered([session('alpha', cwd: '/work/proj')], all: true), '1. [proj] alpha — '
    end

    it 'shows unknown for a session with no timestamp' do
      assert_includes rendered([session('alpha', updated: nil)]), 'alpha — unknown'
    end

    it 'shows just now within the first minute' do
      assert_includes rendered([session('alpha', updated: Time.now - 5)]), 'alpha — just now'
    end

    it 'counts a single minute' do
      assert_includes rendered([session('alpha', updated: Time.now - 90)]), 'alpha — 1 minute ago'
    end

    it 'counts minutes within the first hour' do
      assert_includes rendered([session('alpha', updated: Time.now - 150)]), 'alpha — 2 minutes ago'
    end

    it 'counts hours within the first day' do
      assert_includes rendered([session('alpha', updated: Time.now - (3.5 * 3_600))]), 'alpha — 3 hours ago'
    end

    it 'counts days within the first thirty' do
      assert_includes rendered([session('alpha', updated: Time.now - (3.5 * 86_400))]), 'alpha — 3 days ago'
    end

    it 'shows the date beyond thirty days' do
      updated = Time.now - (40 * 86_400)

      assert_includes rendered([session('alpha', updated: updated)]), "alpha — #{updated.strftime('%b %-d, %Y')}"
    end
  end
end
