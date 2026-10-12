# frozen_string_literal: true

class Riffer::Rig::Events::BeforePrompt
  extend Riffer::Rig::Support::TypedValue::Schema #[Symbol]
  include Riffer::Rig::Support::TypedValue #[Symbol]

  typed_value :before_prompt, :text

  # @dynamic text
  attr_reader :text #: String

  # @rbs text: String
  # @rbs return: void
  def initialize(text)
    @text = text
    freeze
  end
end
