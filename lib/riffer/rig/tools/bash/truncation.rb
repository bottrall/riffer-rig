# frozen_string_literal: true

module Riffer::Rig::Tools::Bash::Truncation
  # @rbs output: String
  # @rbs return: String
  def truncate(output)
    max = Riffer::Rig::Tools::Bash::MAX_OUTPUT_BYTES
    return output if output.bytesize <= max

    "#{output.byteslice(0, max)&.scrub('')}\n[output truncated to #{max} bytes]"
  end
end
