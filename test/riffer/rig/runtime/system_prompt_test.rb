# frozen_string_literal: true

require 'test_helper'

describe Riffer::Rig::Runtime::SystemPrompt do
  before do
    @runtime = Object.new
    @environment = "Current date: #{Date.today}\nCurrent working directory: /tmp/proj"
  end

  def prompt(sections = {})
    Riffer::Rig::Runtime::SystemPrompt.new('BASE', '/tmp/proj', sections)
  end

  def session
    Riffer::Agent::Session.new(
      messages: [
        Riffer::Messages::System.new('STALE'),
        Riffer::Messages::User.new('hello'),
        Riffer::Messages::Assistant.new('Hi there.')
      ]
    )
  end

  describe '#bare' do
    it 'carries the date and cwd in the environment block under the base' do
      assert_equal "BASE\n\n#{@environment}", prompt.bare
    end

    it 'leaves the sections out' do
      assert_equal "BASE\n\n#{@environment}", prompt({ branch: ->(_runtime) { 'Branch: main' } }).bare
    end
  end

  describe '#render' do
    it 'renders sections in order between the base and the environment block' do
      sections = { first: ->(_runtime) { 'SECTION_ONE' }, second: ->(_runtime) { 'SECTION_TWO' } }

      assert_equal "BASE\n\nSECTION_ONE\n\nSECTION_TWO\n\n#{@environment}", prompt(sections).render(@runtime)
    end

    it 're-evaluates a section on every render' do
      branch = 'main'
      rendering = prompt({ branch: ->(_runtime) { "Branch: #{branch}" } })
      rendering.render(@runtime)
      branch = 'feature'

      assert_includes rendering.render(@runtime), 'Branch: feature'
    end

    it 'passes the runtime to a section' do
      seen = nil
      prompt({ spy: ->(runtime) { seen = runtime } }).render(@runtime)

      assert_same @runtime, seen
    end

    it 'skips a section that renders nothing' do
      assert_equal "BASE\n\n#{@environment}", prompt({ skills: ->(_runtime) {} }).render(@runtime)
    end
  end

  describe '#with_sections' do
    it 'renders the sections it is given' do
      swapped = prompt({ old: ->(_runtime) { 'OLD_SECTION' } }).with_sections({ new: ->(_runtime) { 'NEW_SECTION' } })

      assert_equal "BASE\n\nNEW_SECTION\n\n#{@environment}", swapped.render(@runtime)
    end

    it 'leaves the receiver rendering its own sections' do
      original = prompt({ old: ->(_runtime) { 'OLD_SECTION' } })
      original.with_sections({ new: ->(_runtime) { 'NEW_SECTION' } })

      assert_equal "BASE\n\nOLD_SECTION\n\n#{@environment}", original.render(@runtime)
    end
  end

  describe '#refresh' do
    it 'swaps the rendered prompt in as the system message' do
      refreshed = session
      prompt({ branch: ->(_runtime) { 'Branch: main' } }).refresh(refreshed, @runtime)

      assert_equal "BASE\n\nBranch: main\n\n#{@environment}", refreshed.messages.first.content
    end

    it 'keeps one system message across refreshes' do
      refreshed = session
      rendering = prompt({ branch: ->(_runtime) { 'Branch: main' } })
      rendering.refresh(refreshed, @runtime)
      rendering.refresh(refreshed, @runtime)

      assert_equal(%w[system user assistant], refreshed.messages.map { |message| message.role.to_s })
    end

    it 'keeps the messages after the system message' do
      refreshed = session
      history = refreshed.messages.drop(1)
      prompt.refresh(refreshed, @runtime)

      assert_equal history, refreshed.messages.drop(1)
    end
  end
end
