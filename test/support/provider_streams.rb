# frozen_string_literal: true

require 'anthropic'
require 'openai'
require 'webrick'

class ProviderStreams
  SCRIPTS = File.expand_path('../fixtures/scripted_streams', __dir__)

  CLIENTS = {
    openai: OpenAI::Client,
    anthropic: Anthropic::Client,
    gemini: Riffer::Providers::Gemini::Client,
    openrouter: OpenAI::Client
  }.freeze

  # riffer's Bedrock provider needs the AWS SDK, which the bundle leaves out,
  # so its streams cannot be replayed from the wire. These are the events its
  # execute_stream emits, in its order: the finish reason at messageStop, the
  # usage at the metadata event after it.
  BEDROCK = {
    tool_call: [
      Riffer::StreamEvents::TextDelta.new('Let me read '),
      Riffer::StreamEvents::TextDelta.new('the file.'),
      Riffer::StreamEvents::ToolCallDelta.new(
        item_id: 'tooluse_01', name: 'read', arguments_delta: '{"path":"notes.txt"}'
      ),
      Riffer::StreamEvents::ToolCallDone.new(
        item_id: 'tooluse_01', call_id: 'tooluse_01', name: 'read', arguments: '{"path":"notes.txt"}'
      ),
      Riffer::StreamEvents::TextDone.new('Let me read the file.'),
      Riffer::StreamEvents::FinishReasonDone.new(
        finish_reason: Riffer::Providers::AmazonBedrock::FINISH_REASONS.fetch('tool_use'), raw_finish_reason: 'tool_use'
      ),
      Riffer::StreamEvents::TokenUsageDone.new(
        token_usage: Riffer::Providers::TokenUsage.new(input_tokens: 100, output_tokens: 20)
      )
    ],
    answer: [
      Riffer::StreamEvents::TextDelta.new('The file '),
      Riffer::StreamEvents::TextDelta.new('is empty.'),
      Riffer::StreamEvents::TextDone.new('The file is empty.'),
      Riffer::StreamEvents::FinishReasonDone.new(
        finish_reason: Riffer::Providers::AmazonBedrock::FINISH_REASONS.fetch('end_turn'), raw_finish_reason: 'end_turn'
      ),
      Riffer::StreamEvents::TokenUsageDone.new(
        token_usage: Riffer::Providers::TokenUsage.new(input_tokens: 150, output_tokens: 10)
      )
    ]
  }.freeze

  def initialize
    started = Queue.new
    @server = WEBrick::HTTPServer.new(
      Port: 0,
      BindAddress: '127.0.0.1',
      Logger: WEBrick::Log.new(File::NULL),
      AccessLog: [],
      StartCallback: -> { started << true }
    )
    @server.mount_proc('/') do |_request, response|
      response['Content-Type'] = 'text/event-stream'
      # WEBrick's shutdown waits half a second on every idle keep-alive
      # connection an SDK client leaves open.
      response.keep_alive = false
      response.body = @script
    end
    @thread = Thread.new { @server.start }
    # A shutdown that beats the server to its accept loop is lost, and the
    # loop then never ends.
    started.pop
  end

  def stop
    @server.shutdown
    @thread.join
  end

  def events(provider, scenario)
    provider == :amazon_bedrock ? BEDROCK.fetch(scenario) : replay(provider, scenario)
  end

  private

  def replay(provider, scenario)
    config = Riffer.config.public_send(provider)
    @script = File.read(File.join(SCRIPTS, provider.to_s, "#{scenario}.sse"))
    config.client = CLIENTS.fetch(provider).new(api_key: 'scripted', base_url: "http://127.0.0.1:#{@server.config[:Port]}")
    Riffer::Providers::Repository.find(provider).new.stream_text(prompt: 'go', model: 'scripted').to_a
  ensure
    config.client = nil
  end
end
