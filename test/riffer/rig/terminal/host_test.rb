# frozen_string_literal: true

require 'test_helper'
require 'stringio'

describe Riffer::Rig::Terminal::Host do
  def host(input = '', animator: nil, tty: false)
    @output = StringIO.new
    theme = Riffer::Rig::Terminal::Theme.new(enabled: false)
    Riffer::Rig::Terminal::Host.new(
      input: tty ? terminal_input(input) : StringIO.new(input),
      renderer: Riffer::Rig::Terminal::Renderer.new(io: @output, theme: theme),
      animator: animator || Riffer::Rig::Terminal::Animator.new(io: @output, theme: theme)
    )
  end

  def terminal_input(input)
    Class.new(StringIO) do
      def tty? = true

      def noecho = yield(self)
    end.new(input)
  end

  def recording_animator
    Class.new do
      attr_reader :calls

      def initialize
        @calls = []
      end

      def start = @calls << :start

      def stop = @calls << :stop
    end.new
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

  it 'reads a secret answer typed on a terminal' do
    assert_equal 'sk-test', host("sk-test\n", tty: true).ask('anthropic api_key', secret: true)
  end

  it 'ends the hidden line on a terminal' do
    host("sk-test\n", tty: true).ask('anthropic api_key', secret: true)

    assert_match(/\n\z/, @output.string)
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

  it 'renders a notify as its own line' do
    host.notify('Extension x failed to load', level: :error)

    assert_equal "\nExtension x failed to load\n", @output.string
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

  it 'stops the animator when the block exits early' do
    animator = recording_animator
    catch(:leave) { host(animator: animator).progress('Installing') { throw :leave } }

    assert_equal %i[start stop], animator.calls
  end
end
