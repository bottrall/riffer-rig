# frozen_string_literal: true

require 'test_helper'
require_relative '../../../support/confirming_host'

describe Riffer::Rig::CLI::Sessions do
  before do
    @home = Dir.mktmpdir
    @cwd = Dir.mktmpdir
    @host = ConfirmingHost.new
  end

  after do
    FileUtils.remove_entry(@home)
    FileUtils.remove_entry(@cwd)
  end

  def sessions(*argv)
    Riffer::Rig::CLI::Sessions.new(
      flags: Riffer::Rig::CLI::Flags.parse(['--model', 'mock/test', *argv]),
      env: Riffer::Rig::Env.load({ 'MOCK_API_KEY' => 'mock-key' }),
      cwd: @cwd,
      home: @home
    )
  end

  def save(id, cwd: @cwd, title: 'hello', updated: 1_000)
    Riffer::Rig::Stores::JSONL.new(home: @home).append(id, header(id, cwd, title))
    time = Time.at(updated)
    File.utime(time, time, session_path(id))
  end

  def header(id, cwd, title)
    Riffer::Rig::Stores::Header.new(
      schema_version: 1,
      id: id,
      cwd: cwd,
      created_at: '2026-01-01T00:00:00Z',
      model: 'mock/test',
      riffer_rig_version: '0.9.0',
      riffer_version: '0.49.0',
      title: title
    )
  end

  def session_path(id)
    Dir.glob(File.join(@home, '.riffer', 'sessions', '*', "#{id}.jsonl")).first
  end

  def write_skill(name)
    dir = File.join(@cwd, '.agents', 'skills', name)
    FileUtils.mkdir_p(dir)
    File.write(File.join(dir, 'SKILL.md'), "---\nname: #{name}\ndescription: Skill #{name}.\n---\nDo #{name}.\n")
  end

  describe '#initialize' do
    it 'reads no saved session under --no-save' do
      save('aaa')

      assert_empty sessions('--no-save').list(@host)
    end
  end

  describe '#find' do
    it 'resumes the --resume id' do
      save('aaa')

      assert_equal 'aaa', sessions('-r', 'aaa').find(@host).id
    end

    it 'prefers the --resume id over --continue' do
      save('aaa', updated: 1_000)
      save('bbb', updated: 2_000)

      assert_equal 'aaa', sessions('-c', '-r', 'aaa').find(@host).id
    end

    it 'finds nothing for an unknown --resume id' do
      assert_nil sessions('-r', 'nope').find(@host)
    end

    it 'continues the most recent session for --continue' do
      save('aaa', updated: 2_000)
      save('bbb', updated: 1_000)

      assert_equal 'aaa', sessions('-c').find(@host).id
    end

    it 'finds nothing for --continue with no saved session' do
      assert_nil sessions('-c').find(@host)
    end

    it 'finds nothing for a bare --resume' do
      save('aaa')

      assert_nil sessions('-r').find(@host)
    end

    it 'finds nothing when no session was asked for' do
      save('aaa')

      assert_nil sessions.find(@host)
    end
  end

  describe '#fresh' do
    it 'builds a new session whatever the flags ask for' do
      save('aaa')

      refute_equal 'aaa', sessions('-r', 'aaa').fresh(@host).id
    end

    it 'hands --model to the Loader' do
      assert_equal 'mock/flagged', sessions('--model', 'mock/flagged').fresh(@host).model
    end

    it 'loads the skills of the cwd by default' do
      write_skill('tidy')

      assert_equal %w[tidy], sessions.fresh(@host).agent.context.skills.skills.keys
    end

    it 'hands --no-skills to the Loader' do
      write_skill('tidy')

      assert_nil sessions('--no-skills').fresh(@host).agent.context.skills
    end
  end

  describe '#resume' do
    it 'resumes the session with the given id' do
      save('aaa')

      assert_equal 'aaa', sessions.resume(@host, 'aaa').id
    end

    it 'resumes nothing for an unknown id' do
      assert_nil sessions.resume(@host, 'nope')
    end
  end

  describe '#recorded' do
    def record(id, message)
      entry = Riffer::Rig::Stores::MessageEntry.new(message: message, recorded_at: '2026-10-11T00:00:00.000Z')
      Riffer::Rig::Stores::JSONL.new(home: @home).append(id, entry)
    end

    it 'reads back nothing when sessions are not saved' do
      save('aaa')
      record('aaa', { role: 'user', content: 'hello' })

      assert_empty sessions('--no-save').recorded('aaa')
    end

    it 'reads back nothing for a session that has recorded nothing' do
      assert_empty sessions.recorded('nope')
    end

    it 'reads back the messages of a session without its other entries' do
      save('aaa')
      record('aaa', { role: 'user', content: 'hello' })

      assert_equal [{ role: 'user', content: 'hello' }], sessions.recorded('aaa').map(&:message)
    end
  end

  describe '#list' do
    it 'lists only the sessions of the cwd by default' do
      save('aaa')
      save('bbb', cwd: '/elsewhere')

      assert_equal %w[aaa], sessions.list(@host).map(&:id)
    end

    it 'lists every session with all' do
      save('aaa')
      save('bbb', cwd: '/elsewhere')

      assert_equal %w[aaa bbb], sessions.list(@host, all: true).map(&:id).sort
    end

    it 'lists the most recently updated session first' do
      save('aaa', updated: 1_000)
      save('bbb', updated: 3_000)
      save('ccc', updated: 2_000)

      assert_equal %w[bbb ccc aaa], sessions.list(@host).map(&:id)
    end

    it 'breaks an mtime tie by id' do
      # The store globs by directory, so these come back as bbb, aaa.
      save('bbb', cwd: '/first')
      save('aaa', cwd: '/second')

      assert_equal %w[aaa bbb], sessions.list(@host, all: true).map(&:id)
    end

    it 'collapses whitespace runs in the title' do
      save('aaa', title: "  fix\n\nthe   bug\t now ")

      assert_equal 'fix the bug now', sessions.list(@host).first.title
    end

    it 'carries the id, cwd and update time into the row' do
      save('aaa', updated: 1_000)
      row = sessions.list(@host).first

      assert_equal ['aaa', @cwd, Time.at(1_000)], [row.id, row.cwd, row.updated]
    end
  end

  describe '#delete' do
    it 'deletes the saved session' do
      save('aaa')
      sessions.delete(@host, 'aaa')

      assert_nil session_path('aaa')
    end
  end

  describe '#asked?' do
    it 'is true for a --resume id' do
      assert_predicate sessions('-r', 'aaa'), :asked?
    end

    it 'is true for --continue' do
      assert_predicate sessions('-c'), :asked?
    end

    it 'is false for a bare --resume' do
      refute_predicate sessions('-r'), :asked?
    end

    it 'is false with neither flag' do
      refute_predicate sessions, :asked?
    end
  end

  describe '#off' do
    it 'says sessions are off under --no-save' do
      assert_equal Riffer::Rig::CLI::Sessions::OFF, sessions('--no-save').off
    end

    it 'is nil when the run saves' do
      assert_nil sessions.off
    end
  end

  describe '#missing' do
    it 'says sessions are off under --no-save' do
      assert_equal Riffer::Rig::CLI::Sessions::OFF, sessions('--no-save', '-r', 'aaa').missing
    end

    it 'names the given id' do
      assert_equal 'No saved session bbb.', sessions('-r', 'aaa').missing('bbb')
    end

    it 'names the --resume id when none is given' do
      assert_equal 'No saved session aaa.', sessions('-r', 'aaa').missing
    end

    it 'names the directory when there is no id' do
      assert_equal 'No saved session in this directory.', sessions('-c').missing
    end
  end
end
