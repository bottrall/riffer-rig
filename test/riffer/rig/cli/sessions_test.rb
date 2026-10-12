# frozen_string_literal: true

require 'test_helper'

describe Riffer::Rig::CLI::Sessions do
  before do
    @home = Dir.mktmpdir
    @store = Riffer::Rig::Stores::JSONL.new(home: @home)
    @sessions = Riffer::Rig::CLI::Sessions.new(
      flags: Riffer::Rig::CLI::Flags.parse([]),
      env: Riffer::Rig::Env.new('MOCK_API_KEY' => 'mock-key'),
      cwd: '/work/project',
      home: @home
    )
  end

  after do
    FileUtils.remove_entry(@home)
  end

  def seed(id, cwd: '/work/project', title: 'hello')
    @store.append(
      id,
      Riffer::Rig::Stores::Header.new(
        schema_version: 1,
        id: id,
        cwd: cwd,
        created_at: '2026-01-01T00:00:00Z',
        model: 'mock/test',
        riffer_rig_version: '0.8.0',
        riffer_version: '0.49.0',
        title: title
      )
    )
    updated = Time.at(1_800_000_000)
    File.utime(updated, updated, Dir.glob(File.join(@home, '.riffer', 'sessions', '*', "#{id}.jsonl")).fetch(0))
  end

  def list(all: false)
    @sessions.list(Riffer::Rig::Hosts::Null.new, all: all)
  end

  describe '#list' do
    it 'orders sessions updated at the same moment by id' do
      seed('ccc', cwd: '/work/a')
      seed('bbb', cwd: '/work/b')
      seed('aaa', cwd: '/work/c')

      assert_equal %w[aaa bbb ccc], list(all: true).map(&:id)
    end

    it 'collapses the whitespace of a title onto one line' do
      seed('aaa', title: " fix  the\nlogin\t bug\n")

      assert_equal ['fix the login bug'], list.map(&:title)
    end
  end
end
