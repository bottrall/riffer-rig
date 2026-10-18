# frozen_string_literal: true

require 'test_helper'
require 'json'

describe Riffer::Rig::Settings::File do
  def settings_file(dir, data)
    path = File.join(dir, 'settings.json')
    File.write(path, JSON.generate(data))
    path
  end

  describe '.read' do
    it 'reads the document with symbol keys' do
      Dir.mktmpdir do |dir|
        path = settings_file(dir, { 'model' => 'anthropic/claude-sonnet-4-6', 'git' => { 'depth' => 10 } })

        assert_equal(
          { model: 'anthropic/claude-sonnet-4-6', git: { depth: 10 } },
          Riffer::Rig::Settings::File.read(path)
        )
      end
    end
  end

  describe '.update' do
    it 'yields the document with symbol keys' do
      Dir.mktmpdir do |dir|
        path = settings_file(dir, { 'git' => { 'depth' => 10 } })
        yielded = nil
        Riffer::Rig::Settings::File.update(path) { |document| yielded = document }

        assert_equal({ git: { depth: 10 } }, yielded)
      end
    end
  end

  describe '.store_model' do
    it 'reports a malformed file' do
      Dir.mktmpdir do |dir|
        path = File.join(dir, 'settings.json')
        File.write(path, '{"reasoning":"low",}')

        assert_equal(
          "#{path} is not valid JSON at line 1 column 20",
          Riffer::Rig::Settings::File.store_model('openai/gpt-5', path: path)
        )
      end
    end

    it 'writes the model' do
      Dir.mktmpdir do |dir|
        path = File.join(dir, '.riffer', 'settings.json')
        Riffer::Rig::Settings::File.store_model('openai/gpt-5', path: path)

        assert_equal 'openai/gpt-5', JSON.parse(File.read(path))['model']
      end
    end

    it 'keeps the other keys' do
      Dir.mktmpdir do |dir|
        path = settings_file(dir, { 'model' => 'anthropic/a', 'reasoning' => 'low' })
        Riffer::Rig::Settings::File.store_model('openai/gpt-5', path: path)

        assert_equal 'low', JSON.parse(File.read(path))['reasoning']
      end
    end
  end

  describe '.store_reasoning' do
    it 'reports a malformed file' do
      Dir.mktmpdir do |dir|
        path = File.join(dir, 'settings.json')
        File.write(path, '{"reasoning":"low",}')

        assert_equal(
          "#{path} is not valid JSON at line 1 column 20",
          Riffer::Rig::Settings::File.store_reasoning('high', path: path)
        )
      end
    end

    it 'writes the level' do
      Dir.mktmpdir do |dir|
        path = File.join(dir, '.riffer', 'settings.json')
        Riffer::Rig::Settings::File.store_reasoning('high', path: path)

        assert_equal 'high', JSON.parse(File.read(path))['reasoning']
      end
    end

    it 'keeps the other keys' do
      Dir.mktmpdir do |dir|
        path = settings_file(dir, { 'model' => 'anthropic/a', 'reasoning' => 'low' })
        Riffer::Rig::Settings::File.store_reasoning('high', path: path)

        assert_equal 'anthropic/a', JSON.parse(File.read(path))['model']
      end
    end
  end
end
