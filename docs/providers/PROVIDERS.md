# Providers

`riffer-rig` talks to the provider named by the model's prefix: `anthropic/claude-sonnet-4-6` means Anthropic. Each provider has a recipe, a data-only entry in `Riffer::Rig::Recipes` listing the fields that provider needs. A field is either a secret (an API key or token) or a plain value (an endpoint, a region, a base URL), and is either required or optional.

| Provider         | Fields                                                  | Guide                               |
| ---------------- | ------------------------------------------------------- | ----------------------------------- |
| `anthropic`      | secret `api_key`                                        | [Anthropic](ANTHROPIC.md)           |
| `openai`         | secret `api_key`; optional `base_url`                   | [OpenAI](OPENAI.md)                 |
| `gemini`         | secret `api_key`                                        | [Gemini](GEMINI.md)                 |
| `openrouter`     | secret `api_key`                                        | [OpenRouter](OPENROUTER.md)         |
| `azure_openai`   | `endpoint`; secret `api_key`                            | [Azure OpenAI](AZURE_OPENAI.md)     |
| `amazon_bedrock` | `region`; optional secret `api_token`; credential chain | [Amazon Bedrock](AMAZON_BEDROCK.md) |

A provider without a recipe gets the generic one: a single required secret `api_key` read from `<IDENTIFIER>_API_KEY`, so `acme` reads `ACME_API_KEY`.

## Resolution order

Every field resolves on its own, and the first hit wins:

1. **Environment variable.** The field's env vars, in the order its provider page lists them. A blank value counts as unset.
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

`resolve` asks through the host's `ask` (see [Hosts](../HOSTS.md)) and stores what the host answers. A host that declines, as `Riffer::Rig::Hosts::Null` does, leaves `missing` listing the required fields that did not resolve, next to the values that did. A `!command` runs on every `resolve`, so resolve once and keep the result.

`apply` touches only the members it was given a value for, and does nothing for a provider `Riffer.config` has no section for.

`status` reports where a provider's secret comes from: `:env` when one of its env vars is set, `:stored` when `auth.json` has it, `:chain` when neither holds and the recipe offers the SDK's own credential chain, otherwise `:missing`. It reads no plain fields and runs no command.

`resolve`, `store` and `remove` take `auth_path:` and `settings_path:` to point at other files, and `status` takes `auth_path:`. `resolve` and `status` take `env:` in place of `ENV`; `resolve`, `store` and `status` take `recipe:` in place of the `Riffer::Rig::Recipes.for(identifier)` lookup; `apply` takes `config:` in place of `Riffer.config`.

## Recipes

`Riffer::Rig::Recipes[identifier]` returns a built-in recipe or `nil`; `Riffer::Rig::Recipes.for(identifier)` returns the generic recipe instead of `nil`. A recipe is a hash:

```ruby
{
  url: "https://console.aws.amazon.com/bedrock",
  chain: true,
  fields: [
    { name: :region, env: %w[AWS_REGION AWS_DEFAULT_REGION], secret: false, required: true, fallback: -> { … } },
    { name: :api_token, env: ["AWS_BEARER_TOKEN_BEDROCK"], secret: true, required: false }
  ]
}
```

| Key              | Meaning                                                                                   |
| ---------------- | ----------------------------------------------------------------------------------------- |
| `url`            | where to create the credential; optional                                                  |
| `chain`          | `true` when the SDK's own credential chain is a valid way to authenticate; optional       |
| `fields`         | the list of fields                                                                        |
| field `name`     | the member of `Riffer.config.<provider>` that receives the value                          |
| field `env`      | the env var names, tried in order                                                         |
| field `secret`   | `true` hides the input and stores the value in `auth.json`; `false` stores it in settings |
| field `required` | only required fields are asked for                                                        |
| field `fallback` | a callable tried after the environment and the files, before asking; optional             |
