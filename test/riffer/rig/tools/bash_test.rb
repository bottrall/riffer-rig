# frozen_string_literal: true

require 'test_helper'

describe Riffer::Rig::Tools::Bash do
  def setup
    @tool = Riffer::Rig::Tools::Bash.new
    @context = Riffer::Agent::Context.new(cwd: Dir.pwd)
  end

  it 'ends its description with its guidance sentence' do
    assert Riffer::Rig::Tools::Bash.description.end_with?(
      'Use this for exploring and running things: ls, rg or grep, find, tests, git, package managers.'
    )
  end

  it 'is a tool error without a cwd in its context' do
    assert_predicate @tool.call_with_validation(context: nil, command: 'pwd'), :error?
  end

  it 'runs in the cwd in its context' do
    Dir.mktmpdir do |dir|
      response = @tool.call(context: Riffer::Agent::Context.new(cwd: dir), command: 'pwd')

      assert_equal File.realpath(dir), response.content
    end
  end

  it 'non zero exit returns error' do
    response = @tool.call(context: @context, command: 'exit 3')

    assert_predicate response, :error?
  end

  it 'captures command output' do
    response = @tool.call(context: @context, command: 'echo hello')

    assert_equal 'hello', response.content
  end

  it 'reports a command that printed nothing as no output' do
    response = @tool.call(context: @context, command: 'true')

    assert_equal '(no output)', response.content
  end

  def background_context(command_registry)
    Riffer::Agent::Context.new(cwd: Dir.pwd, jobs: command_registry)
  end

  it 'is a tool error without a job registry in its context' do
    response = @tool.call_with_validation(context: @context, command: 'echo hello', run_in_background: true)

    assert_predicate response, :error?
  end

  def output_path(response)
    response.content.split("\n").last.delete_prefix('Output: ')
  end

  def with_background_job(command)
    jobs = Riffer::Rig::Tools::Bash::Jobs.new(Riffer::Rig::Runtime::JobInbox.new)
    response = @tool.call(context: background_context(jobs), command: command, run_in_background: true)
    yield response, jobs
  ensure
    jobs.shutdown
  end

  it 'returns a job id and output path when run_in_background is set' do
    with_background_job('echo hello') do |response, _jobs|
      assert_match(/\AJob \h{8} started in background\nOutput: \S+\z/, response.content)
    end
  end

  it 'returns before a background job finishes' do
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    with_background_job('sleep 5') do
      assert_operator Process.clock_gettime(Process::CLOCK_MONOTONIC) - started, :<, 5
    end
  end

  it 'collects a background job output at the returned path' do
    with_background_job('echo hello') do |response, _jobs|
      path = output_path(response)
      content = ''
      50.times do
        content = File.exist?(path) ? File.read(path) : ''
        break if content.include?('hello')

        sleep 0.02
      end

      assert_includes content, 'hello'
    end
  end

  it 'registers a background job in the context registry' do
    with_background_job('echo hello') do |response, jobs|
      job_id = response.content[/\AJob (\h{8})/, 1]

      assert_includes jobs.list.map(&:id), job_id
    end
  end

  it 'registers a background job with its command' do
    with_background_job('echo hello') do |_response, jobs|
      assert_equal ['echo hello'], jobs.list.map(&:command)
    end
  end

  it 'reads output while the command runs' do
    response = @tool.call(context: @context, command: 'seq 1 200000', timeout_ms: 2000)

    refute_predicate response, :error?
  end

  it 'returns when the command exits though a child still holds its output' do
    response = @tool.call(context: @context, command: '(sleep 2; echo late) & echo hi')

    assert_equal 'hi', response.content
  end

  it 'waits for a command that closed its output' do
    response = @tool.call(context: @context, command: 'exec >&- 2>&-; sleep 0.2; exit 3')

    assert_includes response.content, 'Command exited with status 3'
  end

  it 'replaces bytes that are not valid UTF-8' do
    response = @tool.call(context: @context, command: %q(printf 'ok\377ok\n'))

    assert_equal "ok\u{FFFD}ok", response.content
  end

  it 'times out long running commands' do
    response = @tool.call(context: @context, command: 'sleep 5', timeout_ms: 200)

    assert_includes response.content, '[timed out after 0.2s]'
  end

  it 'reports a whole second timeout without a decimal' do
    response = @tool.call(context: @context, command: 'sleep 5', timeout_ms: 1000)

    assert_includes response.content, '[timed out after 1s]'
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

  it 'reports a command killed by a signal as status 1' do
    response = @tool.call(context: @context, command: 'kill -KILL $$')

    assert_includes response.content, 'Command exited with status 1'
  end

  it 'ignores a flag that is not set' do
    context = Riffer::Agent::Context.new(cwd: Dir.pwd, cancel_flag: Riffer::Rig::Runtime::CancelFlag.new)
    response = @tool.call(context: context, command: 'echo hello')

    assert_equal 'hello', response.content
  end

  it 'truncates output past the byte limit' do
    limit = Riffer::Rig::Tools::Bash::MAX_OUTPUT_BYTES
    response = @tool.call(context: @context, command: "head -c #{limit + 1} /dev/zero | tr '\\0' x")

    assert_equal "#{'x' * limit}\n[output truncated to #{limit} bytes]", response.content
  end

  it 'keeps the timeout marker after truncated output' do
    response = @tool.call(context: @context, command: 'yes', timeout_ms: 200)

    assert response.content.end_with?("bytes]\n[timed out after 0.2s]")
  end

  it 'keeps the cancel marker after truncated output' do
    response = with_cancel_after(0.2) { |context| @tool.call(context: context, command: 'yes') }

    assert response.content.end_with?("bytes]\n[cancelled]")
  end
end
