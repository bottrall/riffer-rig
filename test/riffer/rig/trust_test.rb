# frozen_string_literal: true

require 'test_helper'
require 'json'

describe Riffer::Rig::Trust do
  before do
    @dir = Dir.mktmpdir
    @path = File.join(@dir, 'trust.json')
  end

  after do
    FileUtils.remove_entry(@dir)
  end

  describe '.read' do
    it 'is empty for malformed json' do
      File.write(@path, 'not json {{{')

      assert_empty Riffer::Rig::Trust.read(@path)
    end

    it 'keeps only the boolean decisions' do
      File.write(@path, JSON.generate('/a/rig.rb' => true, '/b/rig.rb' => false, '/c/rig.rb' => 'yes'))

      assert_equal({ '/a/rig.rb' => true, '/b/rig.rb' => false }, Riffer::Rig::Trust.read(@path))
    end
  end

  describe '.store' do
    it 'records the decision for a file' do
      Riffer::Rig::Trust.store(@path, '/a/rig.rb', true)

      assert_equal({ '/a/rig.rb' => true }, Riffer::Rig::Trust.read(@path))
    end

    it 'keeps the decisions already stored' do
      Riffer::Rig::Trust.store(@path, '/a/rig.rb', true)
      Riffer::Rig::Trust.store(@path, '/b/rig.rb', false)

      assert_equal({ '/a/rig.rb' => true, '/b/rig.rb' => false }, Riffer::Rig::Trust.read(@path))
    end
  end
end
