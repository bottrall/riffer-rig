# frozen_string_literal: true

require 'test_helper'

describe Riffer::Rig::Terminal::Banner do
  def setup
    @theme = Riffer::Rig::Terminal::Theme.new(enabled: false)
  end

  it 'emits no ansi escapes when theme disabled' do
    banner = Riffer::Rig::Terminal::Banner.call(@theme, model: 'm', cwd: 'c', skills: 'none', version: '1')

    refute_includes banner, "\e["
  end

  it 'includes the provided info values' do
    banner = Riffer::Rig::Terminal::Banner.call(
      @theme,
      model: 'anthropic/claude-x',
      cwd: '/tmp/proj',
      skills: '2',
      version: '9.9.9'
    )

    assert_includes banner, '/tmp/proj'
  end

  it 'includes the model' do
    banner = Riffer::Rig::Terminal::Banner.call(
      @theme,
      model: 'anthropic/claude-x',
      cwd: '/tmp/proj',
      skills: 'none',
      version: '9.9.9'
    )

    assert_includes banner, 'anthropic/claude-x'
  end

  it 'includes the skills count' do
    banner = Riffer::Rig::Terminal::Banner.call(@theme, model: 'm', cwd: 'c', skills: '3', version: '1')

    assert_includes banner, '3'
  end

  describe 'the logo' do
    def banner(width)
      Riffer::Rig::Terminal::Banner.call(@theme, model: 'm', cwd: 'c', skills: 'none', version: '1', width: width)
    end

    it 'is drawn when the width is unknown' do
      assert_includes banner(nil), Riffer::Rig::Terminal::Banner::WORDMARK.first
    end

    it 'is drawn on a terminal as wide as it' do
      assert_includes banner(Riffer::Rig::Terminal::Banner::ART_COLUMNS), Riffer::Rig::Terminal::Banner::WORDMARK.first
    end

    it 'is left out on a narrower terminal' do
      refute_includes banner(Riffer::Rig::Terminal::Banner::ART_COLUMNS - 1), '█'
    end

    it 'leaves the tagline in on a narrower terminal' do
      assert_includes banner(Riffer::Rig::Terminal::Banner::ART_COLUMNS - 1), "♪ let's riff ♪"
    end
  end

  describe 'a value too long for its row' do
    def banner(model: 'm', cwd: 'c', width: 30)
      Riffer::Rig::Terminal::Banner.call(@theme, model: model, cwd: cwd, skills: 'none', version: '1', width: width)
    end

    it 'keeps a long value whole when the width is unknown' do
      assert_match(%r{cwd\s+/home/someone/repos/riffer-rig$}, banner(cwd: '/home/someone/repos/riffer-rig', width: nil))
    end

    it 'keeps a model that fits whole' do
      assert_match(%r{model\s+anthropic/claude-x$}, banner(model: 'anthropic/claude-x'))
    end

    it 'cuts a long model from the left' do
      assert_match(/model\s+…claude-sonnet-4-5$/, banner(model: 'anthropic/claude-sonnet-4-5'))
    end

    it 'cuts a long working directory from the left' do
      assert_match(%r{cwd\s+…/repos/riffer-rig$}, banner(cwd: '/home/someone/repos/riffer-rig'))
    end

    it 'fits the cut row to the width' do
      cut = banner(cwd: '/home/someone/repos/riffer-rig').lines(chomp: true).find { |line| line.include?('cwd') }

      assert_equal 30, Riffer::Rig::Terminal::Columns.width(cut)
    end
  end

  describe 'the session row' do
    def banner(tally)
      Riffer::Rig::Terminal::Banner.call(@theme, model: 'm', cwd: 'c', skills: 'none', version: '1', tally: tally)
    end

    it 'shows the tally in a session row' do
      tally = Riffer::Providers::TokenUsage.new(input_tokens: 300, output_tokens: 150, cost: 0.25)
      session = Regexp.escape(Riffer::Rig::Terminal::Tally.call(tally))

      assert_match(/session\s+#{session}$/, banner(tally))
    end

    it 'omits the row before the first turn' do
      refute_includes banner(nil), 'session'
    end
  end
end
