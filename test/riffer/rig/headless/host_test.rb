# frozen_string_literal: true

require 'test_helper'
require 'stringio'

describe Riffer::Rig::Headless::Host do
  before do
    @error = StringIO.new
    @host = Riffer::Rig::Headless::Host.new(error: @error)
  end

  it 'reports notify and progress as its capabilities' do
    assert_equal Set[:notify, :progress], @host.capabilities
  end

  it 'declines an ask' do
    assert_nil @host.ask('Which model?')
  end

  it 'declines a confirm' do
    refute @host.confirm('Trust this project?')
  end

  it 'prints a notify to stderr' do
    @host.notify('heads up', level: :warning)

    assert_equal "heads up\n", @error.string
  end

  it 'keeps a notify off stderr in --json mode' do
    host = Riffer::Rig::Headless::Host.new(error: @error, json: true)

    host.notify('heads up', level: :warning)

    assert_empty @error.string
  end

  it 'prints a progress label to stderr' do
    @host.progress('installing') { nil }

    assert_equal "installing\n", @error.string
  end

  it 'yields the progress block' do
    yielded = false

    @host.progress { yielded = true }

    assert yielded
  end
end
