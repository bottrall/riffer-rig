# frozen_string_literal: true

require 'test_helper'

describe Riffer::Rig::Commands::Switch do
  before do
    @host = Riffer::Rig::Hosts::Mirror.new(Riffer::Rig::Hosts::Null.new)
    @stored = []
    @switched = []
  end

  def run_switch(args, current: 'old', refusal: nil, accept: true)
    events = []
    ctx = Riffer::Rig::Command::Context.new(
      'thing', args, runtime: nil, host: @host, settings: {}, emit: ->(event) { events << event }, turn: ->(_text) {}
    )
    Riffer::Rig::Commands::Switch.run(
      ctx,
      label: 'Thing',
      shown: current || 'none',
      current: current,
      unset: 'No thing is in effect to save',
      saved_to: '/home/.riffer/settings.json',
      store: lambda { |value|
        @stored << value
        refusal
      }
    ) do |value|
      @switched << value
      accept
    end
    events + @host.drain
  end

  def output(text)
    Riffer::Rig::Events::CommandOutput.new('thing', text)
  end

  describe 'without a value' do
    it 'reports the value shown' do
      assert_equal [output('Thing: none')], run_switch('', current: nil)
    end

    it 'reports that nothing is in effect to save' do
      assert_equal [output('No thing is in effect to save')], run_switch('--save', current: nil)
    end

    it 'stores the current value' do
      run_switch('--save')

      assert_equal ['old'], @stored
    end

    it 'reports a refused save instead of the save' do
      assert_equal [Riffer::Rig::Events::Notify.new('cannot write', :error)],
                   run_switch('--save', refusal: 'cannot write')
    end

    it 'reports the saved value' do
      assert_equal [output('Saved old to /home/.riffer/settings.json')], run_switch('--save')
    end
  end

  describe 'with a value' do
    it 'hands the value, without --save, to the switch' do
      run_switch('new --save')

      assert_equal ['new'], @switched
    end

    it 'reports nothing more when the switch refuses' do
      assert_empty run_switch('new --save', accept: false)
    end

    it 'stores nothing when the switch refuses' do
      run_switch('new --save', accept: false)

      assert_empty @stored
    end

    it 'reports the switch' do
      assert_equal [output('Thing switched to new')], run_switch('new')
    end

    it 'stores nothing without --save' do
      run_switch('new')

      assert_empty @stored
    end

    it 'stores the new value with --save' do
      run_switch('new --save')

      assert_equal ['new'], @stored
    end

    it 'reports the switch and the save' do
      assert_equal [output('Thing switched to new and saved to /home/.riffer/settings.json')], run_switch('new --save')
    end

    it 'reports the switch and then a refused save' do
      assert_equal [output('Thing switched to new'), Riffer::Rig::Events::Notify.new('cannot write', :error)],
                   run_switch('new --save', refusal: 'cannot write')
    end
  end
end
