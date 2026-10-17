# frozen_string_literal: true

require 'test_helper'
require 'anthropic'
require 'openai'

describe Riffer::Rig::Runtime::ErrorMessage do
  def status_error(message, body)
    StandardError.new(message).tap { |error| error.define_singleton_method(:body) { body } }
  end

  def sdk_error(status_error_class, url, message)
    status_error_class.for(
      url: URI(url),
      status: 400,
      headers: {},
      body: { error: { message: message } },
      request: nil,
      response: nil
    )
  end

  describe '.of' do
    it 'keeps the message alone for an error without a body' do
      assert_equal 'boom', Riffer::Rig::Runtime::ErrorMessage.of(StandardError.new('boom'))
    end

    it 'keeps the message alone for a body that is not a hash' do
      assert_equal 'status=502', Riffer::Rig::Runtime::ErrorMessage.of(status_error('status=502', 'Bad Gateway'))
    end

    it 'keeps the message alone for a body whose error is not a hash' do
      error = status_error('status=400', { error: 'bad request' })

      assert_equal 'status=400', Riffer::Rig::Runtime::ErrorMessage.of(error)
    end

    it 'keeps the message alone for a body error without a string message' do
      error = status_error('status=400', { error: { code: 400 } })

      assert_equal 'status=400', Riffer::Rig::Runtime::ErrorMessage.of(error)
    end

    it 'keeps the message alone when it already carries the body message' do
      error = sdk_error(Anthropic::Errors::APIStatusError, 'https://api.anthropic.com/v1/messages', 'model not found')

      assert_equal error.message, Riffer::Rig::Runtime::ErrorMessage.of(error)
    end

    it 'adds the message from the response body' do
      error = sdk_error(OpenAI::Errors::APIStatusError, 'https://openrouter.ai/api', 'no/such-model is not valid')

      assert_equal 'status=400 url=https://openrouter.ai/api: no/such-model is not valid',
                   Riffer::Rig::Runtime::ErrorMessage.of(error)
    end
  end
end
