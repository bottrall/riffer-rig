# frozen_string_literal: true

require 'test_helper'
require 'stringio'

describe Riffer::Rig::Terminal::Renderer do
  def setup
    @io = StringIO.new
    @renderer = Riffer::Rig::Terminal::Renderer.new(io: @io, theme: Riffer::Rig::Terminal::Theme.new(enabled: false))
  end

  it 'renders text delta content to the io' do
    @renderer.render(Riffer::StreamEvents::TextDelta.new('hello'))
    @renderer.drain

    assert_equal "  hello\n", @io.string
  end

  it 'separates prose after the prompt with a blank line' do
    @renderer.prompt
    @io.truncate(0)
    @io.rewind

    @renderer.render(Riffer::StreamEvents::TextDelta.new('hello'))
    @renderer.drain

    assert_equal "\n  hello\n", @io.string
  end

  it 'does not stack blank lines between consecutive prose deltas' do
    @renderer.render(Riffer::StreamEvents::TextDelta.new('hello '))
    @renderer.render(Riffer::StreamEvents::TextDelta.new('world'))
    @renderer.drain

    assert_equal "  hello world\n", @io.string
  end

  it 'routes text deltas through the smoother when one is present' do
    renderer = Riffer::Rig::Terminal::Renderer.new(
      io: @io,
      theme: Riffer::Rig::Terminal::Theme.new(enabled: false),
      smoother: recording_smoother
    )

    renderer.render(Riffer::StreamEvents::TextDelta.new("hello\n"))

    assert_equal ["  hello\n"], recording_smoother.written
  end

  it 'wraps prose at the terminal width' do
    renderer = Riffer::Rig::Terminal::Renderer.new(
      io: @io,
      theme: Riffer::Rig::Terminal::Theme.new(enabled: false),
      width: 20
    )

    renderer.render(Riffer::StreamEvents::TextDelta.new('one two three four five'))
    renderer.drain

    assert(@io.string.lines.all? { |line| line.chomp.length <= 20 })
  end

  it 'loads io-console so IO#winsize exists' do
    assert_includes IO.instance_methods, :winsize
  end

  it 'detects the width from a tty io' do
    io = StringIO.new
    def io.tty? = true

    def io.winsize = [24, 20]
    renderer = Riffer::Rig::Terminal::Renderer.new(io: io, theme: Riffer::Rig::Terminal::Theme.new(enabled: false))

    renderer.render(Riffer::StreamEvents::TextDelta.new('one two three four five'))
    renderer.drain

    assert(io.string.lines.all? { |line| line.chomp.length <= 20 })
  end

  it 'ignores an io whose winsize raises' do
    io = StringIO.new
    def io.tty? = true

    def io.winsize = raise Errno::ENOTTY
    renderer = Riffer::Rig::Terminal::Renderer.new(io: io, theme: Riffer::Rig::Terminal::Theme.new(enabled: false))

    renderer.render(Riffer::StreamEvents::TextDelta.new('hello'))
    renderer.drain

    assert_equal "  hello\n", io.string
  end

  it 'ignores an io reporting zero columns' do
    io = StringIO.new
    def io.tty? = true

    def io.winsize = [24, 0]
    renderer = Riffer::Rig::Terminal::Renderer.new(io: io, theme: Riffer::Rig::Terminal::Theme.new(enabled: false))

    renderer.render(Riffer::StreamEvents::TextDelta.new('hello'))
    renderer.drain

    assert_equal "  hello\n", io.string
  end

  it 'indents prose on the left' do
    @renderer.render(Riffer::StreamEvents::TextDelta.new('hello'))
    @renderer.drain

    assert @io.string.lines.first.start_with?('  ')
  end

  it 'drains the smoother before rendering a tool call done event' do
    renderer = Riffer::Rig::Terminal::Renderer.new(
      io: @io,
      theme: Riffer::Rig::Terminal::Theme.new(enabled: false),
      smoother: recording_smoother
    )

    renderer.render(Riffer::StreamEvents::ToolCallDone.new(item_id: 'i1', call_id: 'c1', name: 'read', arguments: '{}'))

    assert_predicate recording_smoother, :drained?
  end

  it 'drains the smoother before rendering a skill activation' do
    renderer = Riffer::Rig::Terminal::Renderer.new(
      io: @io,
      theme: Riffer::Rig::Terminal::Theme.new(enabled: false),
      smoother: recording_smoother
    )

    renderer.skill('refactor')

    assert_predicate recording_smoother, :drained?
  end

  it 'drains the smoother before rendering an interrupt event' do
    renderer = Riffer::Rig::Terminal::Renderer.new(
      io: @io,
      theme: Riffer::Rig::Terminal::Theme.new(enabled: false),
      smoother: recording_smoother
    )

    renderer.render(Riffer::StreamEvents::Interrupt.new(reason: 'user'))

    assert_predicate recording_smoother, :drained?
  end

  it 'drains the smoother before rendering usage' do
    renderer = Riffer::Rig::Terminal::Renderer.new(
      io: @io,
      theme: Riffer::Rig::Terminal::Theme.new(enabled: false),
      smoother: recording_smoother
    )

    renderer.usage(usage(1, 1), usage(1, 1))

    assert_predicate recording_smoother, :drained?
  end

  it 'records a tool call without printing it' do
    @renderer.render(
      Riffer::StreamEvents::ToolCallDone.new(
        item_id: 'i1',
        call_id: 'c1',
        name: 'read',
        arguments: '{}'
      )
    )

    assert_empty @io.string
  end

  it 'opens a gap in the prose around a tool call' do
    @renderer.render(Riffer::StreamEvents::TextDelta.new('before'))
    @renderer.render(
      Riffer::StreamEvents::ToolCallDone.new(item_id: 'i1', call_id: 'c1', name: 'read', arguments: '{}')
    )
    @renderer.render(Riffer::StreamEvents::TextDelta.new('after'))
    @renderer.drain

    assert_equal "  before\n\n  after\n", @io.string
  end

  it 'summarizes a tool call with its arguments for the status line' do
    detail = @renderer.tool_detail('read', JSON.generate(path: 'a.rb', limit: 5))

    assert_includes detail, 'read('
    assert_includes detail, 'path: "a.rb"'
  end

  it 'falls back to raw arguments the status line cannot parse' do
    assert_equal 'read(oops)', @renderer.tool_detail('read', 'oops')
  end

  it 'elides long tool call details to the status line limit' do
    detail = @renderer.tool_detail('read', JSON.generate(path: 'a' * 200))

    assert_operator detail.length, :<=, Riffer::Rig::Terminal::Renderer::DETAIL_LIMIT
    refute_includes detail, 'a' * 200
    assert detail.end_with?('…')
  end

  it 'prints failing tool results as an error line' do
    message = Riffer::Messages::Tool.new('boom', tool_call_id: 'c1', name: 'write', error: 'nope')
    @renderer.render_tool_result(message)

    assert_equal "\n      ✗ boom\n", @io.string
  end

  it 'silences successful tool results' do
    message = Riffer::Messages::Tool.new('done', tool_call_id: 'c1', name: 'write')
    @renderer.render_tool_result(message)

    assert_empty @io.string
  end

  it 'fits failing tool result lines to the terminal width' do
    renderer = Riffer::Rig::Terminal::Renderer.new(
      io: @io,
      theme: Riffer::Rig::Terminal::Theme.new(enabled: false),
      width: 15
    )
    message = Riffer::Messages::Tool.new('x' * 40, tool_call_id: 'c1', name: 'write', error: 'nope')

    renderer.render_tool_result(message)

    assert_operator @io.string.lines.last.chomp.length, :<=, 15
  end

  it 'renders skill activation at column zero with a blank line above' do
    @renderer.skill('refactor')

    assert_equal "\n✦ skill: refactor\n", @io.string
  end

  it 'renders the turn as one dim summary line' do
    tool_call = ->(name, id) { Riffer::StreamEvents::ToolCallDone.new(item_id: id, call_id: id, name: name, arguments: '{}') }
    @renderer.render(tool_call.call('read', 'i1'))
    @renderer.render(tool_call.call('read', 'i2'))
    @renderer.render(tool_call.call('bash', 'i3'))
    @renderer.usage(usage(100, 50, cache_read_tokens: 200), usage(300, 150))

    lines = @io.string.lines

    assert_equal 2, lines.length
    assert(lines.last.chomp.start_with?('3 calls read×2 bash · '))
    assert_includes lines.last, '↑100 ↓50 cache_read:200'
    assert_includes lines.last, 'session 450 tok'
  end

  it 'renders nothing when the turn has nothing to report' do
    @renderer.usage(nil, usage(100, 50))

    assert_empty @io.string
  end

  it 'drains the smoother before rendering a tool result' do
    renderer = Riffer::Rig::Terminal::Renderer.new(
      io: @io,
      theme: Riffer::Rig::Terminal::Theme.new(enabled: false),
      smoother: recording_smoother
    )

    message = Riffer::Messages::Tool.new('done', tool_call_id: 'c1', name: 'write', error: 'nope')
    renderer.render_tool_result(message)

    assert_predicate recording_smoother, :drained?
  end

  def usage(input, output, **cache)
    Riffer::Providers::TokenUsage.new(input_tokens: input, output_tokens: output, **cache)
  end

  def recording_smoother
    @recording_smoother ||= Class.new do
      attr_reader :written

      def initialize = @written = []

      def <<(content)
        @written << content
        self
      end

      def start = nil

      def drain = @drained = true

      def drained? = @drained == true

      def finish = nil
    end.new
  end

  it 'renders failing tool results without ansi when theme disabled' do
    message = Riffer::Messages::Tool.new('done', tool_call_id: 'c1', name: 'write', error: 'nope')
    @renderer.render_tool_result(message)

    refute_includes @io.string, "\e["
  end

  it 'ignores token usage done' do
    @renderer.render(Riffer::StreamEvents::TokenUsageDone.new(token_usage: usage(100, 50)))

    assert_empty @io.string
  end

  it 'renders cache write token count when present' do
    @renderer.usage(usage(100, 50, cache_write_tokens: 400), usage(100, 50))

    assert_includes @io.string, 'cache_write:400'
  end

  it 'renders the session cost when the session is priced' do
    @renderer.usage(usage(100, 50), Riffer::Providers::TokenUsage.new(input_tokens: 100, output_tokens: 50, cost: 0.25))

    assert_includes @io.string, '~$0.2500'
  end

  it 'omits the cost when the session is unpriced' do
    @renderer.usage(usage(100, 50), usage(100, 50))

    refute_includes @io.string, '~$'
  end

  it 'renders an error in its own block' do
    @renderer.error('boom')

    assert_equal "\nboom\n", @io.string
  end

  it 'renders a question with numbered options' do
    @renderer.question('Pick one', %w[chain token], false)

    assert_equal "\nPick one\n  1. chain\n  2. token\n› ", @io.string
  end

  it 'marks a secret question as hidden' do
    @renderer.question('anthropic api_key', nil, true)

    assert_includes @io.string, '(hidden)'
  end
end
