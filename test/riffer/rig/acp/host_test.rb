# frozen_string_literal: true

require 'test_helper'
require 'acp/sdk'

describe Riffer::Rig::ACP::Host do
  before do
    sent = [] #: Array[[String, ACP::Types::SessionUpdate::t]]
    permissions = [] #: Array[ACP::Types::RequestPermissionRequest]
    asked_at = [] #: Array[Integer]
    elicitations = [] #: Array[ACP::Types::CreateElicitationRequest]
    replies = @replies = { permission: selected('yes'), elicitation: accepted('answer' => 'Ada') }
    client = Object.new
    client.define_singleton_method(:update) { |session_id, update| sent << [session_id, update] }
    client.define_singleton_method(:request_permission) do |request|
      permissions << request
      asked_at << sent.size
      replies.fetch(:permission)
    end
    client.define_singleton_method(:create_elicitation) do |request|
      elicitations << request
      replies.fetch(:elicitation)
    end
    @host = Riffer::Rig::ACP::Host.new(client: client)
    @client = client
    @sent = sent
    @permissions = permissions
    @asked_at = asked_at
    @elicitations = elicitations
  end

  attr_reader :sent

  def selected(option_id)
    ACP::Types::RequestPermissionResponse.new(
      outcome: ACP::Types::RequestPermissionOutcome::Selected.new(option_id: option_id)
    )
  end

  def cancelled
    ACP::Types::RequestPermissionResponse.new(outcome: ACP::Types::RequestPermissionOutcome::Cancelled.new)
  end

  def accepted(content)
    ACP::Types::CreateElicitationResponse.new(
      action: ACP::Types::CreateElicitationResponse::Action::Accept.new(content: content)
    )
  end

  describe '#capabilities' do
    it 'reports only notify before it knows the session id' do
      assert_equal Set[:notify], @host.capabilities
    end

    it 'reports ask and confirm too once it knows the session id' do
      @host.session_id = 'session-1'

      assert_equal Set[:notify, :ask, :confirm], @host.capabilities
    end
  end

  describe '#ask' do
    it 'declines without eliciting before it knows the session id' do
      @host.ask('Which model?')

      assert_empty @elicitations
    end

    describe 'once it knows the session id' do
      before { @host.session_id = 'session-1' }

      it 'declines a secret ask without eliciting it' do
        @host.ask('API key?', secret: true)

        assert_empty @elicitations
      end

      it 'declines a secret ask with options without asking permission' do
        @host.ask('Key?', options: %w[a b], secret: true)

        assert_empty @permissions
      end

      it 'elicits a free-text ask on its session' do
        @host.ask('Name?')

        assert_equal 'session-1', @elicitations.first.mode.scope.session_id
      end

      it 'elicits a free-text ask with the question as its message' do
        @host.ask('Name?')

        assert_equal 'Name?', @elicitations.first.message
      end

      it 'answers a free-text ask with the elicited answer' do
        assert_equal 'Ada', @host.ask('Name?')
      end

      it 'declines a free-text ask the client declines' do
        @replies[:elicitation] = ACP::Types::CreateElicitationResponse.new(
          action: ACP::Types::CreateElicitationResponse::Action::Decline.new
        )

        assert_nil @host.ask('Name?')
      end

      it 'offers the options of an ask as permission options' do
        @host.ask('Colour?', options: %w[red blue])

        assert_equal(%w[red blue], @permissions.first.options.map(&:name))
      end

      it 'closes the tool call of an ask with options once the client answers' do
        @host.ask('Colour?', options: %w[red blue])

        assert_equal(
          [@permissions.first.tool_call.tool_call_id],
          sent.drop(@asked_at.first).map { |_, update| update.tool_call_id }
        )
      end

      it 'answers an ask with options with the selected option' do
        @replies[:permission] = selected('blue')

        assert_equal 'blue', @host.ask('Colour?', options: %w[red blue])
      end

      it 'declines an ask whose selected option was never offered' do
        assert_nil @host.ask('Colour?', options: %w[red blue])
      end

      it 'declines an ask with options when the client cancels the request' do
        @replies[:permission] = cancelled

        assert_nil @host.ask('Colour?', options: %w[red blue])
      end
    end
  end

  describe '#confirm' do
    it 'declines without asking permission before it knows the session id' do
      @host.confirm('Trust this project?')

      assert_empty @permissions
    end

    describe 'once it knows the session id' do
      before { @host.session_id = 'session-1' }

      it 'announces the tool call of its question on its session before asking' do
        @host.confirm('Trust this project?')

        assert_equal(
          [['session-1', @permissions.first.tool_call.tool_call_id]],
          sent.take(@asked_at.first).map { |session_id, update| [session_id, update.tool_call_id] }
        )
      end

      it 'asks permission on its session' do
        @host.confirm('Trust this project?')

        assert_equal 'session-1', @permissions.first.session_id
      end

      it 'offers yes and no' do
        @host.confirm('Trust this project?')

        assert_equal(%w[Yes No], @permissions.first.options.map(&:name))
      end

      it 'closes the tool call of its question on its session once the client answers' do
        @host.confirm('Trust this project?')

        assert_equal(
          [['session-1', @permissions.first.tool_call.tool_call_id]],
          sent.drop(@asked_at.first).map { |session_id, update| [session_id, update.tool_call_id] }
        )
      end

      it 'closes the tool call on the client it asked when another adopts the session meanwhile' do
        host = @host
        reply = selected('yes')
        asked_id = nil
        @client.define_singleton_method(:request_permission) do |request|
          asked_id = request.tool_call.tool_call_id
          host.client = Object.new
          reply
        end
        @host.confirm('Trust this project?')

        assert_equal([asked_id, asked_id], sent.map { |_, update| update.tool_call_id })
      end

      it 'confirms when the client selects yes' do
        assert @host.confirm('Trust this project?')
      end

      it 'declines when the client selects no' do
        @replies[:permission] = selected('no')

        refute @host.confirm('Trust this project?')
      end

      it 'declines when the client cancels the request' do
        @replies[:permission] = cancelled

        refute @host.confirm('Trust this project?')
      end

      it 'declines when the request fails' do
        @replies[:permission] = ACP::RequestError.new(code: ACP::RequestError::INTERNAL_ERROR, message: 'closed')

        refute @host.confirm('Trust this project?')
      end
    end
  end

  describe '#notify' do
    it 'sends a notify after the session id as a notice' do
      @host.session_id = 'session-1'
      @host.notify('Live')

      assert_equal Riffer::Rig::ACP::Mapper.notice('Live').to_h, sent.first.last.to_h
    end
  end

  describe '#update' do
    it 'buffers an update until it knows the session id' do
      @host.update(Riffer::Rig::ACP::Mapper.job_exit)

      assert_empty sent
    end

    it 'sends an update on the session id it was given' do
      update = Riffer::Rig::ACP::Mapper.job_exit
      @host.session_id = 'session-1'
      @host.update(update)

      assert_equal [['session-1', update]], sent
    end
  end

  describe '#progress' do
    it 'notifies the progress label' do
      @host.session_id = 'session-1'
      @host.progress('Installing')

      assert_equal Riffer::Rig::ACP::Mapper.notice('Installing').to_h, sent.first.last.to_h
    end

    it 'sends nothing from progress without a label' do
      @host.session_id = 'session-1'
      @host.progress { nil }

      assert_empty sent
    end

    it 'yields to the block given to progress' do
      yielded = false
      @host.progress('Installing') { yielded = true }

      assert yielded
    end
  end

  describe '#session_id=' do
    it 'flushes the buffered notifies in order when the session id arrives' do
      @host.notify('First')
      @host.notify('Second', level: :error)
      @host.session_id = 'session-1'

      notices = %w[First Second].map { |text| Riffer::Rig::ACP::Mapper.notice(text).to_h }

      assert_equal(notices, sent.map { |_, update| update.to_h })
    end
  end
end
