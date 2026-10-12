# frozen_string_literal: true

require 'test_helper'
require 'stringio'

describe Riffer::Rig::Terminal::Renderer do
  def setup
    @io = StringIO.new
    @renderer = Riffer::Rig::Terminal::Renderer.new(io: @io, theme: Riffer::Rig::Terminal::Theme.new(enabled: false))
  end

  it 'separates prose after the prompt with a blank line' do
    @renderer.prompt
    @io.truncate(0)
    @io.rewind

    @renderer.render(Riffer::StreamEvents::TextDelta.new('hello'))
    @renderer.drain

    assert_equal "\n  hello\n", @io.string
  end

  it 'renders text delta content to the io' do
    @renderer.render(Riffer::StreamEvents::TextDelta.new('hello'))
    @renderer.drain

    assert_equal "  hello\n", @io.string
  end

  it 'indents prose on the left' do
    @renderer.render(Riffer::StreamEvents::TextDelta.new('hello'))
    @renderer.drain

    assert @io.string.lines.first.start_with?('  ')
  end

  it 'does not stack blank lines between consecutive prose deltas' do
    @renderer.render(Riffer::StreamEvents::TextDelta.new('hello '))
    @renderer.render(Riffer::StreamEvents::TextDelta.new('world'))
    @renderer.drain

    assert_equal "  hello world\n", @io.string
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

  it 'holds an unfinished prose line back from the smoother' do
    renderer = Riffer::Rig::Terminal::Renderer.new(
      io: @io,
      theme: Riffer::Rig::Terminal::Theme.new(enabled: false),
      smoother: recording_smoother
    )

    renderer.render(Riffer::StreamEvents::TextDelta.new('hello'))

    assert_empty recording_smoother.written
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

  it 'drains the smoother before rendering a tool call done event' do
    renderer = Riffer::Rig::Terminal::Renderer.new(
      io: @io,
      theme: Riffer::Rig::Terminal::Theme.new(enabled: false),
      smoother: recording_smoother
    )

    renderer.render(Riffer::StreamEvents::ToolCallDone.new(item_id: 'i1', call_id: 'c1', name: 'read', arguments: '{}'))

    assert_predicate recording_smoother, :drained?
  end

  it 'renders tool call done as an indented block below a blank line' do
    @renderer.render(
      Riffer::StreamEvents::ToolCallDone.new(
        item_id: 'i1',
        call_id: 'c1',
        name: 'read',
        arguments: '{}'
      )
    )

    assert_equal "\n    ⚙ read()\n", @io.string
  end

  it 'renders tool call arguments as key and value pairs' do
    @renderer.render(
      Riffer::StreamEvents::ToolCallDone.new(
        item_id: 'i1',
        call_id: 'c1',
        name: 'read',
        arguments: JSON.generate(path: 'a.rb', limit: 5)
      )
    )

    assert_equal "\n    ⚙ read(path: \"a.rb\", limit: 5)\n", @io.string
  end

  it 'truncates long tool call argument values' do
    @renderer.render(
      Riffer::StreamEvents::ToolCallDone.new(
        item_id: 'i1',
        call_id: 'c1',
        name: 'read',
        arguments: JSON.generate(path: 'a' * 200)
      )
    )

    refute_includes @io.string, 'a' * 200
  end

  it 'renders unparseable tool call arguments verbatim' do
    @renderer.render(
      Riffer::StreamEvents::ToolCallDone.new(item_id: 'i1', call_id: 'c1', name: 'read', arguments: 'not json')
    )

    assert_equal "\n    ⚙ read(not json)\n", @io.string
  end

  it 'fits tool call lines to the terminal width' do
    renderer = Riffer::Rig::Terminal::Renderer.new(
      io: @io,
      theme: Riffer::Rig::Terminal::Theme.new(enabled: false),
      width: 20
    )

    renderer.render(
      Riffer::StreamEvents::ToolCallDone.new(
        item_id: 'i1',
        call_id: 'c1',
        name: 'read',
        arguments: JSON.generate(path: 'a' * 40)
      )
    )

    assert_operator @io.string.lines.last.chomp.length, :<=, 20
  end

  it 'marks a fitted tool call line with an ellipsis' do
    renderer = Riffer::Rig::Terminal::Renderer.new(
      io: @io,
      theme: Riffer::Rig::Terminal::Theme.new(enabled: false),
      width: 20
    )

    renderer.render(
      Riffer::StreamEvents::ToolCallDone.new(
        item_id: 'i1',
        call_id: 'c1',
        name: 'read',
        arguments: JSON.generate(path: 'a' * 40)
      )
    )

    assert @io.string.lines.last.chomp.end_with?('…')
  end

  it 'reduces a tool call line to an ellipsis when the width leaves no room' do
    renderer = Riffer::Rig::Terminal::Renderer.new(
      io: @io,
      theme: Riffer::Rig::Terminal::Theme.new(enabled: false),
      width: 4
    )

    renderer.render(Riffer::StreamEvents::ToolCallDone.new(item_id: 'i1', call_id: 'c1', name: 'read', arguments: '{}'))

    assert_equal "\n    …\n", @io.string
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

  it 'renders an interrupt at column zero with a blank line above' do
    @renderer.render(Riffer::StreamEvents::Interrupt.new(reason: 'user'))

    assert_equal "\n[interrupted: user]\n", @io.string
  end

  it 'ignores token usage done' do
    @renderer.render(Riffer::StreamEvents::TokenUsageDone.new(token_usage: usage(100, 50)))

    assert_empty @io.string
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

  it 'renders skill activation at column zero with a blank line above' do
    @renderer.skill('refactor')

    assert_equal "\n✦ skill: refactor\n", @io.string
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

  it 'renders nothing when the turn reported no usage' do
    @renderer.usage(nil, usage(100, 50))

    assert_empty @io.string
  end

  it 'renders nothing when the session reported no usage' do
    @renderer.usage(usage(100, 50), nil)

    assert_empty @io.string
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

  it 'renders the turn usage and session total as one stats block' do
    @renderer.usage(usage(100, 50, cache_read_tokens: 200), usage(300, 150))

    assert_equal "\n  ↑100 · ↓50 · cache_read:200 · session 450 tok\n", @io.string
  end

  it 'renders cache write token count when present' do
    @renderer.usage(usage(100, 50, cache_write_tokens: 400), usage(100, 50))

    assert_includes @io.string, 'cache_write:400'
  end

  it 'omits a zero cache write token count' do
    @renderer.usage(usage(100, 50, cache_write_tokens: 0), usage(100, 50))

    refute_includes @io.string, 'cache_write'
  end

  it 'omits a zero cache read token count' do
    @renderer.usage(usage(100, 50, cache_read_tokens: 0), usage(100, 50))

    refute_includes @io.string, 'cache_read'
  end

  it 'renders the session cost when the session is priced' do
    @renderer.usage(usage(100, 50), Riffer::Providers::TokenUsage.new(input_tokens: 100, output_tokens: 50, cost: 0.25))

    assert_includes @io.string, '~$0.2500'
  end

  it 'omits the cost when the session is unpriced' do
    @renderer.usage(usage(100, 50), usage(100, 50))

    refute_includes @io.string, '~$'
  end

  it 'renders the prompt marker below a blank line' do
    @renderer.prompt

    assert_equal "\n› ", @io.string
  end

  it 'drains the smoother before rendering a question' do
    renderer = Riffer::Rig::Terminal::Renderer.new(
      io: @io,
      theme: Riffer::Rig::Terminal::Theme.new(enabled: false),
      smoother: recording_smoother
    )

    renderer.question('Pick one', nil, false)

    assert_predicate recording_smoother, :drained?
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

  it 'hides the cursor when a turn begins' do
    renderer = Riffer::Rig::Terminal::Renderer.new(
      io: @io,
      theme: Riffer::Rig::Terminal::Theme.new(enabled: false),
      cursor: recording_cursor
    )

    renderer.begin_turn

    assert_equal [:hide], recording_cursor.calls
  end

  it 'starts the smoother when a turn begins' do
    renderer = Riffer::Rig::Terminal::Renderer.new(
      io: @io,
      theme: Riffer::Rig::Terminal::Theme.new(enabled: false),
      smoother: recording_smoother
    )

    renderer.begin_turn

    assert_predicate recording_smoother, :started?
  end

  it 'flushes buffered prose to the smoother when a turn ends' do
    renderer = Riffer::Rig::Terminal::Renderer.new(
      io: @io,
      theme: Riffer::Rig::Terminal::Theme.new(enabled: false),
      smoother: recording_smoother
    )
    renderer.render(Riffer::StreamEvents::TextDelta.new('hello'))

    renderer.end_turn

    assert_equal ["  hello\n"], recording_smoother.written
  end

  it 'finishes the smoother when a turn ends' do
    renderer = Riffer::Rig::Terminal::Renderer.new(
      io: @io,
      theme: Riffer::Rig::Terminal::Theme.new(enabled: false),
      smoother: recording_smoother
    )

    renderer.end_turn

    assert_predicate recording_smoother, :finished?
  end

  it 'shows the cursor when a turn ends' do
    renderer = Riffer::Rig::Terminal::Renderer.new(
      io: @io,
      theme: Riffer::Rig::Terminal::Theme.new(enabled: false),
      cursor: recording_cursor
    )

    renderer.end_turn

    assert_equal [:show], recording_cursor.calls
  end

  it 'ignores a message that is not a tool result' do
    @renderer.render_tool_result(Riffer::Messages::User.new('hello'))

    assert_empty @io.string
  end

  it 'drains the smoother before rendering a tool result' do
    renderer = Riffer::Rig::Terminal::Renderer.new(
      io: @io,
      theme: Riffer::Rig::Terminal::Theme.new(enabled: false),
      smoother: recording_smoother
    )

    renderer.render_tool_result(Riffer::Messages::Tool.new('done', tool_call_id: 'c1', name: 'write'))

    assert_predicate recording_smoother, :drained?
  end

  it 'renders tool results tight under their tool call' do
    message = Riffer::Messages::Tool.new('done', tool_call_id: 'c1', name: 'write')
    @renderer.render(
      Riffer::StreamEvents::ToolCallDone.new(item_id: 'i1', call_id: 'c1', name: 'write', arguments: '{}')
    )
    @renderer.render_tool_result(message)

    assert_equal "\n    ⚙ write()\n      ↳ done\n", @io.string
  end

  it 'previews only the first line of a tool result' do
    @renderer.render_tool_result(Riffer::Messages::Tool.new("one\ntwo", tool_call_id: 'c1', name: 'read'))

    assert_equal "\n      ↳ one\n", @io.string
  end

  it 'elides a long tool result preview' do
    @renderer.render_tool_result(Riffer::Messages::Tool.new('x' * 300, tool_call_id: 'c1', name: 'read'))

    assert_equal "\n      ↳ #{'x' * 199}…\n", @io.string
  end

  it 'fits tool result lines to the terminal width' do
    renderer = Riffer::Rig::Terminal::Renderer.new(
      io: @io,
      theme: Riffer::Rig::Terminal::Theme.new(enabled: false),
      width: 15
    )

    renderer.render_tool_result(Riffer::Messages::Tool.new('x' * 40, tool_call_id: 'c1', name: 'write'))

    assert_operator @io.string.lines.last.chomp.length, :<=, 15
  end

  it 'renders a failed tool result in red' do
    theme = Riffer::Rig::Terminal::Theme.new(enabled: true)
    renderer = Riffer::Rig::Terminal::Renderer.new(io: @io, theme: theme)

    renderer.render_tool_result(Riffer::Messages::Tool.new('nope', tool_call_id: 'c1', name: 'read', error: 'nope'))

    assert_equal "\n      #{theme.red('↳ nope')}\n", @io.string
  end

  it 'renders a successful tool result dimmed' do
    theme = Riffer::Rig::Terminal::Theme.new(enabled: true)
    renderer = Riffer::Rig::Terminal::Renderer.new(io: @io, theme: theme)

    renderer.render_tool_result(Riffer::Messages::Tool.new('done', tool_call_id: 'c1', name: 'read'))

    assert_equal "\n      #{theme.dim('↳ done')}\n", @io.string
  end

  it 'renders tool results without ansi when theme disabled' do
    message = Riffer::Messages::Tool.new('done', tool_call_id: 'c1', name: 'write')
    @renderer.render_tool_result(message)

    refute_includes @io.string, "\e["
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

  it 'ignores an io reporting zero columns' do
    io = StringIO.new
    def io.tty? = true

    def io.winsize = [24, 0]
    renderer = Riffer::Rig::Terminal::Renderer.new(io: io, theme: Riffer::Rig::Terminal::Theme.new(enabled: false))

    renderer.render(Riffer::StreamEvents::TextDelta.new('hello'))
    renderer.drain

    assert_equal "  hello\n", io.string
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

      def start = @started = true

      def started? = @started == true

      def drain = @drained = true

      def drained? = @drained == true

      def finish = @finished = true

      def finished? = @finished == true
    end.new
  end

  def recording_cursor
    @recording_cursor ||= Class.new do
      attr_reader :calls

      def initialize = @calls = []

      def hide = @calls << :hide

      def show = @calls << :show
    end.new
  end
end
