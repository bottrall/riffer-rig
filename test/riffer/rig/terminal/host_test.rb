# frozen_string_literal: true

require 'test_helper'
require 'stringio'

describe Riffer::Rig::Hosts::Terminal do
  def host(input = '')
    @output = StringIO.new
    theme = Riffer::Rig::Terminal::Theme.new(enabled: false)
    Riffer::Rig::Hosts::Terminal.new(
      input: StringIO.new(input),
      renderer: Riffer::Rig::Terminal::Renderer.new(io: @output, theme: theme),
      animator: Riffer::Rig::Terminal::Animator.new(io: @output, theme: theme)
    )
  end

  it 'reports all four capabilities' do
    assert_equal Set[:ask, :confirm, :notify, :progress], host.capabilities
  end

  it 'prints the question' do
    host("x\n").ask('Which model?')

    assert_includes @output.string, 'Which model?'
  end

  it 'answers the typed line without its newline' do
    assert_equal 'mock/test', host("  mock/test \n").ask('Which model?')
  end

  it 'answers nil at the end of input' do
    assert_nil host.ask('Which model?')
  end

  it 'reads a secret answer' do
    assert_equal 'sk-test', host("sk-test\n").ask('anthropic api_key', secret: true)
  end

  it 'lists the options' do
    host("1\n").ask('Sign in with?', options: %w[chain token])

    assert_includes @output.string, '2. token'
  end

  it 'maps an option number to the option' do
    assert_equal 'token', host("2\n").ask('Sign in with?', options: %w[chain token])
  end

  it 'keeps a typed option as written' do
    assert_equal 'chain', host("chain\n").ask('Sign in with?', options: %w[chain token])
  end

  it 'keeps a number beyond the options as written' do
    assert_equal '3', host("3\n").ask('Sign in with?', options: %w[chain token])
  end

  it 'confirms on yes' do
    assert host("y\n").confirm('Trust this project?')
  end

  it 'declines on anything else' do
    refute host("\n").confirm('Trust this project?')
  end

  it 'declines at the end of input' do
    refute host.confirm('Trust this project?')
  end

  it 'renders a notify as its own line' do
    host.notify('Extension x failed to load', level: :error)

    assert_equal "\nExtension x failed to load\n", @output.string
  end

  it 'yields from progress' do
    yielded = false
    host.progress('Installing') { yielded = true }

    assert yielded
  end

  it 'labels the progress' do
    host.progress('Installing') { nil }

    assert_includes @output.string, 'Installing'
  end
end
