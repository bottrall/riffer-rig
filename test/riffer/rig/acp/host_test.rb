# frozen_string_literal: true

require 'test_helper'
require 'acp/sdk'

describe Riffer::Rig::ACP::Host do
  before do
    sent = [] #: Array[[String, ACP::Types::SessionUpdate::t]]
    client = Object.new
    client.define_singleton_method(:update) { |session_id, update| sent << [session_id, update] }
    @host = Riffer::Rig::ACP::Host.new(client: client)
    @sent = sent
  end

  attr_reader :sent

  it 'reports only notify' do
    assert_equal Set[:notify], @host.capabilities
  end

  it 'buffers a notify until it knows the session id' do
    @host.notify('Buffered', level: :warning)

    assert_empty sent
  end

  it 'sends a notify after the session id as an agent message chunk with its text' do
    @host.session_id = 'session-1'
    @host.notify('Live')

    assert_equal 'Live', sent.first.last.content.text
  end

  it 'sends a notify on the session id it was given' do
    @host.session_id = 'session-1'
    @host.notify('Live')

    assert_equal 'session-1', sent.first.first
  end

  it 'yields to the block given to progress' do
    yielded = false
    @host.progress('Installing') { yielded = true }

    assert yielded
  end

  it 'notifies the progress label' do
    @host.session_id = 'session-1'
    @host.progress('Installing')

    assert_equal 'Installing', sent.first.last.content.text
  end

  it 'sends nothing from progress without a label' do
    @host.session_id = 'session-1'
    @host.progress { nil }

    assert_empty sent
  end

  it 'flushes the buffered notifies in order when the session id arrives' do
    @host.notify('First')
    @host.notify('Second', level: :error)
    @host.session_id = 'session-1'

    assert_equal(%w[First Second], sent.map { |_, update| update.content.text })
  end
end
