# frozen_string_literal: true

require 'test_helper'
require 'stringio'

class Riffer::Rig::CLITest < Minitest::Test
  def test_start_runs_a_session_and_returns_zero
    with_clean_global_state do
      ENV['ANTHROPIC_API_KEY'] = 'sk-ant-test'

      exit_code = Riffer::Rig::CLI.start(output: StringIO.new, input: StringIO.new(''))

      assert_equal 0, exit_code
    end
  end

  def test_configure_provider_configures_the_openrouter_key
    with_clean_global_state do
      Riffer::Rig::CLI.send(:configure_provider, 'openrouter', 'sk-or-test')

      assert_equal 'sk-or-test', Riffer.config.openrouter.api_key
    end
  end

  def test_configure_provider_reports_a_missing_sdk_rather_than_raising
    status, = Riffer::Rig::CLI.send(:configure_provider, 'openrouter', 'sk-or-test', loader: ->(_name) { raise LoadError })

    assert_equal :error, status
  end

  def test_missing_sdk_message_names_the_openai_gem
    _status, message = Riffer::Rig::CLI.send(:configure_provider, 'openai', 'sk-test', loader: ->(_name) { raise LoadError })

    assert_includes message, 'openai'
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
