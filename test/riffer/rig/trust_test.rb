# frozen_string_literal: true

require 'test_helper'
require 'tmpdir'
require 'json'

describe Riffer::Rig::Trust do
  def trust_file(dir, content)
    path = File.join(dir, 'trust.json')
    File.write(path, content)
    path
  end

  describe '.read' do
    it 'reports a malformed file' do
      Dir.mktmpdir do |dir|
        path = trust_file(dir, '{"a.rb":true,}')

        assert_equal "#{path} is not valid JSON at line 1 column 14", Riffer::Rig::Trust.read(path)
      end
    end

    it 'keeps true decisions' do
      Dir.mktmpdir do |dir|
        path = trust_file(dir, '{"a.rb":true}')

        assert_equal({ 'a.rb' => true }, Riffer::Rig::Trust.read(path))
      end
    end

    it 'keeps false decisions' do
      Dir.mktmpdir do |dir|
        path = trust_file(dir, '{"a.rb":false}')

        assert_equal({ 'a.rb' => false }, Riffer::Rig::Trust.read(path))
      end
    end

    it 'drops entries whose decision is not a boolean' do
      Dir.mktmpdir do |dir|
        path = trust_file(dir, '{"a.rb":"yes","b.rb":1,"c.rb":null,"d.rb":true}')

        assert_equal({ 'd.rb' => true }, Riffer::Rig::Trust.read(path))
      end
    end
  end

  describe '.store' do
    it 'reports a malformed file' do
      Dir.mktmpdir do |dir|
        path = trust_file(dir, '{"a.rb":true,}')

        assert_equal "#{path} is not valid JSON at line 1 column 14", Riffer::Rig::Trust.store(path, 'b.rb', true)
      end
    end

    it 'writes the decision to the file' do
      Dir.mktmpdir do |dir|
        path = File.join(dir, 'trust.json')
        Riffer::Rig::Trust.store(path, 'a.rb', true)

        assert_equal({ 'a.rb' => true }, JSON.parse(File.read(path)))
      end
    end

    it 'keeps existing decisions when adding another' do
      Dir.mktmpdir do |dir|
        path = File.join(dir, 'trust.json')
        Riffer::Rig::Trust.store(path, 'a.rb', true)
        Riffer::Rig::Trust.store(path, 'b.rb', false)

        assert_equal({ 'a.rb' => true, 'b.rb' => false }, Riffer::Rig::Trust.read(path))
      end
    end

    it 'overwrites the decision for the same file' do
      Dir.mktmpdir do |dir|
        path = File.join(dir, 'trust.json')
        Riffer::Rig::Trust.store(path, 'a.rb', true)
        Riffer::Rig::Trust.store(path, 'a.rb', false)

        assert_equal({ 'a.rb' => false }, Riffer::Rig::Trust.read(path))
      end
    end
  end
end
