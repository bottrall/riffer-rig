# frozen_string_literal: true

require 'test_helper'

describe Riffer::Rig::UI::Banner do
  def setup
    @theme = Riffer::Rig::UI::Theme.new(enabled: false)
  end

  it 'includes the provided info values' do
    banner = Riffer::Rig::UI::Banner.call(
      @theme,
      model: 'anthropic/claude-x',
      cwd: '/tmp/proj',
      context: 'AGENTS.md',
      skills: '2',
      version: '9.9.9'
    )

    assert_includes banner, '/tmp/proj'
  end

  it 'includes the model' do
    banner = Riffer::Rig::UI::Banner.call(
      @theme,
      model: 'anthropic/claude-x',
      cwd: '/tmp/proj',
      context: 'none',
      skills: 'none',
      version: '9.9.9'
    )

    assert_includes banner, 'anthropic/claude-x'
  end

  it 'includes the skills label' do
    banner = Riffer::Rig::UI::Banner.call(@theme, model: 'm', cwd: 'c', context: 'none', skills: '3', version: '1')

    assert_includes banner, 'skills'
  end

  it 'includes the skills count' do
    banner = Riffer::Rig::UI::Banner.call(@theme, model: 'm', cwd: 'c', context: 'none', skills: '3', version: '1')

    assert_includes banner, '3'
  end

  it 'shows none when no skills' do
    banner = Riffer::Rig::UI::Banner.call(@theme, model: 'm', cwd: 'c', context: 'none', skills: 'none', version: '1')

    assert_includes banner, 'none'
  end

  it 'emits no ansi escapes when theme disabled' do
    banner = Riffer::Rig::UI::Banner.call(@theme, model: 'm', cwd: 'c', context: 'none', skills: 'none', version: '1')

    refute_includes banner, "\e["
  end
end
