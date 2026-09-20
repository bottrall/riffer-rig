# frozen_string_literal: true

require 'test_helper'

describe Riffer::Rig::Hosts::Mirror do
  before do
    @calls = calls = []
    @wrapped = Class.new(Riffer::Rig::Hosts::Base) do
      define_method(:capabilities) { Set[:ask, :notify].freeze }
      define_method(:ask) do |question = nil, options: nil, secret: false|
        calls << [:ask, question, options, secret]
        'answer'
      end
      define_method(:confirm) do |question = nil|
        calls << [:confirm, question]
        true
      end
      define_method(:notify) { |message = nil, level: :info| calls << [:notify, message, level] }
      define_method(:progress) do |label = nil, &block|
        calls << [:progress, label]
        block&.call
      end
    end.new
    @host = Riffer::Rig::Hosts::Mirror.new(@wrapped)
  end

  it 'implements every host method' do
    assert_implements Riffer::Rig::Hosts::Base, Riffer::Rig::Hosts::Mirror
  end

  it 'reports the wrapped host capabilities' do
    assert_equal Set[:ask, :notify], @host.capabilities
  end

  it 'forwards ask to the wrapped host' do
    @host.ask('token?', options: %w[a b], secret: true)

    assert_equal [[:ask, 'token?', %w[a b], true]], @calls
  end

  it 'returns the wrapped host answer from ask' do
    assert_equal 'answer', @host.ask('token?')
  end

  it 'forwards confirm to the wrapped host' do
    @host.confirm('sure?')

    assert_equal [[:confirm, 'sure?']], @calls
  end

  it 'returns the wrapped host answer from confirm' do
    assert @host.confirm('sure?')
  end

  it 'forwards notify to the wrapped host' do
    @host.notify('boom', level: :error)

    assert_equal [[:notify, 'boom', :error]], @calls
  end

  it 'queues a notify event for every notify' do
    @host.notify('boom', level: :error)

    assert_equal [Riffer::Rig::Events::Notify.new('boom', :error)], @host.drain
  end

  it 'forwards progress to the wrapped host' do
    @host.progress('working') { nil }

    assert_equal [[:progress, 'working']], @calls
  end

  it 'yields from progress' do
    yielded = false
    @host.progress('working') { yielded = true }

    assert yielded
  end

  it 'drains queued events in order' do
    first = Riffer::Rig::Events::Notify.new('one', :info)
    second = Riffer::Rig::Events::Notify.new('two', :warn)
    @host.queue(first)
    @host.queue(second)

    assert_equal [first, second], @host.drain
  end

  it 'empties the queue on drain' do
    @host.queue(Riffer::Rig::Events::Notify.new('one', :info))
    @host.drain

    assert_empty @host.drain
  end
end
