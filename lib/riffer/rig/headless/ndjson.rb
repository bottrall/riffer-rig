# frozen_string_literal: true

require 'json'

module Riffer::Rig::Headless::Ndjson
  extend self

  # @rbs event: ::Riffer::StreamEvents::Base | Riffer::Rig::Events::_Event
  # @rbs return: String
  def line(event)
    "#{JSON.generate(envelope(event))}\n"
  end

  # @rbs message: String
  # @rbs return: String
  def error(message)
    "#{JSON.generate({ 'type' => 'error', 'message' => message })}\n"
  end

  # @rbs event: ::Riffer::StreamEvents::Base | Riffer::Rig::Events::_Event
  # @rbs return: Hash[String, Riffer::Rig::Headless::json]
  def envelope(event)
    json_hash(event.to_h).merge('type' => event_type(event))
  end

  # @rbs hash: Hash[Symbol, untyped]
  # @rbs return: Hash[String, Riffer::Rig::Headless::json]
  def json_hash(hash)
    hash.to_h { |key, item| [key.to_s, json_value(item)] }
  end

  # @rbs event: ::Riffer::StreamEvents::Base | Riffer::Rig::Events::_Event
  # @rbs return: String
  def event_type(event)
    event.class.name.to_s.split('::').last.to_s.gsub(/(?<=[a-z\d])(?=[A-Z])|(?<=[A-Z])(?=[A-Z][a-z])/, '_').downcase
  end

  # @rbs value: untyped
  # @rbs return: Riffer::Rig::Headless::json
  def json_value(value)
    case value
    when String, Integer, Float, true, false, nil then value
    when Symbol then value.to_s
    when Hash then value.to_h { |key, item| [key.to_s, json_value(item)] }
    when Array then value.map { |item| json_value(item) }
    else value.respond_to?(:to_h) ? json_value(value.to_h) : value.to_s
    end
  end
end
