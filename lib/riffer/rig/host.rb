# frozen_string_literal: true

# A host receives questions and out-of-band messages from a Session. It is
# duck-typed: any object with #ask, #confirm, #notify, #progress and
# #capabilities is a host.
#
#   class HeadlessHost
#     def capabilities = Set[:notify, :progress].freeze
#     def ask(*) = nil
#     def confirm(*) = false
#     def notify(message, level:) = warn("[#{level}] #{message}")
#     def progress(label) = yield
#   end
#
# Callers check #capabilities before asking, so a host that declines a
# capability is never asked and the caller takes the declined path.
# The do-nothing host: the default +host:+ for a Session. Every capability is
# declined, so callers take the declined path without any UI attempt.
class Riffer::Rig::Host
  # @rbs return: Set[Symbol]
  def capabilities
    Set.new.freeze
  end

  # @rbs _question: String?
  # @rbs options: Array[String]?
  # @rbs secret: bool
  # @rbs return: String?
  def ask(_question = nil, options: nil, secret: false)
    nil
  end

  # @rbs _question: String?
  # @rbs return: bool
  def confirm(_question = nil)
    false
  end

  # @rbs _message: String?
  # @rbs level: Symbol
  # @rbs return: void
  def notify(_message = nil, level: :info)
    nil
  end

  # @rbs _label: String?
  # @rbs &block: ^() -> void
  # @rbs return: void
  def progress(_label = nil, &block)
    block&.call
  end
end
