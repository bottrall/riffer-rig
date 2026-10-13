# frozen_string_literal: true

require 'test_helper'
require 'stringio'

describe Riffer::Rig::Terminal::BlockingPrompter do
  def ask(input, question = 'Which model?', options: nil, secret: false, tty: false)
    @output = StringIO.new
    Riffer::Rig::Terminal::BlockingPrompter.new(
      input: tty ? terminal_input(input) : StringIO.new(input),
      renderer: Riffer::Rig::Terminal::Renderer.new(
        io: @output,
        theme: Riffer::Rig::Terminal::Theme.new(enabled: false)
      )
    ).ask(question, options: options, secret: secret)
  end

  def terminal_input(input)
    Class.new(StringIO) do
      def tty? = true

      def noecho = yield(self)
    end.new(input)
  end

  describe '#ask' do
    it 'prints the question' do
      ask("x\n")

      assert_includes @output.string, 'Which model?'
    end

    it 'lists the options' do
      ask("1\n", 'Sign in with?', options: %w[chain token])

      assert_includes @output.string, '2. token'
    end

    it 'marks a secret question as hidden' do
      ask("sk-test\n", 'anthropic api_key', secret: true)

      assert_includes @output.string, '(hidden)'
    end

    it 'answers the line as typed' do
      assert_equal "mock/test\n", ask("mock/test\n")
    end

    it 'answers nil at the end of input' do
      assert_nil ask('')
    end
  end

  describe '#read_secret' do
    it 'reads a secret answer' do
      assert_equal "sk-test\n", ask("sk-test\n", 'anthropic api_key', secret: true)
    end

    it 'leaves the echoed line of a secret as it is off a terminal' do
      ask("sk-test\n", 'anthropic api_key', secret: true)

      refute_match(/\n\z/, @output.string)
    end

    it 'reads a secret answer typed on a terminal' do
      assert_equal "sk-test\n", ask("sk-test\n", 'anthropic api_key', secret: true, tty: true)
    end

    it 'ends the hidden line on a terminal' do
      ask("sk-test\n", 'anthropic api_key', secret: true, tty: true)

      assert_match(/\n\z/, @output.string)
    end
  end
end
