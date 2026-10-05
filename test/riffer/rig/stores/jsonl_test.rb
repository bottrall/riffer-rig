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
    {
      type: 'header', schema_version: 1, id: id, cwd: cwd, created_at: '2026-01-01T00:00:00Z',
      model: 'mock/test', riffer_rig_version: '0.8.0', riffer_version: '0.49.0', title: 'hello'
    }
  end

  def message_entry(content)
    { type: 'message', message: { role: 'user', content: content } }
  end

  def sessions
    File.join(@home, '.riffer', 'sessions')
  end

  def write_elsewhere(slug, id, entry)
    dir = File.join(sessions, slug)
    FileUtils.mkdir_p(dir)
    File.write(File.join(dir, "#{id}.jsonl"), "#{JSON.generate(entry)}\n")
  end

  it 'appends one JSON line per entry under the cwd slug' do
    @store.append('aaa', header('aaa', '/home/jake/My Work'))
    @store.append('aaa', message_entry('hello'))

    lines = File.readlines(File.join(sessions, 'home-jake-My-Work', 'aaa.jsonl'))

    assert_equal(
      [header('aaa', '/home/jake/My Work'), message_entry('hello')],
      lines.map do |line|
        JSON.parse(line, symbolize_names: true)
      end
    )
  end

  it 'reads the entries in order' do
    @store.append('aaa', header('aaa'))
    @store.append('aaa', message_entry('first'))
    @store.append('aaa', message_entry('second'))

    assert_equal [header('aaa'), message_entry('first'), message_entry('second')], @store.read('aaa')
  end

  it 'reads an unknown session as empty' do
    assert_empty @store.read('nope')
  end

  it 'skips malformed lines when reading' do
    @store.append('aaa', header('aaa'))
    File.open(File.join(sessions, 'project', 'aaa.jsonl'), 'a') { |file| file.write("not json\n") }

    assert_equal [header('aaa')], @store.read('aaa')
  end

  it 'lists the header entries of every session' do
    @store.append('aaa', header('aaa', '/one'))
    @store.append('aaa', message_entry('hello'))
    write_elsewhere('other', 'bbb', header('bbb', '/two'))

    assert_equal [header('aaa', '/one'), header('bbb', '/two')], @store.list
  end

  it 'dates a session by its file mtime' do
    @store.append('aaa', header('aaa'))
    time = Time.at(1000)
    File.utime(time, time, File.join(sessions, 'project', 'aaa.jsonl'))

    assert_equal time, @store.updated('aaa')
  end

  it 'dates an unknown session as nil' do
    assert_nil @store.updated('nope')
  end

  it 'filters the listing by the header cwd, not the slug directory' do
    write_elsewhere('misleading', 'aaa', header('aaa', '/project'))
    @store.append('bbb', header('bbb', '/other'))

    assert_equal [header('aaa', '/project')], @store.list(cwd: '/project')
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

  it 'collapses a bare dot cwd so the file stays in the tree' do
    @store.append('aaa', header('aaa', '..'))

    refute_empty Dir.glob(File.join(sessions, '*', 'aaa.jsonl'))
  end

  it 'raises when appending without a header' do
    assert_raises(ArgumentError) { @store.append('aaa', message_entry('hello')) }
  end
end
