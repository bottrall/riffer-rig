# frozen_string_literal: true

require 'test_helper'

describe Riffer::Rig::Tools::Read do
  def setup
    @tool = Riffer::Rig::Tools::Read.new
  end

  it 'reads file contents with line numbers' do
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        File.write('greeting.txt', "hello\nworld")
        response = @tool.call(context: nil, path: 'greeting.txt')

        assert_includes response.content, "1\thello"
      end
    end
  end

  it 'offset and limit select a slice' do
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        File.write('lines.txt', (1..10).map { |n| "line#{n}" }.join("\n"))
        response = @tool.call(context: nil, path: 'lines.txt', offset: 3, limit: 1)

        assert_equal "     3\tline3", response.content
      end
    end
  end

  it 'missing file returns error' do
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        response = @tool.call(context: nil, path: 'nope.txt')

        assert_predicate response, :error?
      end
    end
  end

  it 'offset below one returns error' do
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        File.write('lines.txt', "a\nb\nc")
        response = @tool.call(context: nil, path: 'lines.txt', offset: 0)

        assert_predicate response, :error?
      end
    end
  end
end
