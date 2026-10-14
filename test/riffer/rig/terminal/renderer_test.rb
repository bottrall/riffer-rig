# frozen_string_literal: true

require 'test_helper'
require 'stringio'

describe Riffer::Rig::Terminal::Renderer do
  def setup
    @io = StringIO.new
    @renderer = Riffer::Rig::Terminal::Renderer.new(io: @io, theme: Riffer::Rig::Terminal::Theme.new(enabled: false))
  end

  it 'renders a notice in its own block' do
    @renderer.notice('saved')

    assert_equal "\nsaved\n", @io.string
  end

  it 'renders an error in its own block' do
    @renderer.error('boom')

    assert_equal "\nboom\n", @io.string
  end

  it 'notifies an error level as an error' do
    theme = Riffer::Rig::Terminal::Theme.new(enabled: true)
    renderer = Riffer::Rig::Terminal::Renderer.new(io: @io, theme: theme)

    renderer.notify('boom', :error)

    assert_equal "\n#{theme.red('boom')}\n", @io.string
  end

  it 'notifies any other level as a notice' do
    theme = Riffer::Rig::Terminal::Theme.new(enabled: true)
    renderer = Riffer::Rig::Terminal::Renderer.new(io: @io, theme: theme)

    renderer.notify('saved', :info)

    assert_equal "\n#{theme.grey('saved')}\n", @io.string
  end

  it 'renders the prompt marker below a blank line' do
    @renderer.prompt

    assert_equal "\n› ", @io.string
  end

  it 'echoes a submitted line after the prompt marker in its own block' do
    @renderer.echo('hello')

    assert_equal "\n› hello\n", @io.string
  end

  it 'renders a question with numbered options' do
    @renderer.question('Pick one', %w[chain token], false)

    assert_equal "\nPick one\n  1. chain\n  2. token\n› ", @io.string
  end

  it 'renders only the prompt marker when there is no question text' do
    @renderer.question(nil, nil, false)

    assert_equal "\n› ", @io.string
  end

  it 'marks a secret question as hidden' do
    @renderer.question('anthropic api_key', nil, true)

    assert_includes @io.string, '(hidden)'
  end

  it 'renders a newline' do
    @renderer.newline

    assert_equal "\n", @io.string
  end
end
