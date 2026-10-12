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
