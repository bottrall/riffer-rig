# frozen_string_literal: true

require 'test_helper'

describe Riffer::Rig::Terminal::StatusBar do
  def idle(room: 120, color: false, jobs: 1)
    Riffer::Rig::Terminal::StatusBar.idle(
      clock: '14:32',
      up_tokens: 132_000,
      down_tokens: 218_000,
      cost: 1.4,
      jobs: jobs,
      theme: Riffer::Rig::Terminal::Theme.new(enabled: color),
      room: room
    )
  end

  def working(room: 120, color: false)
    Riffer::Rig::Terminal::StatusBar.working(
      glyph: '⠸',
      state: 'turn 7',
      clock: '00:41',
      up_tokens: 18_240,
      down_tokens: 3_100,
      cost: 0.071,
      jobs: 2,
      theme: Riffer::Rig::Terminal::Theme.new(enabled: color),
      room: room
    )
  end

  describe '#idle' do
    it 'pads every slot to its fixed width' do
      assert_equal '· idle    14:32 ↑132k  ↓218k tok  ~$1.4000 1 job ', idle
    end

    it 'cuts a value that overflows its slot' do
      assert_equal '· idle    14:32 ↑132k  ↓218k tok  ~$1.4000 12 job', idle(jobs: 12)
    end

    it 'sheds the clock whole when the row does not fit' do
      assert_equal '· idle    ↑132k  ↓218k tok  ~$1.4000 1 job ', idle(room: 43)
    end

    it 'sheds the cost after the clock' do
      assert_equal '· idle    ↑132k  ↓218k tok  1 job ', idle(room: 34)
    end

    it 'sheds the tokens after the cost' do
      assert_equal '· idle    1 job ', idle(room: 16)
    end

    it 'sheds the state last, keeping the jobs count at the right edge' do
      assert_equal '· 1 job ', idle(room: 8)
    end

    it 'keeps the glyph and the jobs count whole when nothing else fits' do
      assert_equal '· 1 job ', idle(room: 5)
    end

    it 'dims the whole row' do
      assert_equal "\e[2m· idle    14:32 ↑132k  ↓218k tok  ~$1.4000 1 job \e[0m", idle(color: true)
    end
  end

  describe '#working' do
    it 'pads every slot to the same widths as the idle state' do
      assert_equal '⠸ turn 7  00:41 ↑18.2k ↓3.1k tok  ~$0.0710 2 jobs', working
    end

    it 'renders both states at the same visible width' do
      assert_equal Riffer::Rig::Terminal::Columns.width(idle), Riffer::Rig::Terminal::Columns.width(working)
    end

    it 'paints the spinner and the cost green and the jobs count amber' do
      assert_equal(
        "\e[38;2;126;201;160m⠸\e[0m turn 7  00:41 \e[2m↑18.2k\e[0m \e[2m↓3.1k tok \e[0m " \
        "\e[38;2;126;201;160m~$0.0710\e[0m \e[38;2;217;176;108m2 jobs\e[0m",
        working(color: true)
      )
    end
  end
end
