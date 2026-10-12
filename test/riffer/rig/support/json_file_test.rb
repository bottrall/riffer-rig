# frozen_string_literal: true

require 'test_helper'
require 'tmpdir'
require 'json'

describe Riffer::Rig::Support::JsonFile do
  def json_file(dir, content)
    path = File.join(dir, 'document.json')
    File.write(path, content)
    path
  end

  describe '.read' do
    it 'is empty when the file is absent' do
      Dir.mktmpdir do |dir|
        assert_empty Riffer::Rig::Support::JsonFile.read(File.join(dir, 'document.json'))
      end
    end

    it 'is empty for malformed json' do
      Dir.mktmpdir do |dir|
        assert_empty Riffer::Rig::Support::JsonFile.read(json_file(dir, 'not json {{{'))
      end
    end

    it 'is empty for a document that is not an object' do
      Dir.mktmpdir do |dir|
        assert_empty Riffer::Rig::Support::JsonFile.read(json_file(dir, '["model"]'))
      end
    end

    it 'reads the document with string keys' do
      Dir.mktmpdir do |dir|
        path = json_file(dir, '{"git":{"depth":10}}')

        assert_equal({ 'git' => { 'depth' => 10 } }, Riffer::Rig::Support::JsonFile.read(path))
      end
    end

    it 'reads the document with symbol keys when asked' do
      Dir.mktmpdir do |dir|
        path = json_file(dir, '{"git":{"depth":10}}')

        assert_equal({ git: { depth: 10 } }, Riffer::Rig::Support::JsonFile.read(path, symbolize_names: true))
      end
    end
  end

  describe '.write' do
    it 'creates the directory owner-only' do
      Dir.mktmpdir do |dir|
        path = File.join(dir, '.riffer', 'document.json')
        Riffer::Rig::Support::JsonFile.write(path, {})

        assert_equal 0o700, File.stat(File.dirname(path)).mode & 0o777
      end
    end

    it 'creates the file with the given mode' do
      Dir.mktmpdir do |dir|
        path = File.join(dir, 'document.json')
        Riffer::Rig::Support::JsonFile.write(path, {}, mode: 0o600)

        assert_equal 0o600, File.stat(path).mode & 0o777
      end
    end

    it 'writes the document as json' do
      Dir.mktmpdir do |dir|
        path = File.join(dir, 'document.json')
        Riffer::Rig::Support::JsonFile.write(path, { 'git' => { 'depth' => 10 } })

        assert_equal({ 'git' => { 'depth' => 10 } }, JSON.parse(File.read(path)))
      end
    end
  end
end
