# frozen_string_literal: true

require 'test_helper'

describe Riffer::Rig::Hosts::ErrorMessage do
  def status_error(message, body)
    StandardError.new(message).tap { |error| error.define_singleton_method(:body) { body } }
  end

  describe '.of' do
    it 'keeps the message alone for an error without a body' do
      assert_equal 'boom', Riffer::Rig::Hosts::ErrorMessage.of(StandardError.new('boom'))
    end

    it 'keeps the message alone for a body that is not a hash' do
      assert_equal 'status=502', Riffer::Rig::Hosts::ErrorMessage.of(status_error('status=502', 'Bad Gateway'))
    end

    it 'keeps the message alone for a body whose error is not a hash' do
      error = status_error('status=400', { error: 'bad request' })

      assert_equal 'status=400', Riffer::Rig::Hosts::ErrorMessage.of(error)
    end

    it 'keeps the message alone for a body error without a string message' do
      error = status_error('status=400', { error: { code: 400 } })

      assert_equal 'status=400', Riffer::Rig::Hosts::ErrorMessage.of(error)
    end

    it 'keeps the message alone when it already carries the body message' do
      error = status_error('status=400 message=model not found', { error: { message: 'model not found' } })

      assert_equal 'status=400 message=model not found', Riffer::Rig::Hosts::ErrorMessage.of(error)
    end

    it 'adds the message from the response body' do
      error = status_error('status=400 url=https://openrouter.ai', { error: { message: 'no/such-model is not valid' } })

      assert_equal 'status=400 url=https://openrouter.ai: no/such-model is not valid', Riffer::Rig::Hosts::ErrorMessage.of(error)
    end
  end
end
