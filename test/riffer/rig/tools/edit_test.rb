# frozen_string_literal: true

require 'test_helper'

describe Riffer::Rig::Tools::Edit do
  def setup
    @tool = Riffer::Rig::Tools::Edit.new
  end

  it 'replaces a unique string' do
    with_file('foo bar baz') do
      @tool.call(context: nil, path: 'f.txt', old_string: 'bar', new_string: 'QUX')

      assert_equal 'foo QUX baz', File.read('f.txt')
    end
  end

  it 'missing old string returns error' do
    with_file('foo bar') do
      response = @tool.call(context: nil, path: 'f.txt', old_string: 'nope', new_string: 'x')

      assert_predicate response, :error?
    end
  end

  it 'non unique match without replace all returns error' do
    with_file('x x x') do
      response = @tool.call(context: nil, path: 'f.txt', old_string: 'x', new_string: 'y')

      assert_predicate response, :error?
    end
  end

  it 'replace all replaces every occurrence' do
    with_file('x x x') do
      @tool.call(context: nil, path: 'f.txt', old_string: 'x', new_string: 'y', replace_all: true)

      assert_equal 'y y y', File.read('f.txt')
    end
  end

  it 'backslash sequences in replacement are inserted literally' do
    with_file('foo bar baz') do
      @tool.call(context: nil, path: 'f.txt', old_string: 'bar', new_string: '\0\1')

      assert_equal 'foo \0\1 baz', File.read('f.txt')
    end
  end

  private

  def with_file(content)
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        File.write('f.txt', content)
        yield
      end
    end
  end
end
