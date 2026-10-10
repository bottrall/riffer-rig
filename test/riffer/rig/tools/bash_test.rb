# frozen_string_literal: true

require 'test_helper'

describe Riffer::Rig::Tools::Bash do
  def setup
    @tool = Riffer::Rig::Tools::Bash.new
    @context = Riffer::Agent::Context.new(cwd: Dir.pwd)
  end

  it 'captures command output' do
    response = @tool.call(context: @context, command: 'echo hello')

    assert_equal 'hello', response.content
  end

  it 'is a tool error without a cwd in its context' do
    assert_predicate @tool.call_with_validation(context: nil, command: 'pwd'), :error?
  end

  it 'non zero exit returns error' do
    response = @tool.call(context: @context, command: 'exit 3')

    assert_predicate response, :error?
  end

  it 'times out long running commands' do
    response = @tool.call(context: @context, command: 'sleep 5', timeout_ms: 200)

    assert_includes response.content, 'timed out'
  end

  def with_cancel_after(seconds)
    flag = Riffer::Rig::Runtime::CancelFlag.new
    canceller = Thread.new do
      sleep seconds
      flag.set
    end
    yield Riffer::Agent::Context.new(cwd: Dir.pwd, cancel_flag: flag)
  ensure
    canceller.join
  end

  it 'returns within a second of the cancel' do
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    with_cancel_after(0.2) { |context| @tool.call(context: context, command: 'sleep 30') }

    assert_operator Process.clock_gettime(Process::CLOCK_MONOTONIC) - started, :<, 1.2
  end

  it 'reports the cancel as a tool error' do
    response = with_cancel_after(0.2) { |context| @tool.call_with_validation(context: context, command: 'sleep 30') }

    assert_predicate response, :error?
  end

  it 'tells the model the command was cancelled' do
    response = with_cancel_after(0.2) { |context| @tool.call_with_validation(context: context, command: 'sleep 30') }

    assert_includes response.content, '[cancelled]'
  end

  it 'ignores a flag that is not set' do
    context = Riffer::Agent::Context.new(cwd: Dir.pwd, cancel_flag: Riffer::Rig::Runtime::CancelFlag.new)
    response = @tool.call(context: context, command: 'echo hello')

    assert_equal 'hello', response.content
  end

  def background_context(command_registry)
    Riffer::Agent::Context.new(cwd: Dir.pwd, jobs: command_registry)
  end

  it 'returns a job id and output path when run_in_background is set' do
    response = @tool.call(
      context: background_context(Riffer::Rig::Tools::Bash::Jobs.new),
      command: 'echo hello',
      run_in_background: true
    )

    assert_match(/\AJob \h{8} started in background\nOutput: \S+\z/, response.content)
  end

  it 'returns before a background job finishes' do
    jobs = Riffer::Rig::Tools::Bash::Jobs.new
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    @tool.call(context: background_context(jobs), command: 'sleep 5', run_in_background: true)

    assert_operator Process.clock_gettime(Process::CLOCK_MONOTONIC) - started, :<, 5
  ensure
    jobs&.kill_outstanding
  end

  it 'collects a background job output at the returned path' do
    jobs = Riffer::Rig::Tools::Bash::Jobs.new
    response = @tool.call(context: background_context(jobs), command: 'echo hello', run_in_background: true)
    path = response.content.split("\n").last.delete_prefix('Output: ')
    content = ''
    50.times do
      content = File.exist?(path) ? File.read(path) : ''
      break if content.include?('hello')

      sleep 0.02
    end

    assert_includes content, 'hello'
  ensure
    jobs&.kill_outstanding
  end

  it 'registers a background job in the context registry' do
    jobs = Riffer::Rig::Tools::Bash::Jobs.new
    response = @tool.call(context: background_context(jobs), command: 'echo hello', run_in_background: true)
    job_id = response.content[/\AJob (\h{8})/, 1]

    assert_includes jobs.list.map(&:id), job_id
  ensure
    jobs&.kill_outstanding
  end

  it 'is a tool error without a job registry in its context' do
    response = @tool.call_with_validation(context: @context, command: 'echo hello', run_in_background: true)

    assert_predicate response, :error?
  end

  def test_kill_group_returns_the_childs_process_group_id
    pid = Process.spawn('sleep 5', pgroup: true)

    pgid = @tool.send(:kill_group, pid)

    refute_equal Process.getpgid(Process.pid), pgid
  ensure
    begin
      Process.kill('KILL', -Process.getpgid(pid)) if pid
    rescue Errno::ESRCH
      nil
    end
  end

  def test_kill_group_pgids_are_positive
    pid = Process.spawn('sleep 5', pgroup: true)

    pgid = @tool.send(:kill_group, pid)

    assert_operator pgid, :positive?
  ensure
    begin
      Process.kill('KILL', -Process.getpgid(pid)) if pid
    rescue Errno::ESRCH
      nil
    end
  end

  def test_kill_group_returns_zero_when_the_group_is_gone
    assert_equal 0, @tool.send(:kill_group, -1)
  end

  it 'ends its description with its guidance sentence' do
    assert Riffer::Rig::Tools::Bash.description.end_with?(
      'Use this for exploring and running things: ls, rg or grep, find, tests, git, package managers.'
    )
  end

  it 'runs in the cwd in its context' do
    Dir.mktmpdir do |dir|
      response = @tool.call(context: Riffer::Agent::Context.new(cwd: dir), command: 'pwd')

      assert_equal File.realpath(dir), response.content
    end
  end
end
