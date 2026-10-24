# frozen_string_literal: true

class Riffer::Rig::Runtime::JobNotices
  # @rbs @jobs: Riffer::Rig::Runtime::Jobs
  # @rbs @inbox: Riffer::Rig::Runtime::JobInbox
  # @rbs @emit: ^(Riffer::Rig::Events::_Event) -> void
  # @rbs @deliver: ^(Riffer::Messages::Base) -> void

  # @rbs jobs: Riffer::Rig::Runtime::Jobs
  # @rbs inbox: Riffer::Rig::Runtime::JobInbox
  # @rbs emit: ^(Riffer::Rig::Events::_Event) -> void
  # @rbs deliver: ^(Riffer::Messages::Base) -> void
  # @rbs return: void
  def initialize(jobs, inbox, emit:, deliver:)
    @jobs = jobs
    @inbox = inbox
    @emit = emit
    @deliver = deliver
    freeze
  end

  # @rbs return: Integer
  def running_count
    @jobs.list.count(&:active?)
  end

  # @rbs return: bool
  def pending?
    # Jobs stay listed from their start until the model is told of their exit.
    @jobs.list.any?
  end

  # @rbs timeout: Numeric?
  # @rbs return: bool
  def await(timeout)
    @inbox.await(timeout)
  end

  # @rbs return: Integer
  def pending_exit_count
    @inbox.size
  end

  # @rbs message: Riffer::Messages::Tool
  # @rbs session: Riffer::Agent::Session
  # @rbs return: Riffer::Messages::Tool
  def with_notice(message, session)
    completions = exits
    return message if completions.empty?

    # Appended to a tool result because a user message straight after one is
    # consecutive user turns to Bedrock and Gemini, which reject them.
    noticed = Riffer::Messages::Tool.new(
      "#{message.content}\n\n#{Riffer::Rig::Runtime::JobEnvelope.render(completions)}",
      tool_call_id: message.tool_call_id,
      name: message.name,
      id: message.id,
      error: message.error,
      error_type: message.error_type
    )
    # By identity: Session#update finds a result by its call id, which need
    # not be unique within a session.
    session.set(session.messages.map { |recorded| recorded.equal?(message) ? noticed : recorded })
    noticed
  end

  # @rbs session: Riffer::Agent::Session
  # @rbs follow_up: bool
  # @rbs return: Riffer::Messages::Base?
  def notify(session, follow_up: false)
    completions = exits
    return if completions.empty?

    notification = Riffer::Rig::Runtime::JobNotification.new(
      Riffer::Rig::Runtime::JobEnvelope.render(completions),
      follow_up_exits: (completions.size if follow_up)
    )
    # Silent, then delivered by hand: the on_message observer interrupts a
    # cancelled turn with a throw, and no riffer run is there to catch it.
    session.add(notification, silent: true).tap { |message| @deliver.call(message) }
  end

  private

  # @rbs return: Array[Riffer::Rig::Runtime::JobCompletion]
  def exits
    @jobs.consume.each { |completion| @emit.call(Riffer::Rig::Events::JobExit.new(completion)) }
  end
end
