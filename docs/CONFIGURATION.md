# Configuration

`~/.riffer/settings.json` holds optional user settings. Every key is optional; the [README](../README.md#configuration) lists them all.

## `model`

`model` is the model new sessions start with, as a `"provider/name"` string: the provider's identifier, a slash, then the provider's own model name.

```json
{ "model": "anthropic/claude-sonnet-4-6" }
```

The provider is one of `anthropic`, `openai`, `gemini`, `openrouter`, `azure_openai` or `amazon_bedrock` ([Providers](PROVIDERS.md) has each one's setup). Everything after the first slash is passed to the provider unchanged, so a name with slashes of its own works as written: `openrouter/anthropic/claude-sonnet-4-6`. A string without a provider prefix is rejected, never inferred from the bare name; `/model` answers one with a hint listing the providers.

`/model provider/name` overrides this key for the current session only: the override wins until the session ends, and `settings.json` is left unchanged ([Switching the model](../README.md#switching-the-model)).

## `models`

`models` prices each model, keyed by its `"provider/name"` string. Rates are USD per million tokens:

```json
{
  "models": {
    "anthropic/claude-sonnet-4-6": {
      "input": 3.0,
      "output": 15.0,
      "cache_write": 3.75,
      "cache_read": 0.3
    }
  }
}
```

| Key           | Prices                                   | When absent |
| ------------- | ---------------------------------------- | ----------- |
| `input`       | input tokens not read from or written to the cache | `0` |
| `output`      | output tokens, reasoning included        | `0`         |
| `cache_write` | input tokens written to the prompt cache | `0`         |
| `cache_read`  | input tokens read from the prompt cache  | `0`         |

Each entry becomes a `Riffer::Rig::Settings::Pricing` and reaches the Runtime through its `pricing:` keyword, which registers it into riffer's `Riffer.config.pricing` so every turn and the running total carry a cost (see [Embedding](EMBEDDING.md#token-tally-and-cost)).

A model without an entry has no cost: it is shown as missing, never as zero. An entry that is not an object is ignored.

## Extension namespaces

Core keys — `model`, `reasoning`, `models`, `reload`, `extensions`, `sessions`, `providers`, `mcp` and `tools` — stay at the top level. Every other top-level key is an extension's namespace, named after the extension, holding the keys that extension declares with [`rig.setting`](EXTENSIONS.md#the-rigsetting-seam):

```json
{
  "model": "anthropic/claude-sonnet-4-6",
  "git": {
    "depth": 10
  }
}
```

A key left out takes the default the extension declared. An extension cannot be named after a core key; one that is fails to load and is reported.

An embedder passes the same shape as the Runtime's `settings:` hash, with symbol keys — `{ model: '…', git: { depth: 10 } }` (see [Embedding](EMBEDDING.md#constructing-a-runtime)).
