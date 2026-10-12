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

  describe '.store_model' do
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
end
