# frozen_string_literal: true

require 'test_helper'
require 'json'

describe Riffer::Rig::Stores::JSONL do
  before do
    @home = Dir.mktmpdir
    @store = Riffer::Rig::Stores::JSONL.new(home: @home)
  end

  after do
    FileUtils.remove_entry(@home)
  end

  def header(id, cwd = '/project')
    Riffer::Rig::Stores::Header.new(
      schema_version: 1,
      id: id,
      cwd: cwd,
      created_at: '2026-01-01T00:00:00Z',
      model: 'mock/test',
      riffer_rig_version: '0.8.0',
      riffer_version: '0.49.0',
      title: 'hello'
    )
  end

  def message_entry(content)
    Riffer::Rig::Stores::MessageEntry.new(message: { role: 'user', content: content })
  end

  def sessions
    File.join(@home, '.riffer', 'sessions')
  end

  def write_elsewhere(slug, id, entry)
    dir = File.join(sessions, slug)
    FileUtils.mkdir_p(dir)
    File.write(File.join(dir, "#{id}.jsonl"), "#{JSON.generate(entry.to_h)}\n")
  end

  def append_line(entry_hash)
    File.open(File.join(sessions, 'project', 'aaa.jsonl'), 'a') { |file| file.write("#{JSON.generate(entry_hash)}\n") }
  end

  it 'raises when appending without a header' do
    assert_raises(ArgumentError) { @store.append('aaa', message_entry('hello')) }
  end

  it 'appends one JSON line per entry under the cwd slug' do
    @store.append('aaa', header('aaa', '/home/jake/My Work'))
    @store.append('aaa', message_entry('hello'))

    lines = File.readlines(File.join(sessions, 'home-jake-My-Work', 'aaa.jsonl'))

    assert_equal(
      [header('aaa', '/home/jake/My Work').to_h, message_entry('hello').to_h],
      lines.map do |line|
        JSON.parse(line, symbolize_names: true)
      end
    )
  end

  it 'appends to a session file another store instance created' do
    write_elsewhere('project', 'aaa', header('aaa'))
    @store.append('aaa', message_entry('hello'))

    assert_equal [header('aaa'), message_entry('hello')], @store.read('aaa')
  end

  it 'files a cwd with no slug characters under a dash' do
    @store.append('aaa', header('aaa', '/'))

    assert_path_exists File.join(sessions, '-', 'aaa.jsonl')
  end

  it 'collapses a bare dot cwd so the file stays in the tree' do
    @store.append('aaa', header('aaa', '..'))

    refute_empty Dir.glob(File.join(sessions, '*', 'aaa.jsonl'))
  end

  it 'reads an unknown session as empty' do
    assert_empty @store.read('nope')
  end

  it 'round-trips every entry type' do
    entries = [
      header('aaa'),
      message_entry('hello'),
      Riffer::Rig::Stores::ModelEntry.new(model: 'mock/one'),
      Riffer::Rig::Stores::SkillEntry.new(skill: 'a')
    ]
    entries.each { |entry| @store.append('aaa', entry) }

    assert_equal entries, @store.read('aaa')
  end

  it 'round-trips the recorded_at of a stamped entry' do
    stamped = Riffer::Rig::Stores::ModelEntry.new(model: 'mock/one', recorded_at: '2026-10-11T12:00:00.500Z')
    @store.append('aaa', header('aaa'))
    @store.append('aaa', stamped)

    assert_equal stamped.recorded_at, @store.read('aaa').last.recorded_at
  end

  it 'reads a file written before entries carried recorded_at' do
    @store.append('aaa', header('aaa'))
    append_line({ type: 'message', message: { role: 'user', content: 'hello' } })
    append_line({ type: 'model', model: 'mock/one' })
    append_line({ type: 'skill', skill: 'a' })

    assert_equal(
      [
        header('aaa'),
        message_entry('hello'),
        Riffer::Rig::Stores::ModelEntry.new(model: 'mock/one'),
        Riffer::Rig::Stores::SkillEntry.new(skill: 'a')
      ],
      @store.read('aaa')
    )
  end

  it 'skips malformed lines when reading' do
    @store.append('aaa', header('aaa'))
    File.open(File.join(sessions, 'project', 'aaa.jsonl'), 'a') { |file| file.write("not json\n") }

    assert_equal [header('aaa')], @store.read('aaa')
  end

  it 'skips an unknown entry type when reading' do
    @store.append('aaa', header('aaa'))
    append_line({ type: 'weird', payload: {} })

    assert_equal [header('aaa')], @store.read('aaa')
  end

  it 'lists the header entries of every session' do
    @store.append('aaa', header('aaa', '/one'))
    @store.append('aaa', message_entry('hello'))
    write_elsewhere('other', 'bbb', header('bbb', '/two'))

    assert_equal [header('aaa', '/one'), header('bbb', '/two')], @store.list
  end

  it 'omits an empty session file from the listing' do
    FileUtils.mkdir_p(File.join(sessions, 'project'))
    File.write(File.join(sessions, 'project', 'aaa.jsonl'), '')

    assert_empty @store.list
  end

  it 'omits a session file with a malformed first line from the listing' do
    FileUtils.mkdir_p(File.join(sessions, 'project'))
    File.write(File.join(sessions, 'project', 'aaa.jsonl'), "not json\n")

    assert_empty @store.list
  end

  it 'omits a session file that does not start with a header from the listing' do
    write_elsewhere('project', 'aaa', message_entry('hello'))

    assert_empty @store.list
  end

  it 'stamps the listed header with the file mtime' do
    @store.append('aaa', header('aaa'))
    time = Time.at(1000)
    File.utime(time, time, File.join(sessions, 'project', 'aaa.jsonl'))

    assert_equal time, @store.list.first.updated
  end

  it 'filters the listing by the header cwd, not the slug directory' do
    write_elsewhere('misleading', 'aaa', header('aaa', '/project'))
    @store.append('bbb', header('bbb', '/other'))

    assert_equal [header('aaa', '/project')], @store.list(cwd: '/project')
  end

  it 'ignores deleting an unknown session' do
    assert_nil @store.delete('nope')
  end

  it 'deletes the session file' do
    @store.append('aaa', header('aaa'))
    @store.delete('aaa')

    refute_path_exists File.join(sessions, 'project', 'aaa.jsonl')
  end

  it 'reads a deleted session as empty' do
    @store.append('aaa', header('aaa'))
    @store.delete('aaa')

    assert_empty @store.read('aaa')
  end
end
