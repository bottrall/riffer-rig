# frozen_string_literal: true

require 'test_helper'
require 'stringio'
require_relative '../../../support/prompter_pty'

describe Riffer::Rig::Terminal::Host do
  after do
    @pty&.close
  end

  def host(input = '')
    @output = StringIO.new
    theme = Riffer::Rig::Terminal::Theme.new(enabled: false)
    renderer = Riffer::Rig::Terminal::Renderer.new(io: @output, theme: theme)
    Riffer::Rig::Terminal::Host.new(
      prompter: Riffer::Rig::Terminal::BlockingPrompter.new(input: StringIO.new(input), renderer: renderer),
      renderer: renderer
    )
  end

  def at_the_footer(keys)
    @pty = PrompterPty.new
    @pty.answering(keys) { yield @pty.host }
  end

  it 'reports all four capabilities' do
    assert_equal Set[:ask, :confirm, :notify, :progress], host.capabilities
  end

  it 'prints the question' do
    host("x\n").ask('Which model?')

    assert_includes @output.string, 'Which model?'
  end

  it 'lists the options' do
    host("1\n").ask('Sign in with?', options: %w[chain token])

    assert_includes @output.string, '2. token'
  end

  it 'reads a secret answer' do
    assert_equal 'sk-test', host("sk-test\n").ask('anthropic api_key', secret: true)
  end

  it 'reads a secret answer typed at the footer' do
    assert_equal 'sk-test', at_the_footer("sk-test\r") { |host| host.ask('anthropic api_key', secret: true) }
  end

  it 'keeps a secret answer typed at the footer off the screen' do
    at_the_footer("sk-test\r") { |host| host.ask('anthropic api_key', secret: true) }

    refute_includes @pty.transcript, 'sk-test'
  end

  it 'answers nil at the end of input' do
    assert_nil host.ask('Which model?')
  end

  it 'answers the typed line without its newline' do
    assert_equal 'mock/test', host("  mock/test \n").ask('Which model?')
  end

  it 'maps an option number to the option' do
    assert_equal 'token', host("2\n").ask('Sign in with?', options: %w[chain token])
  end

  it 'maps an option number typed at the footer to the option' do
    assert_equal 'token', at_the_footer("2\r") { |host| host.ask('Sign in with?', options: %w[chain token]) }
  end

  it 'keeps a typed option as written' do
    assert_equal 'chain', host("chain\n").ask('Sign in with?', options: %w[chain token])
  end

  it 'keeps a number beyond the options as written' do
    assert_equal '3', host("3\n").ask('Sign in with?', options: %w[chain token])
  end

  it 'keeps a number as written without options' do
    assert_equal '2', host("2\n").ask('Which model?')
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

  it 'shows the confirmation above the footer' do
    at_the_footer("y\r") { |host| host.confirm('Trust this project?') }

    assert_equal ['', 'Trust this project? [y/N]', '› y', '', '›', ''], @pty.screen.rows
  end

  it 'confirms on a yes typed at the footer' do
    assert(at_the_footer("y\r") { |host| host.confirm('Trust this project?') })
  end

  it 'declines on a bare Enter at the footer' do
    refute(at_the_footer("\r") { |host| host.confirm('Trust this project?') })
  end

  it 'prints the notification' do
    host.notify('Extension x failed to load', level: :error)

    assert_includes @output.string, 'Extension x failed to load'
  end

  it 'labels the progress' do
    host.progress('Installing') { nil }

    assert_includes @output.string, 'Installing'
  end

  it 'prints nothing for progress without a label' do
    host.progress { nil }

    assert_empty @output.string
  end

  it 'yields from progress' do
    yielded = false
    host.progress('Installing') { yielded = true }

    assert yielded
  end

  it 'returns from progress without a block' do
    assert_nil host.progress('Installing')
  end
end
