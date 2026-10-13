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

    it 'is empty when the file is blank' do
      Dir.mktmpdir do |dir|
        assert_empty Riffer::Rig::Support::JsonFile.read(json_file(dir, "\n"))
      end
    end

    it 'reads a document holding an invalid UTF-8 byte' do
      Dir.mktmpdir do |dir|
        path = json_file(dir, "{\"model\":\"x\xFFy\"}")

        assert_equal({ 'model' => "x\xFFy" }, Riffer::Rig::Support::JsonFile.read(path))
      end
    end

    it 'names the file for a document that is not an object' do
      Dir.mktmpdir do |dir|
        path = json_file(dir, '["model"]')

        assert_equal "#{path} does not hold a JSON object", Riffer::Rig::Support::JsonFile.read(path)
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

    it 'names the file and where the parse stopped for malformed json' do
      Dir.mktmpdir do |dir|
        path = json_file(dir, %({\n  "model": "openai/o3",\n}))

        assert_equal "#{path} is not valid JSON at line 3 column 1", Riffer::Rig::Support::JsonFile.read(path)
      end
    end

    it 'leaves the text the parse stopped at out of the message' do
      Dir.mktmpdir do |dir|
        path = json_file(dir, '{"api_key": sk-secret"}')

        refute_includes Riffer::Rig::Support::JsonFile.read(path), 'sk-secret'
      end
    end

    it 'names the file alone when the parser gives no position' do
      Dir.mktmpdir do |dir|
        path = json_file(dir, '[' * 101)

        assert_equal "#{path} is not valid JSON", Riffer::Rig::Support::JsonFile.read(path)
      end
    end
  end

  describe '.update' do
    it 'reports a malformed file' do
      Dir.mktmpdir do |dir|
        path = json_file(dir, 'not json {{{')

        assert_equal(
          "#{path} is not valid JSON at line 1 column 1",
          Riffer::Rig::Support::JsonFile.update(path) { |document| document.merge('model' => 'openai/o3') }
        )
      end
    end

    it 'leaves a malformed file as it was' do
      Dir.mktmpdir do |dir|
        path = json_file(dir, 'not json {{{')
        Riffer::Rig::Support::JsonFile.update(path) { |document| document.merge('model' => 'openai/o3') }

        assert_equal 'not json {{{', File.read(path)
      end
    end

    it 'leaves a document that is not an object as it was' do
      Dir.mktmpdir do |dir|
        path = json_file(dir, '["model"]')
        Riffer::Rig::Support::JsonFile.update(path) { |document| document.merge('model' => 'openai/o3') }

        assert_equal '["model"]', File.read(path)
      end
    end

    it 'yields the document with symbol keys when asked' do
      Dir.mktmpdir do |dir|
        path = json_file(dir, '{"git":{"depth":10}}')
        yielded = nil
        Riffer::Rig::Support::JsonFile.update(path, symbolize_names: true) { |document| yielded = document }

        assert_equal({ git: { depth: 10 } }, yielded)
      end
    end

    it 'leaves the file unwritten when the block changes nothing' do
      Dir.mktmpdir do |dir|
        path = File.join(dir, 'document.json')
        Riffer::Rig::Support::JsonFile.update(path) { |document| document }

        refute_path_exists path
      end
    end

    it 'creates the directory owner-only' do
      Dir.mktmpdir do |dir|
        path = File.join(dir, '.riffer', 'document.json')
        Riffer::Rig::Support::JsonFile.update(path) { { 'git' => true } }

        assert_equal 0o700, File.stat(File.dirname(path)).mode & 0o777
      end
    end

    it 'creates the file with the given mode' do
      Dir.mktmpdir do |dir|
        path = File.join(dir, 'document.json')
        Riffer::Rig::Support::JsonFile.update(path, mode: 0o600) { { 'git' => true } }

        assert_equal 0o600, File.stat(path).mode & 0o777
      end
    end

    it 'creates the file with the default mode when none is given' do
      Dir.mktmpdir do |dir|
        path = File.join(dir, 'document.json')
        Riffer::Rig::Support::JsonFile.update(path) { { 'git' => true } }

        assert_equal 0o666 & ~File.umask, File.stat(path).mode & 0o777
      end
    end

    it 'applies the given mode to an existing file' do
      Dir.mktmpdir do |dir|
        path = json_file(dir, '{}')
        File.chmod(0o644, path)
        Riffer::Rig::Support::JsonFile.update(path, mode: 0o600) { { 'git' => true } }

        assert_equal 0o600, File.stat(path).mode & 0o777
      end
    end

    it 'keeps the mode of an existing file when none is given' do
      Dir.mktmpdir do |dir|
        path = json_file(dir, '{}')
        File.chmod(0o640, path)
        Riffer::Rig::Support::JsonFile.update(path) { { 'git' => true } }

        assert_equal 0o640, File.stat(path).mode & 0o777
      end
    end

    it 'writes what the block returns as json' do
      Dir.mktmpdir do |dir|
        path = json_file(dir, '{"git":{"depth":10}}')
        Riffer::Rig::Support::JsonFile.update(path) { |document| document.merge('model' => 'openai/o3') }

        assert_equal({ 'git' => { 'depth' => 10 }, 'model' => 'openai/o3' }, JSON.parse(File.read(path)))
      end
    end

    it 'is nil once written' do
      Dir.mktmpdir do |dir|
        path = File.join(dir, 'document.json')

        assert_nil(Riffer::Rig::Support::JsonFile.update(path) { { 'git' => true } })
      end
    end
  end
end
