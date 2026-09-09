# frozen_string_literal: true

require 'test_helper'

describe Riffer::Rig::Tools::Write do
  def setup
    @tool = Riffer::Rig::Tools::Write.new
  end

  it 'writes content to a file' do
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        @tool.call(context: nil, path: 'out.txt', content: 'hello')

        assert_equal 'hello', File.read('out.txt')
      end
    end
  end

  it 'creates missing parent directories' do
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        @tool.call(context: nil, path: 'nested/deep/out.txt', content: 'hi')

        assert_path_exists 'nested/deep/out.txt'
      end
    end
  end

  it 'returns a success response' do
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        response = @tool.call(context: nil, path: 'out.txt', content: 'hello')

        assert_predicate response, :success?
      end
    end
  end
end
