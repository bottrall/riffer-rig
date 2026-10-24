# Providers

riffer-rig talks to the provider named by the model's prefix: `anthropic/claude-sonnet-4-6` means Anthropic. Each provider needs its credentials and, for most, an SDK gem.

| Provider                            | Field       | Kind                                         | Environment variables              | Stored in                                               |
| ----------------------------------- | ----------- | -------------------------------------------- | ---------------------------------- | ------------------------------------------------------- |
| [`anthropic`](#anthropic)           | `api_key`   | required, secret, or [SDK chain](#anthropic) | `ANTHROPIC_API_KEY`                | `~/.riffer/auth.json`                                   |
| [`openai`](#openai)                 | `api_key`   | required, secret                             | `OPENAI_API_KEY`                   | `~/.riffer/auth.json`                                   |
|                                     | `base_url`  | optional                                     | `OPENAI_BASE_URL`                  | `providers.openai` in `~/.riffer/settings.json`         |
| [`gemini`](#gemini)                 | `api_key`   | required, secret                             | `GEMINI_API_KEY`                   | `~/.riffer/auth.json`                                   |
| [`openrouter`](#openrouter)         | `api_key`   | required, secret                             | `OPENROUTER_API_KEY`               | `~/.riffer/auth.json`                                   |
| [`azure_openai`](#azure-openai)     | `endpoint`  | required                                     | `AZURE_OPENAI_ENDPOINT`            | `providers.azure_openai` in `~/.riffer/settings.json`   |
|                                     | `api_key`   | required, secret                             | `AZURE_OPENAI_API_KEY`             | `~/.riffer/auth.json`                                   |
| [`amazon_bedrock`](#amazon-bedrock) | `region`    | required                                     | `AWS_REGION`, `AWS_DEFAULT_REGION` | `providers.amazon_bedrock` in `~/.riffer/settings.json` |
|                                     | `api_token` | optional, secret                             | `AWS_BEARER_TOKEN_BEDROCK`         | `~/.riffer/auth.json`                                   |

Each field resolves in the [order every value follows](CONFIGURATION.md#where-each-value-comes-from). Nothing validates a value: a bad key surfaces on the first request, with the provider's own error.

An extension can add a provider of its own ([Custom providers](CUSTOM_PROVIDERS.md)). A custom provider registered without a setup reads one secret, `<IDENTIFIER>_API_KEY`.

## SDK gems

Installing riffer-rig installs no provider SDK. Each provider's gem is loaded the first time you use the provider:

| Provider                                 | Gem                      | Version   |
| ---------------------------------------- | ------------------------ | --------- |
| `gemini`                                 | none needed              | —         |
| `anthropic`                              | `anthropic`              | `~> 1.69` |
| `openai`, `openrouter`, `azure_openai`   | `openai`                 | `~> 0.80` |
| `amazon_bedrock`                         | `aws-sdk-bedrockruntime` | `~> 1.0`  |

When the gem is missing:

| Where riffer runs              | What happens                                                                                   |
| ------------------------------ | ---------------------------------------------------------------------------------------------- |
| terminal, outside Bundler      | it asks `Install the anthropic gem now?`, and on yes installs and loads it without a restart    |
| under Bundler (`bundle exec`, a Rails app) | it refuses, printing the line to add: `gem 'anthropic', '~> 1.69'`                 |
| headless, or you answer no     | it stops with the `gem install anthropic -v '~> 1.69'` line to run (headless exits 2)          |

To skip the question, install the gem yourself or add it to your Gemfile ahead of time. `/model` runs the same check when you switch to a provider whose gem is missing.

## auth.json

`~/.riffer/auth.json` holds secret fields only, one typed entry per provider. It is written with permissions `600`, in a directory with `700`.

```json
{
  "anthropic": { "type": "api_key", "api_key": "sk-ant-…" },
  "amazon_bedrock": { "type": "api_key", "api_token": "…" }
}
```

`"type": "api_key"` is the only type; an entry of any other shape is ignored. A file that does not parse stops `riffer` the way a broken [settings file](CONFIGURATION.md) does, and its text never appears in the message, so a broken file never puts a key on screen.

### `$VAR` and `!command` values

A stored secret can name where to find the real one:

```json
{
  "anthropic": { "type": "api_key", "api_key": "$WORK_ANTHROPIC_KEY" },
  "openai": { "type": "api_key", "api_key": "!security find-generic-password -s openai -w" }
}
```

- `$NAME` reads the environment variable `NAME`.
- `!command` runs `command` through the shell and uses its stdout, stripped. This is how a keychain or password manager plugs in.

An unset variable, a failing command or empty output counts as unresolved, so resolution moves on. Only `auth.json` values expand; a value in `settings.json` is always literal, so a settings file never runs a command.

## The `providers` block in settings

Plain fields live in the home `settings.json`, keyed by provider and then by field:

```json
{
  "providers": {
    "azure_openai": { "endpoint": "https://my-resource.openai.azure.com" },
    "amazon_bedrock": { "region": "us-west-2" },
    "openai": { "base_url": "https://proxy.example.com/v1" }
  }
}
```

## /auth

| Command                    | Does                                                                                                                             |
| -------------------------- | -------------------------------------------------------------------------------------------------------------------------------- |
| `/auth`                    | lists every provider with where its secret comes from: `env`, `stored`, `chain` (no secret resolves, and the SDK's own credential chain is configured) or `missing` |
| `/auth <provider>`         | asks again for each required field that does not resolve and stores the answers — how you rotate a key; the session uses them from the next request |
| `/auth remove <provider>`  | deletes the provider's `auth.json` entry and its `providers` block; the running session keeps the credentials it already loaded |

## Provider notes

### Anthropic

Prefix `anthropic/`, for example `anthropic/claude-sonnet-4-6`. Create a key at <https://console.anthropic.com/settings/keys>. Anthropic models always get prompt caching.

Instead of an API key, the Anthropic SDK can authenticate through its own credential chain — workload identity federation, `ANTHROPIC_AUTH_TOKEN`, or an `ant auth login` profile — set up as the [Anthropic Ruby SDK](https://github.com/anthropics/anthropic-sdk-ruby) documents; riffer-rig stores nothing for it.

How the chain and an API key combine is part of the [resolution order](CONFIGURATION.md#where-each-value-comes-from). A selected profile that fails to load counts as configured, so the SDK's own error surfaces on the first request.

### OpenAI

Prefix `openai/`. Create a key at <https://platform.openai.com/api-keys>. Set `base_url` to point the client at an OpenAI-compatible endpoint.

### Gemini

Prefix `gemini/`. Create a key at <https://aistudio.google.com/app/apikey>.

### OpenRouter

Prefix `openrouter/`, followed by OpenRouter's own model id, for example `openrouter/z-ai/glm-5.3-flash`. Create a key at <https://openrouter.ai/keys>.

### Azure OpenAI

Prefix `azure_openai/`. The endpoint and key are on the resource's Keys and Endpoint page in the [Azure portal](https://portal.azure.com). Both are required: the endpoint is stored in [settings](#the-providers-block-in-settings) and the key in [`auth.json`](#authjson).

### Amazon Bedrock

Prefix `amazon_bedrock/`. Bedrock authenticates either through the AWS SDK's own credential chain (environment, shared credentials file, SSO, instance role), which stores nothing in riffer-rig, or with a Bedrock bearer token. The token is never asked for: set `AWS_BEARER_TOKEN_BEDROCK` or store it in `auth.json` as `api_token`. Without one, the credential chain is used and `/auth` reports `chain`. A region set nowhere else falls back to the active profile's region in `~/.aws/config`.
