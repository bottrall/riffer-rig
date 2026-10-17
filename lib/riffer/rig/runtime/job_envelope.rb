# frozen_string_literal: true

module Riffer::Rig::Runtime::JobEnvelope
  extend self

  # @rbs completions: Array[Riffer::Rig::Runtime::JobCompletion]
  # @rbs return: String
  def render(completions)
    completions.map { |completion| envelope(completion) }.join("\n")
  end

  private

  # @rbs completion: Riffer::Rig::Runtime::JobCompletion
  # @rbs return: String
  def envelope(completion)
    tail = completion.tail.strip
    [
      %(<background-job id="#{completion.job_id}" #{outcome(completion)} ) +
        %(duration="#{format('%.1fs', completion.duration)}">),
      "<command>#{completion.command}</command>",
      "<output-path>#{completion.output_path}</output-path>",
      "<output-tail>\n#{tail.empty? ? '(no output)' : tail}\n</output-tail>",
      '</background-job>'
    ].join("\n")
  end

  # @rbs completion: Riffer::Rig::Runtime::JobCompletion
  # @rbs return: String
  def outcome(completion)
    exit_status = completion.exit_status
    return %(status="killed" signal="#{completion.signal}") unless exit_status

    %(status="#{exit_status.zero? ? 'completed' : 'failed'}" exit-code="#{exit_status}")
  end
end
