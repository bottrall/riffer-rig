# Providers

`riffer-rig` talks to the provider named by the model's prefix: `anthropic/claude-sonnet-4-6` means Anthropic. Each provider has a setup entry in `Riffer::Rig::ProviderSetup`, a data-only record of what `riffer-rig` needs before it can use that provider: where to create a credential, whether the SDK's own credential chain will do, and the fields to resolve. A field is either a secret (an API key or token) or a plain value (an endpoint, a region, a base URL), and is either required or optional.

| Provider                            | Field       | Kind             | Environment variables              | Stored in                                               |
| ----------------------------------- | ----------- | ---------------- | ---------------------------------- | ------------------------------------------------------- |
| [`anthropic`](#anthropic)           | `api_key`   | required, secret | `ANTHROPIC_API_KEY`                | `~/.riffer/auth.json`                                   |
| [`openai`](#openai)                 | `api_key`   | required, secret | `OPENAI_API_KEY`                   | `~/.riffer/auth.json`                                   |
|                                     | `base_url`  | optional         | `OPENAI_BASE_URL`                  | `providers.openai` in `~/.riffer/settings.json`         |
| [`gemini`](#gemini)                 | `api_key`   | required, secret | `GEMINI_API_KEY`                   | `~/.riffer/auth.json`                                   |
| [`openrouter`](#openrouter)         | `api_key`   | required, secret | `OPENROUTER_API_KEY`               | `~/.riffer/auth.json`                                   |
| [`azure_openai`](#azure-openai)     | `endpoint`  | required         | `AZURE_OPENAI_ENDPOINT`            | `providers.azure_openai` in `~/.riffer/settings.json`   |
|                                     | `api_key`   | required, secret | `AZURE_OPENAI_API_KEY`             | `~/.riffer/auth.json`                                   |
| [`amazon_bedrock`](#amazon-bedrock) | `region`    | required         | `AWS_REGION`, `AWS_DEFAULT_REGION` | `providers.amazon_bedrock` in `~/.riffer/settings.json` |
|                                     | `api_token` | optional, secret | `AWS_BEARER_TOKEN_BEDROCK`         | `~/.riffer/auth.json`                                   |

A provider without a setup entry gets the generic one: a single required secret `api_key` read from `<IDENTIFIER>_API_KEY`, so `acme` reads `ACME_API_KEY`.

This guide covers credentials only. Installing a provider's SDK gem, model options, streaming and tool calling are covered by riffer's own provider guides, one per provider, starting from its [Providers overview](https://riffer.ai/guides/providers/overview/).

## Resolution order

Every field resolves on its own, and the first hit wins:

1. **Environment variable.** The field's env vars, in the order the table above lists them. A blank value counts as unset.
2. **Stored value.** A secret comes from `~/.riffer/auth.json`; a plain value comes from the `providers` block in `~/.riffer/settings.json`.
3. **Fallback.** A few fields can find their value elsewhere on the machine. The Bedrock region falls back to the AWS shared config.
4. **Ask.** A required field that is still unresolved is asked for, with hidden input for a secret, and the answer is stored. Optional fields are never asked for.

The environment wins over the files, the same way the environment wins over settings everywhere else in `riffer-rig`.

Nothing validates a value. A pasted key is saved as it is, and a bad key surfaces on the first request with the provider's own error.

## auth.json

`~/.riffer/auth.json` holds secret fields only, one typed entry per provider. The file is written with permissions `600` and its directory with `700`.

```json
{
  "anthropic": { "type": "api_key", "api_key": "sk-ant-…" },
  "amazon_bedrock": { "type": "api_key", "api_token": "…" }
}
```

`"type": "api_key"` is the only type. An entry of any other shape is ignored, including the flat `{"anthropic": "sk-…"}` entries earlier versions wrote: paste the key again when prompted, or rewrite the entry in the typed shape.

### `$VAR` and `!command` values

A secret in `auth.json` is a literal, a reference to an environment variable, or a shell command whose stdout is the secret:

```json
{
  "anthropic": { "type": "api_key", "api_key": "$WORK_ANTHROPIC_KEY" },
  "openai": { "type": "api_key", "api_key": "!security find-generic-password -s openai -w" }
}
```

- `$NAME` reads the environment variable `NAME`.
- `!command` runs `command` through the shell and uses its stdout, stripped. This is how a keychain or password manager plugs in: `riffer-rig` has no keychain code of its own.

An unset variable, a command that exits non-zero and empty output all count as unresolved, so resolution moves on to the fallback and then asks. Only `auth.json` values expand. A value in `settings.json` is always a literal, so a settings file never runs a command.

## The `providers` block in settings

Plain fields live in `~/.riffer/settings.json` under `providers`, keyed by provider and then by field:

```json
{
  "providers": {
    "azure_openai": { "endpoint": "https://my-resource.openai.azure.com" },
    "amazon_bedrock": { "region": "us-west-2" },
    "openai": { "base_url": "https://proxy.example.com/v1" }
  }
}
```

## Provider notes

### Anthropic

Model prefix `anthropic/`, for example `anthropic/claude-sonnet-4-6`. Create a key at https://console.anthropic.com/settings/keys.

### OpenAI

Model prefix `openai/`. Create a key at https://platform.openai.com/api-keys. `base_url` points the client at an OpenAI-compatible endpoint.

### Gemini

Model prefix `gemini/`. Create a key at https://aistudio.google.com/app/apikey.

### OpenRouter

Model prefix `openrouter/`, followed by OpenRouter's own model id, for example `openrouter/z-ai/glm-5.3-flash`. Create a key at https://openrouter.ai/keys.

### Azure OpenAI

Model prefix `azure_openai/`. The endpoint and key are on the resource's Keys and Endpoint page in the Azure portal, https://portal.azure.com.

Both fields are required, so both are asked for when unresolved. The endpoint goes to [settings](#the-providers-block-in-settings) and the key to [`auth.json`](#authjson):

```json
{ "providers": { "azure_openai": { "endpoint": "https://my-resource.openai.azure.com" } } }
```

```json
{ "azure_openai": { "type": "api_key", "api_key": "…" } }
```

### Amazon Bedrock

Model prefix `amazon_bedrock/`. Bedrock authenticates in one of two ways: the AWS SDK's own credential chain (environment, shared credentials file, SSO, instance role), which stores nothing in `riffer-rig`, or a Bedrock bearer token. Bedrock needs the `aws-sdk-bedrockruntime` gem, which `riffer-rig` does not install: `gem install aws-sdk-bedrockruntime`.

`region` falls back to the region of the active profile in the AWS shared config (`~/.aws/config`), read through the AWS SDK when it is installed, so it is asked for only when the environment, settings and the shared config all come up empty.

`api_token` is never asked for. With no token, the SDK's credential chain is used and `Riffer::Rig::Credentials.status(:amazon_bedrock)` reports `:chain`. To use a bearer token, set `AWS_BEARER_TOKEN_BEDROCK` or store it:

```json
{ "amazon_bedrock": { "type": "api_key", "api_token": "…" } }
```

## Riffer::Rig::Credentials

The module behind all of the above, for a host or an embedder:

| Method                       | Does                                                                          |
| ---------------------------- | ----------------------------------------------------------------------------- |
| `resolve(identifier, host:)` | resolves every field in the order above and returns a `Resolution`            |
| `apply(identifier, values)`  | assigns each value to the `Riffer.config.<provider>` member its field names   |
| `store(identifier, values)`  | writes secret fields to `auth.json` and plain fields to the `providers` block |
| `remove(identifier)`         | deletes the provider's `auth.json` entry and its `providers` block            |
| `status(identifier)`         | `:env`, `:stored`, `:chain` or `:missing`                                     |

```ruby
resolution = Riffer::Rig::Credentials.resolve(:azure_openai, host: host)
resolution.values  # => { endpoint: "https://…", api_key: "…" }
resolution.missing # => []

Riffer::Rig::Credentials.apply(:azure_openai, resolution.values)
```

`resolve` asks through the host's `ask` (see [Hosts](HOSTS.md)) and stores what the host answers. A host that declines, as `Riffer::Rig::Hosts::Null` does, leaves `missing` listing the required fields that did not resolve, next to the values that did. A `!command` runs on every `resolve`, so resolve once and keep the result.

`apply` touches only the members it was given a value for, and does nothing for a provider `Riffer.config` has no section for.

`status` reports where a provider's secret comes from: `:env` when one of its env vars is set, `:stored` when `auth.json` has it, `:chain` when neither holds and the setup entry offers the SDK's own credential chain, otherwise `:missing`. It reads no plain fields and runs no command.

`resolve`, `store` and `remove` take `auth_path:` and `settings_path:` to point at other files, and `status` takes `auth_path:`. `resolve` and `status` take `env:`, a `Riffer::Rig::Env`; `resolve`, `store` and `status` take `setup:` in place of the `Riffer::Rig::ProviderSetup.for(identifier)` lookup; `apply` takes `config:` in place of `Riffer.config`.

A `Riffer::Rig::Env` is a frozen snapshot of the process environment, and `riffer-rig` reads the process environment nowhere else. `Riffer::Rig::Env.new` snapshots the real one; `Riffer::Rig::Env.new('ANTHROPIC_API_KEY' => '…')` builds one from a hash, for an embedder or a test.

## Riffer::Rig::ProviderSetup

`Riffer::Rig::ProviderSetup[identifier]` returns a built-in setup entry or `nil`; `Riffer::Rig::ProviderSetup.for(identifier)` returns the generic entry instead of `nil`. A setup entry is a frozen `Riffer::Rig::ProviderSetup` holding a frozen list of `Riffer::Rig::ProviderSetup::Field`s.

| `ProviderSetup` reader | Meaning                                                                                     |
| ---------------------- | ------------------------------------------------------------------------------------------- |
| `url`                  | where to create the credential, or `nil`                                                    |
| `chain`                | `true` when the SDK's own credential chain is a valid way to authenticate; `false` if unset |
| `fields`               | the list of `Field`s                                                                        |

| `Field` reader | Meaning                                                                                   |
| -------------- | ----------------------------------------------------------------------------------------- |
| `name`         | the member of `Riffer.config.<provider>` that receives the value                          |
| `env`          | the env var names, tried in order                                                         |
| `secret`       | `true` hides the input and stores the value in `auth.json`; `false` stores it in settings |
| `required`     | only required fields are asked for                                                        |
| `fallback`     | a callable tried after the environment and the files, before asking, or `nil`             |

`Credentials.resolve`, `store` and `status` take a setup entry as `setup:`. Build one with the same keywords as the readers; `url:`, `chain:` and `fallback:` are optional:

```ruby
setup = Riffer::Rig::ProviderSetup.new(
  url: "https://acme.example/keys",
  fields: [
    Riffer::Rig::ProviderSetup::Field.new(name: :api_key, env: ["ACME_API_KEY"], secret: true, required: true),
    Riffer::Rig::ProviderSetup::Field.new(
      name: :region, env: ["ACME_REGION"], secret: false, required: true, fallback: -> { "us-east-1" }
    )
  ]
)

Riffer::Rig::Credentials.resolve(:acme, host: host, setup: setup)
```
