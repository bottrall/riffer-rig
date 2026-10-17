# frozen_string_literal: true

module Riffer::Rig::Runtime::ErrorMessage
  extend self

  # @rbs error: StandardError
  # @rbs return: String
  def of(error)
    detail = body_message(error)
    detail && !error.message.include?(detail) ? "#{error.message}: #{detail}" : error.message
  end

  private

  # @rbs error: StandardError
  # @rbs return: String?
  def body_message(error)
    # The provider SDKs are optional gems, so their status errors are matched
    # by duck type: each carries the decoded response body as #body.
    return unless error.respond_to?(:body)

    body = error.public_send(:body) # rubocop:disable Style/SendWithLiteralMethodName -- StandardError declares no #body, so Steep accepts the duck-typed call only through public_send
    payload = body[:error] if body.is_a?(Hash)
    message = payload[:message] if payload.is_a?(Hash)
    message if message.is_a?(String)
  end
end
