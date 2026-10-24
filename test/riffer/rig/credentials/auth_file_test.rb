# frozen_string_literal: true

require 'test_helper'
require 'json'

describe Riffer::Rig::Credentials::AuthFile do
  before do
    @dir = Dir.mktmpdir
    @path = File.join(@dir, '.riffer', 'auth.json')
  end

  after do
    FileUtils.remove_entry(@dir)
  end

  def write(document)
    FileUtils.mkdir_p(File.dirname(@path))
    File.write(@path, JSON.generate(document))
  end

  def written
    JSON.parse(File.read(@path))
  end

  def malform
    FileUtils.mkdir_p(File.dirname(@path))
    File.write(@path, '{"openai":{"a":1},}')
    "#{@path} is not valid JSON at line 1 column 19"
  end

  describe '.read' do
    it 'reports a malformed file' do
      message = malform

      assert_equal message, Riffer::Rig::Credentials::AuthFile.read('openai', path: @path)
    end

    it 'reads nothing when the file does not exist' do
      assert_empty Riffer::Rig::Credentials::AuthFile.read('openai', path: @path)
    end

    it 'returns the secrets of the typed entry' do
      write('openai' => { 'type' => 'api_key', 'api_key' => 'sk-oai' })

      assert_equal({ 'api_key' => 'sk-oai' }, Riffer::Rig::Credentials::AuthFile.read('openai', path: @path))
    end

    it 'ignores the old flat file shape' do
      write('openai' => 'sk-flat')

      assert_empty Riffer::Rig::Credentials::AuthFile.read('openai', path: @path)
    end

    it 'ignores an entry of another type' do
      write('openai' => { 'type' => 'oauth', 'api_key' => 'sk-oauth' })

      assert_empty Riffer::Rig::Credentials::AuthFile.read('openai', path: @path)
    end

    it 'ignores a stored value that is not a string' do
      write('openai' => { 'type' => 'api_key', 'api_key' => 42 })

      assert_empty Riffer::Rig::Credentials::AuthFile.read('openai', path: @path)
    end
  end

  describe '.store' do
    it 'leaves the file unwritten when there is no secret' do
      Riffer::Rig::Credentials::AuthFile.store('openai', {}, path: @path)

      refute_path_exists @path
    end

    it 'reports a malformed file' do
      message = malform

      assert_equal message, Riffer::Rig::Credentials::AuthFile.store('openai', { 'api_key' => 'k' }, path: @path)
    end

    it 'writes the file owner-only' do
      Riffer::Rig::Credentials::AuthFile.store('openai', { 'api_key' => 'sk-oai' }, path: @path)

      assert_equal 0o600, File.stat(@path).mode & 0o777
    end

    it 'writes a typed entry' do
      Riffer::Rig::Credentials::AuthFile.store('openai', { 'api_key' => 'sk-oai' }, path: @path)

      assert_equal({ 'openai' => { 'type' => 'api_key', 'api_key' => 'sk-oai' } }, written)
    end

    it 'keeps the secrets already stored for the identifier' do
      write('acme' => { 'type' => 'api_key', 'api_key' => 'sk-acme' })
      Riffer::Rig::Credentials::AuthFile.store('acme', { 'api_token' => 'acme-token' }, path: @path)

      assert_equal({ 'type' => 'api_key', 'api_key' => 'sk-acme', 'api_token' => 'acme-token' }, written['acme'])
    end

    it 'replaces an entry of another type' do
      write('openai' => { 'type' => 'oauth', 'token' => 't' })
      Riffer::Rig::Credentials::AuthFile.store('openai', { 'api_key' => 'sk-oai' }, path: @path)

      assert_equal({ 'type' => 'api_key', 'api_key' => 'sk-oai' }, written['openai'])
    end

    it 'leaves the other entries untouched' do
      others = { 'legacy' => 'sk-flat', 'other' => { 'type' => 'oauth', 'token' => 't' },
                 'n' => { 'type' => 'api_key', 'n' => 5 } }
      write(others)
      Riffer::Rig::Credentials::AuthFile.store('openai', { 'api_key' => 'sk-oai' }, path: @path)

      assert_equal others, written.except('openai')
    end
  end

  describe '.remove' do
    it 'reports a malformed file' do
      message = malform

      assert_equal message, Riffer::Rig::Credentials::AuthFile.remove('openai', path: @path)
    end

    it 'deletes the entry whatever its type' do
      write('openai' => { 'type' => 'oauth', 'token' => 't' })
      Riffer::Rig::Credentials::AuthFile.remove('openai', path: @path)

      refute_includes written, 'openai'
    end

    it 'leaves the other entries untouched' do
      others = { 'legacy' => 'sk-flat', 'n' => { 'type' => 'api_key', 'n' => 5 } }
      write(others.merge('openai' => { 'type' => 'api_key', 'api_key' => 'sk-oai' }))
      Riffer::Rig::Credentials::AuthFile.remove('openai', path: @path)

      assert_equal others, written
    end
  end

  describe '.expand' do
    def env(vars = {})
      Riffer::Rig::Env.new(vars)
    end

    it 'expands nothing for a missing value' do
      assert_nil Riffer::Rig::Credentials::AuthFile.expand(nil, env)
    end

    it 'expands a $VAR reference from the environment' do
      assert_equal 'sk-ref', Riffer::Rig::Credentials::AuthFile.expand('$MY_KEY', env('MY_KEY' => 'sk-ref'))
    end

    it 'expands a !command to its stripped stdout' do
      assert_equal 'sk-cmd', Riffer::Rig::Credentials::AuthFile.expand('!echo sk-cmd', env)
    end

    it 'treats a failing !command as unresolved' do
      assert_nil Riffer::Rig::Credentials::AuthFile.expand('!exit 1', env)
    end

    it 'treats a !command with empty output as unresolved' do
      assert_nil Riffer::Rig::Credentials::AuthFile.expand('!true', env)
    end

    it 'keeps any other value as written' do
      assert_equal 'sk-plain', Riffer::Rig::Credentials::AuthFile.expand('sk-plain', env)
    end
  end
end
