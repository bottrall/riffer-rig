# frozen_string_literal: true

require 'test_helper'
require 'stringio'

describe Riffer::Rig::CLI do
  it 'start runs a session and returns zero' do
    with_clean_global_state do
      exit_code = Riffer::Rig::CLI.start(
        output: StringIO.new,
        input: StringIO.new(''),
        model: 'anthropic/claude-sonnet-4-6',
        env: Riffer::Rig::Env.new('ANTHROPIC_API_KEY' => 'sk-ant-test')
      )

      assert_equal 0, exit_code
    end
  end

  private

  def with_clean_global_state
    # CLI.start mutates the global Riffer config.
    previous = {
      anthropic: Riffer.config.anthropic.api_key,
      openai: Riffer.config.openai.api_key,
      gemini: Riffer.config.gemini.api_key,
      openrouter: Riffer.config.openrouter.api_key
    }

    yield
  ensure
    Riffer.config.anthropic.api_key  = previous[:anthropic]
    Riffer.config.openai.api_key     = previous[:openai]
    Riffer.config.gemini.api_key     = previous[:gemini]
    Riffer.config.openrouter.api_key = previous[:openrouter]
  end
end
