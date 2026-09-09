# frozen_string_literal: true

require 'test_helper'

describe Riffer::Rig::Credentials do
  it 'round trips a saved key' do
    without_env do
      in_tmp_path do |path|
        Riffer::Rig::Credentials.save_api_key('anthropic', 'sk-ant-stored', path: path)

        assert_equal 'sk-ant-stored', Riffer::Rig::Credentials.api_key_for('anthropic', path: path)
      end
    end
  end

  it 'environment variable takes precedence over stored key' do
    in_tmp_path do |path|
      Riffer::Rig::Credentials.save_api_key('anthropic', 'sk-ant-stored', path: path)
      ENV['ANTHROPIC_API_KEY'] = 'sk-ant-env'

      assert_equal 'sk-ant-env', Riffer::Rig::Credentials.api_key_for('anthropic', path: path)
    ensure
      ENV.delete('ANTHROPIC_API_KEY')
    end
  end

  it 'returns nil when no key is available' do
    without_env do
      in_tmp_path do |path|
        assert_nil Riffer::Rig::Credentials.api_key_for('anthropic', path: path)
      end
    end
  end

  it 'saved file is owner only readable' do
    in_tmp_path do |path|
      Riffer::Rig::Credentials.save_api_key('anthropic', 'sk-ant-stored', path: path)

      assert_equal 0o600, File.stat(path).mode & 0o777
    end
  end

  it 'stores and retrieves openai key from env' do
    in_tmp_path do |path|
      ENV['OPENAI_API_KEY'] = 'sk-openai-env'

      assert_equal 'sk-openai-env', Riffer::Rig::Credentials.api_key_for('openai', path: path)
    ensure
      ENV.delete('OPENAI_API_KEY')
    end
  end

  it 'stores and retrieves openai key from file' do
    in_tmp_path do |path|
      ENV.delete('OPENAI_API_KEY')
      Riffer::Rig::Credentials.save_api_key('openai', 'sk-openai-stored', path: path)

      assert_equal 'sk-openai-stored', Riffer::Rig::Credentials.api_key_for('openai', path: path)
    end
  end

  it 'stores and retrieves gemini key from file' do
    in_tmp_path do |path|
      ENV.delete('GEMINI_API_KEY')
      Riffer::Rig::Credentials.save_api_key('gemini', 'gemini-stored', path: path)

      assert_equal 'gemini-stored', Riffer::Rig::Credentials.api_key_for('gemini', path: path)
    end
  end

  it 'stores and retrieves openrouter key from file' do
    in_tmp_path do |path|
      ENV.delete('OPENROUTER_API_KEY')
      Riffer::Rig::Credentials.save_api_key('openrouter', 'sk-or-stored', path: path)

      assert_equal 'sk-or-stored', Riffer::Rig::Credentials.api_key_for('openrouter', path: path)
    end
  end

  it 'anthropic key survives after adding openai key' do
    in_tmp_path do |path|
      ENV.delete('ANTHROPIC_API_KEY')
      ENV.delete('OPENAI_API_KEY')

      Riffer::Rig::Credentials.save_api_key('anthropic', 'sk-ant', path: path)
      Riffer::Rig::Credentials.save_api_key('openai', 'sk-oai', path: path)

      assert_equal 'sk-ant', Riffer::Rig::Credentials.api_key_for('anthropic', path: path)
    end
  end

  it 'openai key survives after adding anthropic key' do
    in_tmp_path do |path|
      ENV.delete('ANTHROPIC_API_KEY')
      ENV.delete('OPENAI_API_KEY')

      Riffer::Rig::Credentials.save_api_key('anthropic', 'sk-ant', path: path)
      Riffer::Rig::Credentials.save_api_key('openai', 'sk-oai', path: path)

      assert_equal 'sk-oai', Riffer::Rig::Credentials.api_key_for('openai', path: path)
    end
  end

  private

  def in_tmp_path
    Dir.mktmpdir do |dir|
      yield File.join(dir, 'auth.json')
    end
  end

  def without_env
    previous = ENV.delete('ANTHROPIC_API_KEY')
    yield
  ensure
    ENV['ANTHROPIC_API_KEY'] = previous if previous
  end
end
