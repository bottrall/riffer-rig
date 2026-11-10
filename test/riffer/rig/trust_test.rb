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

  def decision(sha256, trusted)
    Riffer::Rig::Trust::Decision.new(sha256: sha256, trusted: trusted)
  end

  describe '.read' do
    it 'reports a malformed file' do
      Dir.mktmpdir do |dir|
        path = trust_file(dir, '{"a.rb":true,}')

        assert_equal "#{path} is not valid JSON at line 1 column 14", Riffer::Rig::Trust.read(path)
      end
    end

    it 'keeps a true decision with its digest' do
      Dir.mktmpdir do |dir|
        path = trust_file(dir, '{"a.rb":{"sha256":"abc","trusted":true}}')

        assert_equal({ 'a.rb' => decision('abc', true) }, Riffer::Rig::Trust.read(path))
      end
    end

    it 'keeps a false decision with its digest' do
      Dir.mktmpdir do |dir|
        path = trust_file(dir, '{"a.rb":{"sha256":"abc","trusted":false}}')

        assert_equal({ 'a.rb' => decision('abc', false) }, Riffer::Rig::Trust.read(path))
      end
    end

    it 'drops entries that are not a digest and a boolean' do
      Dir.mktmpdir do |dir|
        path = trust_file(
          dir,
          '{"a.rb":true,"b.rb":{"sha256":1,"trusted":true},"c.rb":{"sha256":"abc","trusted":"yes"},' \
          '"d.rb":{"sha256":"abc","trusted":true}}'
        )

        assert_equal({ 'd.rb' => decision('abc', true) }, Riffer::Rig::Trust.read(path))
      end
    end
  end

  describe '.store' do
    it 'reports a malformed file' do
      Dir.mktmpdir do |dir|
        path = trust_file(dir, '{"a.rb":true,}')

        assert_equal "#{path} is not valid JSON at line 1 column 14",
                     Riffer::Rig::Trust.store(path, 'b.rb', decision('abc', true))
      end
    end

    it 'writes the decision with its digest to the file' do
      Dir.mktmpdir do |dir|
        path = File.join(dir, 'trust.json')
        Riffer::Rig::Trust.store(path, 'a.rb', decision('abc', true))

        assert_equal({ 'a.rb' => { 'sha256' => 'abc', 'trusted' => true } }, JSON.parse(File.read(path)))
      end
    end

    it 'drops entries that are not a digest and a boolean' do
      Dir.mktmpdir do |dir|
        path = trust_file(dir, '{"a.rb":true}')
        Riffer::Rig::Trust.store(path, 'b.rb', decision('abc', true))

        assert_equal({ 'b.rb' => { 'sha256' => 'abc', 'trusted' => true } }, JSON.parse(File.read(path)))
      end
    end

    it 'keeps existing decisions when adding another' do
      Dir.mktmpdir do |dir|
        path = File.join(dir, 'trust.json')
        Riffer::Rig::Trust.store(path, 'a.rb', decision('abc', true))
        Riffer::Rig::Trust.store(path, 'b.rb', decision('def', false))

        assert_equal(
          { 'a.rb' => decision('abc', true), 'b.rb' => decision('def', false) },
          Riffer::Rig::Trust.read(path)
        )
      end
    end

    it 'overwrites the decision for the same file' do
      Dir.mktmpdir do |dir|
        path = File.join(dir, 'trust.json')
        Riffer::Rig::Trust.store(path, 'a.rb', decision('abc', true))
        Riffer::Rig::Trust.store(path, 'a.rb', decision('def', false))

        assert_equal({ 'a.rb' => decision('def', false) }, Riffer::Rig::Trust.read(path))
      end
    end
  end
end
