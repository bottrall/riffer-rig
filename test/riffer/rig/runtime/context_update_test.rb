# frozen_string_literal: true

require 'test_helper'
require 'json'

describe Riffer::Rig::Runtime::ContextUpdate do
  describe '.of' do
    it 'gives the new text of a changed section in full' do
      update = Riffer::Rig::Runtime::ContextUpdate.of({ branch: "Branch:\nfeature" })

      assert_includes update.content, %(<section name="branch">\nBranch:\nfeature\n</section>)
    end

    it 'marks a section that is gone as removed' do
      update = Riffer::Rig::Runtime::ContextUpdate.of({ agents_md: nil })

      assert_includes update.content, '<section name="agents_md" removed="true"/>'
    end

    it 'tells the model each section replaces its earlier version' do
      update = Riffer::Rig::Runtime::ContextUpdate.of({ branch: 'Branch: feature' })

      assert_includes update.content, Riffer::Rig::Runtime::ContextUpdate::PREAMBLE
    end

    it 'gives the sections in the order of the changes' do
      content = Riffer::Rig::Runtime::ContextUpdate.of({ branch: 'B', environment: 'E' }).content

      assert_operator content.index('name="branch"'), :<, content.index('name="environment"')
    end

    it 'carries the changes as its sections' do
      changes = { branch: 'B', agents_md: nil }

      assert_equal changes, Riffer::Rig::Runtime::ContextUpdate.of(changes).sections
    end
  end

  describe '.from_hash' do
    it 'rebuilds the sections of the update' do
      stored = { role: 'user', content: '<context-update>', context_update: true, sections: { branch: 'B' } }

      assert_equal({ branch: 'B' }, Riffer::Rig::Runtime::ContextUpdate.from_hash(stored).sections)
    end

    it 'rebuilds the content of the update' do
      stored = { role: 'user', content: '<context-update>', context_update: true, sections: {} }

      assert_equal '<context-update>', Riffer::Rig::Runtime::ContextUpdate.from_hash(stored).content
    end
  end

  describe '#initialize' do
    it 'takes the files riffer joins into a message of its class' do
      update = Riffer::Rig::Runtime::ContextUpdate.new('<context-update>')

      assert_instance_of Riffer::Rig::Runtime::ContextUpdate, update + Riffer::Messages::User.new('Go')
    end
  end

  describe '#to_h' do
    it 'marks the user message hash as a context update carrying its sections' do
      update = Riffer::Rig::Runtime::ContextUpdate.new('<context-update>', sections: { agents_md: nil })

      assert_equal(
        { role: :user, content: '<context-update>', context_update: true, sections: { agents_md: nil } },
        update.to_h
      )
    end

    it 'keeps its sections through a JSON round trip' do
      update = Riffer::Rig::Runtime::ContextUpdate.of({ branch: 'B', agents_md: nil })
      stored = JSON.parse(JSON.generate(update.to_h), symbolize_names: true)

      assert_equal update.sections, Riffer::Rig::Runtime::ContextUpdate.from_hash(stored).sections
    end
  end
end
