# frozen_string_literal: true

require 'test_helper'
require_relative '../../../support/frame_pty'

describe Riffer::Rig::Terminal::FramePrompter do
  def teardown
    @frame.stop
    @pty.close
  end

  def key(name, text = nil) = Riffer::Rig::Terminal::Key.new(name, text)

  def typed(text) = text.chars.map { |char| key(:text, char) }

  def ask(keys, question = 'Which model?', options: nil, secret: false, color: false)
    @pty = FramePty.new(columns: 40, rows: 10)
    theme = Riffer::Rig::Terminal::Theme.new(enabled: color)
    @frame = Riffer::Rig::Terminal::Frame.new(io: @pty.slave, theme: theme)
    @frame.start
    queue = Queue.new
    keys.each { |pressed| queue << pressed }
    # The keys close behind the last one, so an ask that outlives them answers
    # nil instead of waiting.
    queue.close
    Riffer::Rig::Terminal::FramePrompter.new(frame: @frame, keys: queue, theme: theme)
                                        .ask(question, options: options, secret: secret)
  end

  def footer = ['', '›', '']

  describe '#ask' do
    it 'shows the question above the footer, below a blank line' do
      ask([])

      assert_equal ['', 'Which model?', *footer], @pty.screen.rows
    end

    it 'numbers the options under the question' do
      ask([], 'Sign in with?', options: %w[chain token])

      assert_equal ['', 'Sign in with?', '  1. chain', '  2. token', *footer], @pty.screen.rows
    end

    it 'wraps the question to the width of the frame' do
      ask([], 'Resume a session — type to filter, Enter switches on a single match')

      assert_equal ['Resume a session — type to filter,', '  Enter switches on a single match'], @pty.screen.rows[1, 2]
    end

    it 'marks a secret question as hidden' do
      ask([], 'anthropic api_key', secret: true)

      assert_equal ['', 'anthropic api_key', '(hidden)', *footer], @pty.screen.rows
    end

    it 'greys the hidden mark when color is on' do
      ask([], 'anthropic api_key', secret: true, color: true)

      assert_includes @pty.transcript, "\e[38;2;138;139;154m(hidden)\e[0m"
    end

    it 'adds nothing to the scrollback for a line that was never entered' do
      ask(typed('abc'))

      assert_equal ['', 'Which model?', *footer], @pty.screen.rows
    end

    it 'leaves the answer in the scrollback' do
      ask([*typed('ac'), key(:left), *typed('b'), key(:enter)])

      assert_equal ['', 'Which model?', '› abc', *footer], @pty.screen.rows
    end

    it 'shows control characters in the answer as pictures' do
      ask([key(:paste, "a\tb"), key(:enter)])

      assert_includes @pty.screen.rows, '› a␉b'
    end

    it 'paints the prompt of the answer when color is on' do
      ask([*typed('abc'), key(:enter)], color: true)
      prompt = "\e[38;2;255;106;193m›\e[0m"

      assert_includes @pty.transcript, "#{prompt} abc\r\n\r\n#{prompt} \r\n"
    end

    it 'leaves a secret answer out of the scrollback' do
      ask([*typed('sk-test'), key(:enter)], 'anthropic api_key', secret: true)

      assert_equal ['', 'anthropic api_key', '(hidden)', *footer], @pty.screen.rows
    end

    it 'answers the text either side of the cursor' do
      assert_equal 'abc', ask([*typed('ac'), key(:left), *typed('b'), key(:enter)])
    end
  end

  describe '#read' do
    it 'shows the hint on the status line while the line is read' do
      ask([])

      assert_includes @pty.transcript, "› \r\n  answer above · Ctrl-C cancels\e[1A"
    end

    it 'dims the hint when color is on' do
      ask([], color: true)

      assert_includes @pty.transcript, "\e[2manswer above · Ctrl-C cancels\e[0m"
    end

    it 'answers nil when the keys close' do
      assert_nil ask([])
    end

    it 'answers nil on Ctrl-D' do
      assert_nil ask([*typed('abc'), key(:ctrl_d), key(:enter)])
    end

    it 'raises Interrupt on Ctrl-C' do
      assert_raises(Interrupt) { ask([*typed('abc'), key(:ctrl_c), key(:enter)]) }
    end

    it 'answers an empty line on a bare Enter' do
      assert_equal '', ask([key(:enter)])
    end

    it 'draws the line on the footer as it is typed' do
      ask(typed('abc'))

      assert_includes @pty.transcript, "› abc\r\n  answer above · Ctrl-C cancels\e[1A"
    end

    it 'never draws a secret line' do
      ask([*typed('sk-test'), key(:enter)], 'anthropic api_key', secret: true)

      refute_includes @pty.transcript, 'sk-test'
    end

    it 'answers the secret line' do
      assert_equal 'sk-test', ask([*typed('sk-test'), key(:enter)], 'anthropic api_key', secret: true)
    end

    it 'clears the footer once the line is entered' do
      ask([*typed('abc'), key(:enter)])

      assert_equal footer, @pty.screen.rows.last(3)
    end

    it 'clears the footer when the line is abandoned' do
      ask([*typed('abc'), key(:ctrl_d)])

      assert_equal footer, @pty.screen.rows.last(3)
    end

    it 'clears the footer when Ctrl-C raises' do
      begin
        ask([*typed('abc'), key(:ctrl_c)])
      rescue Interrupt
        nil
      end

      assert_equal footer, @pty.screen.rows.last(3)
    end
  end
end
