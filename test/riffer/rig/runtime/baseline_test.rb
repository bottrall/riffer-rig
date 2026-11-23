# frozen_string_literal: true

require 'test_helper'
require 'json'

describe Riffer::Rig::Runtime::Baseline do
  def baseline(sections = { agents_md: 'RULES', environment: 'ENV' })
    Riffer::Rig::Runtime::Baseline.new(system: %w[PROMPT CATALOG], sections: sections)
  end

  def update(sections)
    Riffer::Rig::Runtime::ContextUpdate.of(sections)
  end

  describe '.from_h' do
    it 'reads back what to_h wrote' do
      assert_equal baseline, Riffer::Rig::Runtime::Baseline.from_h(baseline.to_h)
    end

    it 'reads the sections back from a JSON round trip' do
      saved = JSON.parse(JSON.generate(baseline.to_h), symbolize_names: true)

      assert_equal baseline, Riffer::Rig::Runtime::Baseline.from_h(saved)
    end
  end

  it 'is frozen' do
    assert_predicate baseline, :frozen?
  end

  describe '#head' do
    it 'puts a system message of each system text ahead of the conversation' do
      head = baseline.head([Riffer::Messages::User.new('hello')])

      assert_equal(
        [[:system, 'PROMPT'], [:system, 'CATALOG'], [:user, 'hello']],
        head.map { |message| [message.role, message.content] }
      )
    end

    it 'replaces the system messages the conversation opens with' do
      messages = [Riffer::Messages::System.new('STALE'), Riffer::Messages::User.new('hello')]

      assert_equal %w[PROMPT CATALOG hello], baseline.head(messages).map(&:content)
    end

    it 'keeps a system message after the first other message' do
      messages = [Riffer::Messages::User.new('hello'), Riffer::Messages::System.new('LATER')]

      assert_equal %w[PROMPT CATALOG hello LATER], baseline.head(messages).map(&:content)
    end
  end

  describe '#changes' do
    it 'is empty when every section is as the baseline holds it' do
      assert_empty baseline.changes([], { agents_md: 'RULES', environment: 'ENV' })
    end

    it 'holds the new text of a changed section' do
      assert_equal({ environment: 'TOMORROW' }, baseline.changes([], { agents_md: 'RULES', environment: 'TOMORROW' }))
    end

    it 'holds an added section' do
      current = { agents_md: 'RULES', branch: 'main', environment: 'ENV' }

      assert_equal({ branch: 'main' }, baseline.changes([], current))
    end

    it 'holds nil for a section that is gone' do
      assert_equal({ agents_md: nil }, baseline.changes([], { environment: 'ENV' }))
    end

    it 'is empty when an earlier update already gave the current text' do
      messages = [update({ environment: 'TOMORROW' })]

      assert_empty baseline.changes(messages, { agents_md: 'RULES', environment: 'TOMORROW' })
    end

    it 'holds a section that changed again after an earlier update' do
      messages = [update({ environment: 'TOMORROW' })]

      assert_equal({ environment: 'LATER' }, baseline.changes(messages, { agents_md: 'RULES', environment: 'LATER' }))
    end

    it 'is empty when an earlier update already removed the section' do
      assert_empty baseline.changes([update({ agents_md: nil })], { environment: 'ENV' })
    end

    it 'holds a section that returns after an earlier update removed it' do
      messages = [update({ agents_md: nil })]

      assert_equal({ agents_md: 'RULES' }, baseline.changes(messages, { agents_md: 'RULES', environment: 'ENV' }))
    end

    it 'folds updates in order' do
      messages = [update({ environment: 'TOMORROW' }), update({ environment: 'LATER' })]

      assert_equal(
        { environment: 'TOMORROW' },
        baseline.changes(messages, { agents_md: 'RULES', environment: 'TOMORROW' })
      )
    end
  end

  describe '#to_h' do
    it 'holds the system texts and the sections' do
      assert_equal({ system: %w[PROMPT CATALOG], sections: { agents_md: 'RULES', environment: 'ENV' } }, baseline.to_h)
    end
  end

  it 'equals a baseline of the same values' do
    assert_equal baseline, baseline
  end
end
