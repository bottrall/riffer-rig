# frozen_string_literal: true

require 'test_helper'

describe Riffer::Rig::Tools::Bash do
  def setup
    @tool = Riffer::Rig::Tools::Bash.new
  end

  it 'captures command output' do
    response = @tool.call(context: nil, command: 'echo hello')

    assert_equal 'hello', response.content
  end

  it 'runs in the working directory' do
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        File.write('marker.txt', '')
        response = @tool.call(context: nil, command: 'ls')

        assert_includes response.content, 'marker.txt'
      end
    end
  end

  it 'non zero exit returns error' do
    response = @tool.call(context: nil, command: 'exit 3')

    assert_predicate response, :error?
  end

  it 'times out long running commands' do
    response = @tool.call(context: nil, command: 'sleep 5', timeout_ms: 200)

    assert_includes response.content, 'timed out'
  end
end
