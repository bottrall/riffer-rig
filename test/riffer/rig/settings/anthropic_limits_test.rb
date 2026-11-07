# frozen_string_literal: true

require 'test_helper'
require 'anthropic'
require 'json'
require 'webrick'

class ModelsApi
  attr_reader :requests #: Array[String?]

  def initialize(models)
    @requests = []
    started = Queue.new
    @server = WEBrick::HTTPServer.new(
      Port: 0,
      BindAddress: '127.0.0.1',
      Logger: WEBrick::Log.new(File::NULL),
      AccessLog: [],
      StartCallback: -> { started << true }
    )
    @server.mount_proc('/v1/models/') { |request, response| answer(models, request, response) }
    @thread = Thread.new { @server.start }
    started.pop
  end

  def url
    "http://127.0.0.1:#{@server.config[:Port]}"
  end

  def stop
    @server.shutdown
    @thread.join
  end

  private

  def answer(models, request, response)
    id = request.path.delete_prefix('/v1/models/')
    @requests << request['x-api-key']
    response.keep_alive = false
    response['Content-Type'] = 'application/json'
    model = models[id]
    response.status = model ? 200 : 404
    response.body = JSON.generate(model ? { type: 'model', id: id, **model } : not_found(id))
  end

  def not_found(id)
    { type: 'error', error: { type: 'not_found_error', message: "model: #{id}" } }
  end
end

describe Riffer::Rig::Settings::AnthropicLimits do
  def with_env(vars)
    saved = vars.keys.to_h { |key| [key, ENV.fetch(key, nil)] }
    vars.each { |key, value| ENV[key] = value }
    yield
  ensure
    saved&.each { |key, value| ENV[key] = value }
  end

  before do
    @api = ModelsApi.new({ 'claude-big' => { max_tokens: 64_000 }, 'claude-uncapped' => { max_tokens: nil } })
    @config = Riffer::Config.new
    @config.anthropic.client = Anthropic::Client.new(api_key: 'sk-ant-client', base_url: @api.url)
  end

  after do
    @api.stop
  end

  describe '#max_tokens' do
    def limits
      @limits ||= Riffer::Rig::Settings::AnthropicLimits.new(@config)
    end

    it "is the model's output limit" do
      assert_equal 64_000, limits.max_tokens('claude-big')
    end

    it 'asks the Models API once per model' do
      2.times { limits.max_tokens('claude-big') }

      assert_equal 1, @api.requests.size
    end

    it 'is nil for a model the API reports no limit for' do
      assert_nil limits.max_tokens('claude-uncapped')
    end

    it 'is nil when the lookup fails' do
      assert_nil limits.max_tokens('claude-unknown')
    end

    it 'asks through the configured client' do
      limits.max_tokens('claude-big')

      assert_equal 'sk-ant-client', @api.requests.last
    end

    it 'asks with the configured key when no client is configured' do
      @config.anthropic.client = nil
      @config.anthropic.api_key = 'sk-ant-config'
      with_env('ANTHROPIC_BASE_URL' => @api.url) { limits.max_tokens('claude-big') }

      assert_equal 'sk-ant-config', @api.requests.last
    end

    it "asks with the SDK's own key when neither a client nor a key is configured" do
      @config.anthropic.client = nil
      with_env('ANTHROPIC_BASE_URL' => @api.url, 'ANTHROPIC_API_KEY' => 'sk-ant-env') do
        limits.max_tokens('claude-big')
      end

      assert_equal 'sk-ant-env', @api.requests.last
    end
  end
end
