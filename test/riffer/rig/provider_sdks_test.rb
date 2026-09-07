# frozen_string_literal: true

require 'test_helper'

# riffer loads each provider's SDK on first use, so the gem only works for a
# provider whose SDK is in the bundle. Pin that for the ones the gemspec ships.
class Riffer::Rig::ProviderSDKsTest < Minitest::Test
  def test_openrouter_provider_loads_the_openai_sdk
    Riffer::Providers::OpenRouter.new

    assert defined?(::OpenAI::Client)
  end

  def test_anthropic_provider_loads_the_anthropic_sdk
    Riffer::Providers::Anthropic.new

    assert defined?(::Anthropic::Client)
  end
end
