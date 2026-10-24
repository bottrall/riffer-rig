# Custom providers

An extension can register a provider class under a new model prefix. riffer-rig then treats it like a built-in: first-run onboarding, `/model` and `/auth` list it, its credentials resolve the [same way](CONFIGURATION.md#where-each-value-comes-from), and its SDK gem is offered like a built-in's.

## Registering a provider

```ruby
# .riffer/rig.rb
class AcmeProvider < Riffer::Providers::Base
  private

  def build_client
    AcmeSdk::Client.new(api_key: Riffer::Rig.credentials(:acme)[:api_key])
  end

  # build_request_params, execute_generate, execute_stream, extract_token_usage,
  # extract_assistant_message, convert_messages and the rest of riffer's provider hooks
end

Riffer::Rig.extension('acme') do |rig|
  rig.provider(:acme, setup: {
    url: 'https://acme.example.com/keys',
    sdk: ['acme_sdk', '~> 2.0'],
    fields: [{ name: :api_key, env: ['ACME_API_KEY'], secret: true, required: true }]
  }) { AcmeProvider }
end
```

Then `acme/some-model` works anywhere a model string does. The provider class itself is riffer's: riffer's [custom provider guide](https://riffer.ai/guides/providers/custom/) covers every hook, streaming, tool calls and reasoning.

A provider registration is process-wide and is never removed: a reload or a second Runtime registering the same prefix replaces it with the same class.

## The setup

| Key      | Meaning                                                                                    | Default |
| -------- | ------------------------------------------------------------------------------------------ | ------- |
| `fields` | the values the provider needs (below)                                                      | required |
| `url`    | where to create a key, shown when one is missing                                           | none    |
| `sdk`    | a `[gem, requirement]` pair, offered for install like a [built-in's](PROVIDERS.md#sdk-gems) | none    |
| `chain`  | `true` when the SDK's own credential chain is always a valid way to authenticate, or a `Proc` returning whether it is configured right now; a configured chain [stands in for a required secret](CONFIGURATION.md#where-each-value-comes-from) | `false` |

Each field:

| Key        | Meaning                                                                          | Default |
| ---------- | -------------------------------------------------------------------------------- | ------- |
| `name`     | the key the value is read under                                                  | required |
| `env`      | one or more environment variable names, tried in order                           | required |
| `secret`   | `true` hides the input and stores the value in `auth.json`; `false` stores it in settings | `false` |
| `required` | only required fields are asked for                                               | `false` |
| `fallback` | a `Proc` tried after the environment and the stored value, before asking         | none    |

Without a `setup:`, the provider needs one required secret, `api_key`, read from `<IDENTIFIER>_API_KEY` — `ACME_API_KEY` for `:acme`.

## Reading the credentials

`Riffer::Rig.credentials(:acme)` returns the provider's resolved values as a hash, or `nil` before any are resolved. Read it when building the client, as above, rather than caching it: `/model` switches and `/auth` re-runs replace the values.
