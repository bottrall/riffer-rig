# frozen_string_literal: true

require 'test_helper'

describe Riffer::Rig::Terminal::Autocomplete do
  def commands
    {
      'model' => 'Switch the model',
      'auth' => 'Store credentials',
      'reload' => 'Reload extensions',
      'commit' => 'Commit staged work',
      'skill:review' => 'Review code.'
    }.map { |name, about| Riffer::Rig::Command.new(name, description: about, extension: :core) { nil } }
  end

  def key(name)
    return Riffer::Rig::Terminal::Key.new(:text, name) if name.is_a?(String)

    Riffer::Rig::Terminal::Key.new(name)
  end

  def typed(*names, from: Riffer::Rig::Terminal::Autocomplete.new(commands: commands))
    names.reduce(from) { |state, name| state.press(key(name)) }
  end

  def submitted(*lines)
    lines.reduce(typed) { |state, line| typed(*line.chars, from: state).submit }
  end

  def names(state)
    state.matches.map(&:name)
  end

  it 'is frozen' do
    assert_predicate typed, :frozen?
  end

  describe '#matches' do
    it 'is empty before anything is typed' do
      assert_empty names(typed)
    end

    it 'is empty when the slash is not leading' do
      assert_empty names(typed(' ', '/'))
    end

    it 'is empty once the line moves on to arguments' do
      assert_empty names(typed('/', 'm', 'o', 'd', 'e', 'l', ' '))
    end

    it 'treats typed regexp characters literally' do
      assert_empty names(typed('/', '.'))
    end

    it 'matches letters in order across gaps' do
      assert_equal %w[skill:review], names(typed('/', 's', 'r', 'v'))
    end

    it 'ignores case' do
      assert_equal %w[model], names(typed('/', 'M', 'O'))
    end

    it 'filters live as the name is typed' do
      assert_equal %w[model], names(typed('/', 'm', 'o'))
    end

    it 'is empty when nothing matches' do
      assert_empty names(typed('/', 'z'))
    end

    it 'lists every command in name order on a leading slash' do
      assert_equal %w[auth commit model reload skill:review], names(typed('/'))
    end

    it 'ranks prefix matches ahead of fuzzy matches' do
      assert_equal %w[model commit], names(typed('/', 'm'))
    end
  end

  describe '#open?' do
    it 'is closed on an ordinary line' do
      refute_predicate typed('h', 'i'), :open?
    end

    it 'opens on a leading slash' do
      assert_predicate typed('/'), :open?
    end
  end

  describe '#selected' do
    it 'is nothing while closed' do
      assert_nil typed('h').selected
    end

    it 'starts on the best match' do
      assert_equal 'model', typed('/', 'm').selected.name
    end
  end

  describe '#ghost' do
    it 'is empty while closed' do
      assert_equal '', typed('h').ghost
    end

    it 'is empty when the cursor is not at the end of the line' do
      assert_equal '', typed('/', 'm', 'o', :left).ghost
    end

    it 'is empty for a fuzzy match' do
      assert_equal '', typed('/', 's', 'r', 'v').ghost
    end

    it 'completes the selected name past the typed prefix' do
      assert_equal 'del', typed('/', 'm', 'o').ghost
    end

    it 'follows the selection' do
      assert_equal 'commit', typed('/', :down).ghost
    end
  end

  describe '#press' do
    it 'recalls history on up while closed' do
      state = typed('h', 'i').submit

      assert_equal 'hi', typed(:up, from: state).editor.text
    end

    it 'recalls past a slash command in the history' do
      assert_equal 'hello', typed(:up, :up, from: submitted('hello', '/reload')).editor.text
    end

    it 'stays closed on a recalled slash command' do
      refute_predicate typed(:up, from: submitted('/reload')), :open?
    end

    it 'stays closed while a recalled slash command is edited' do
      refute_predicate typed(:up, :backspace, from: submitted('/reload')), :open?
    end

    it 'returns to the draft on down from a recalled slash command' do
      assert_equal 'hi', typed('h', 'i', :up, :down, from: submitted('/reload')).editor.text
    end

    it 'opens on a fresh slash after a recalled slash command' do
      assert_predicate typed(:up, :down, '/', from: submitted('/reload')), :open?
    end

    it 'opens on a narrowed slash line after a recall that finds no history' do
      assert_predicate typed('/', 'z', :up, :backspace), :open?
    end

    it 'wraps to the last match on up' do
      assert_equal 'skill:review', typed('/', :up).selected.name
    end

    it 'leaves the line alone when cycling' do
      assert_equal '/', typed('/', :up).editor.text
    end

    it 'moves to the next match on down' do
      assert_equal 'commit', typed('/', :down).selected.name
    end

    it 'wraps to the first match on down' do
      assert_equal 'auth', typed('/', :up, :down).selected.name
    end

    it 'accepts the selection on tab' do
      assert_equal '/model ', typed('/', 'm', 'o', :tab).editor.text
    end

    it 'accepts a cycled selection' do
      assert_equal '/commit ', typed('/', :down, :tab).editor.text
    end

    it 'accepts a fuzzy match in full' do
      assert_equal '/skill:review ', typed('/', 's', 'r', 'v', :tab).editor.text
    end

    it 'closes once a selection is accepted' do
      refute_predicate typed('/', 'm', 'o', :tab), :open?
    end

    it 'keeps the history across an accept' do
      state = typed('h', 'i').submit

      assert_equal %w[hi], typed('/', 'm', :tab, from: state).editor.history
    end

    it 'accepts the selection on right at the end of the line' do
      assert_equal '/model ', typed('/', 'm', 'o', :right).editor.text
    end

    it 'moves the cursor on right inside the line' do
      assert_equal '/mo', typed('/', 'm', 'o', :left, :right).editor.text
    end

    it 'dismisses on escape' do
      refute_predicate typed('/', 'm', :escape), :open?
    end

    it 'keeps the typed line on escape' do
      assert_equal '/m', typed('/', 'm', :escape).editor.text
    end

    it 'stays dismissed while the slash line is edited' do
      refute_predicate typed('/', 'm', :escape, 'o'), :open?
    end

    it 'opens again on a fresh slash after a dismissal' do
      assert_predicate typed('/', :escape, :backspace, '/'), :open?
    end

    it 'returns to the best match when the filter changes' do
      assert_equal 'reload', typed('/', :down, 'r').selected.name
    end

    it 'keeps the selection when the cursor moves' do
      assert_equal 'commit', typed('/', :down, :left).selected.name
    end

    it 'closes when the slash is deleted' do
      refute_predicate typed('/', :backspace), :open?
    end
  end

  describe '#submit' do
    it 'records the line in the history' do
      assert_equal %w[/m], typed('/', 'm').submit.editor.history
    end

    it 'opens again after a dismissed line is submitted' do
      assert_predicate typed('/', from: typed('/', :escape).submit), :open?
    end
  end
end
