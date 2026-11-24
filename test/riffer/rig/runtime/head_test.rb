# frozen_string_literal: true

require 'test_helper'

describe Riffer::Rig::Runtime::Head do
  def head(sections = { agents_md: 'RULES', environment: 'ENV' })
    system(Riffer::Rig::Runtime::SystemPrompt.new('BASE', '/tmp/proj').render(sections))
  end

  def system(text)
    Riffer::Messages::System.new(text)
  end

  def user(content = 'hello')
    Riffer::Messages::User.new(content)
  end

  def update(sections)
    Riffer::Rig::Runtime::ContextUpdate.of(sections)
  end

  describe '.sections' do
    it 'is nil for no messages' do
      assert_nil Riffer::Rig::Runtime::Head.sections([])
    end

    it 'is nil when the messages open with no system message' do
      assert_nil Riffer::Rig::Runtime::Head.sections([user, head])
    end

    it 'is nil for a system message without an environment section' do
      assert_nil Riffer::Rig::Runtime::Head.sections([head({ agents_md: 'RULES' }), user])
    end

    it 'is nil for a system message rig did not render' do
      assert_nil Riffer::Rig::Runtime::Head.sections([system('You are riffer.'), user])
    end

    it 'reads the sections of the head the messages open with' do
      assert_equal({ agents_md: 'RULES', environment: 'ENV' }, Riffer::Rig::Runtime::Head.sections([head, user]))
    end
  end

  describe '.seen' do
    it 'is nil without a head' do
      assert_nil Riffer::Rig::Runtime::Head.seen([user, update({ environment: 'LATER' })])
    end

    it 'is the sections of the head before any update' do
      assert_equal({ agents_md: 'RULES', environment: 'ENV' }, Riffer::Rig::Runtime::Head.seen([head, user]))
    end

    it 'takes the text of a section from the update that changed it' do
      seen = Riffer::Rig::Runtime::Head.seen([head, user, update({ environment: 'LATER' })])

      assert_equal({ agents_md: 'RULES', environment: 'LATER' }, seen)
    end

    it 'drops a section an update removed' do
      assert_equal({ environment: 'ENV' }, Riffer::Rig::Runtime::Head.seen([head, update({ agents_md: nil })]))
    end

    it 'folds updates in order' do
      seen = Riffer::Rig::Runtime::Head.seen([head, update({ environment: 'LATER' }), update({ environment: 'LAST' })])

      assert_equal 'LAST', seen&.fetch(:environment)
    end
  end

  describe '.changes' do
    before do
      @seen = { agents_md: 'RULES', environment: 'ENV' }
    end

    it 'is empty when every section is as last seen' do
      assert_empty Riffer::Rig::Runtime::Head.changes(@seen, { agents_md: 'RULES', environment: 'ENV' })
    end

    it 'holds the new text of a changed section' do
      changes = Riffer::Rig::Runtime::Head.changes(@seen, { agents_md: 'RULES', environment: 'TOMORROW' })

      assert_equal({ environment: 'TOMORROW' }, changes)
    end

    it 'holds an added section' do
      changes = Riffer::Rig::Runtime::Head.changes(@seen, { agents_md: 'RULES', branch: 'main', environment: 'ENV' })

      assert_equal({ branch: 'main' }, changes)
    end

    it 'holds nil for a section that is gone' do
      assert_equal({ agents_md: nil }, Riffer::Rig::Runtime::Head.changes(@seen, { environment: 'ENV' }))
    end
  end
end
