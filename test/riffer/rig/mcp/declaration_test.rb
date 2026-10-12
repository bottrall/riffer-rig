# frozen_string_literal: true

require 'test_helper'

describe Riffer::Rig::Mcp::Declaration do
  let(:stdio) do
    Riffer::Rig::Mcp::Declaration.new(
      command: 'some-server', args: ['--x'], env: { 'FOO' => 'bar' }, auth: { api_key: ['MY_KEY'] }
    )
  end

  def refusal
    yield
    nil
  rescue ArgumentError => e
    e.message
  end

  describe '.new' do
    it 'rejects a url and a command together' do
      assert_equal(
        'a declaration takes a url or a command, not both',
        refusal { Riffer::Rig::Mcp::Declaration.new(url: 'https://x.test', command: 'x') }
      )
    end

    it 'rejects neither a url nor a command' do
      assert_equal('a declaration takes a url or a command', refusal { Riffer::Rig::Mcp::Declaration.new })
    end
  end

  describe '#with_headers' do
    it 'replaces the headers of a url declaration' do
      declaration = Riffer::Rig::Mcp::Declaration.new(url: 'https://x.test', headers: { 'A' => 'a' })

      assert_equal({ 'B' => 'b' }, declaration.with_headers({ 'B' => 'b' }).headers)
    end

    it 'keeps the url of a url declaration' do
      declaration = Riffer::Rig::Mcp::Declaration.new(url: 'https://x.test')

      assert_equal 'https://x.test', declaration.with_headers({ 'B' => 'b' }).url
    end

    it 'preserves the auth of a stdio declaration' do
      assert_equal({ api_key: ['MY_KEY'] }, stdio.with_headers({ 'X-Y' => 'z' }).auth)
    end

    it 'preserves the command, args and env of a stdio declaration' do
      rebuilt = stdio.with_headers({ 'X-Y' => 'z' })

      assert_equal ['some-server', ['--x'], { 'FOO' => 'bar' }], [rebuilt.command, rebuilt.args, rebuilt.env]
    end
  end

  describe '#to_h' do
    it 'returns every field' do
      assert_equal(
        {
          url: nil, headers: {}, auth: { api_key: ['MY_KEY'] },
          command: 'some-server', args: ['--x'], env: { 'FOO' => 'bar' }
        },
        stdio.to_h
      )
    end
  end
end
