# frozen_string_literal: true

require 'test_helper'
require 'stringio'

describe Riffer::Rig::CLI do
  it 'start runs a session and returns zero' do
    with_clean_global_state do
      ENV['ANTHROPIC_API_KEY'] = 'sk-ant-test'

      exit_code = Riffer::Rig::CLI.start(output: StringIO.new, input: StringIO.new(''))

      assert_equal 0, exit_code
    end
  end

  private

  # CLI.start mutates the global Riffer config and reads ENV; snapshot and
  # restore both so tests leave no residue.
  def with_clean_global_state
    previous = {
      anthropic: Riffer.config.anthropic.api_key,
      openai: Riffer.config.openai.api_key,
      gemini: Riffer.config.gemini.api_key,
      openrouter: Riffer.config.openrouter.api_key
    }
    previous_env = {
      'ANTHROPIC_API_KEY' => ENV.fetch('ANTHROPIC_API_KEY', nil),
      'OPENAI_API_KEY' => ENV.fetch('OPENAI_API_KEY', nil),
      'GEMINI_API_KEY' => ENV.fetch('GEMINI_API_KEY', nil),
      'OPENROUTER_API_KEY' => ENV.fetch('OPENROUTER_API_KEY', nil)
    }

    yield
  ensure
    Riffer.config.anthropic.api_key  = previous[:anthropic]
    Riffer.config.openai.api_key     = previous[:openai]
    Riffer.config.gemini.api_key     = previous[:gemini]
    Riffer.config.openrouter.api_key = previous[:openrouter]
    previous_env.each { |k, v| v ? ENV[k] = v : ENV.delete(k) }
  end
end
