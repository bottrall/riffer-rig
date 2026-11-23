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

  describe '.new' do
    it 'evaluates only the environment block when no sections are given' do
      values = Riffer::Rig::Runtime::SystemPrompt.new('BASE', '/tmp/proj').values(@runtime)

      assert_equal({ environment: @environment }, values)
    end
  end

  describe '#with_sections' do
    it 'evaluates the sections it is given' do
      swapped = prompt({ old: ->(_runtime) { 'OLD_SECTION' } }).with_sections({ new: ->(_runtime) { 'NEW_SECTION' } })

      assert_equal({ new: 'NEW_SECTION', environment: @environment }, swapped.values(@runtime))
    end

    it 'leaves the receiver evaluating its own sections' do
      original = prompt({ old: ->(_runtime) { 'OLD_SECTION' } })
      original.with_sections({ new: ->(_runtime) { 'NEW_SECTION' } })

      assert_equal({ old: 'OLD_SECTION', environment: @environment }, original.values(@runtime))
    end
  end

  describe '#bare' do
    it 'carries the date and cwd in the environment block under the base' do
      assert_equal "BASE\n\n#{@environment}", prompt.bare
    end

    it 'leaves the sections out' do
      assert_equal "BASE\n\n#{@environment}", prompt({ branch: ->(_runtime) { 'Branch: main' } }).bare
    end
  end

  describe '#values' do
    it 'evaluates sections in order, then the environment block' do
      sections = { first: ->(_runtime) { 'SECTION_ONE' }, second: ->(_runtime) { 'SECTION_TWO' } }

      assert_equal %i[first second environment], prompt(sections).values(@runtime).keys
    end

    it 're-evaluates a section on every call' do
      branch = 'main'
      evaluating = prompt({ branch: ->(_runtime) { "Branch: #{branch}" } })
      evaluating.values(@runtime)
      branch = 'feature'

      assert_equal 'Branch: feature', evaluating.values(@runtime)[:branch]
    end

    it 'passes the runtime to a section' do
      seen = nil
      prompt({ spy: ->(runtime) { seen = runtime } }).values(@runtime)

      assert_same @runtime, seen
    end

    it 'leaves out a section that renders nothing' do
      assert_equal({ environment: @environment }, prompt({ skills: ->(_runtime) {} }).values(@runtime))
    end

    it 'leaves out a section that renders an empty string' do
      assert_equal({ environment: @environment }, prompt({ empty: ->(_runtime) { '' } }).values(@runtime))
    end
  end

  describe '#render' do
    it 'joins the base and the values with blank lines' do
      assert_equal "BASE\n\nSECTION_ONE\n\nENV", prompt.render({ first: 'SECTION_ONE', environment: 'ENV' })
    end
  end
end
