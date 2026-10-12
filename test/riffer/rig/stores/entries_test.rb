# frozen_string_literal: true

require 'test_helper'

describe Riffer::Rig::Stores::Entries do
  def header
    Riffer::Rig::Stores::Header.new(
      schema_version: 1,
      id: 'aaa',
      cwd: '/project',
      created_at: '2026-01-01T00:00:00Z',
      model: 'mock/test',
      riffer_rig_version: '0.9.0',
      riffer_version: '0.49.0',
      title: 'hello'
    )
  end

  def message_entry(content)
    Riffer::Rig::Stores::MessageEntry.new(message: { role: 'user', content: content })
  end

  def model_entry(name)
    Riffer::Rig::Stores::ModelEntry.new(model: name)
  end

  def skill_entry(name)
    Riffer::Rig::Stores::SkillEntry.new(skill: name)
  end

  def entries
    [
      header,
      skill_entry('a'),
      message_entry('first'),
      model_entry('mock/one'),
      message_entry('second'),
      model_entry('mock/two'),
      skill_entry('b')
    ]
  end

  describe '.messages' do
    it 'maps the message entries in recorded order' do
      assert_equal(
        [{ role: 'user', content: 'first' }, { role: 'user', content: 'second' }],
        Riffer::Rig::Stores::Entries.messages(entries)
      )
    end

    it 'maps no entries to no messages' do
      assert_empty Riffer::Rig::Stores::Entries.messages([])
    end
  end

  describe '.snapshot' do
    it 'holds the id, messages, model and skills' do
      assert_equal %i[id messages model skills], Riffer::Rig::Stores::Entries.snapshot(entries, 'aaa').keys
    end

    it 'carries the id it is given' do
      assert_equal 'aaa', Riffer::Rig::Stores::Entries.snapshot(entries, 'aaa')[:id]
    end

    it 'carries the messages in recorded order' do
      assert_equal(
        [{ role: 'user', content: 'first' }, { role: 'user', content: 'second' }],
        Riffer::Rig::Stores::Entries.snapshot(entries, 'aaa')[:messages]
      )
    end

    it 'lets the last model entry win' do
      assert_equal 'mock/two', Riffer::Rig::Stores::Entries.snapshot(entries, 'aaa')[:model]
    end

    it 'has no model without a model entry' do
      assert_nil Riffer::Rig::Stores::Entries.snapshot([header, message_entry('first')], 'aaa')[:model]
    end

    it 'carries every skill entry in recorded order' do
      assert_equal %w[a b], Riffer::Rig::Stores::Entries.snapshot(entries, 'aaa')[:skills]
    end
  end
end
