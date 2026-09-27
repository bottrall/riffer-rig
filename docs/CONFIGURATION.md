# Configuration

`~/.riffer/settings.json` holds optional user settings. Every key is optional; the [README](../README.md#configuration) lists them all.

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

Each entry becomes a `Riffer::Rig::Settings::Pricing` and reaches the Runtime through its `pricing:` keyword, which prices every turn and keeps the session's running total (see [Embedding](EMBEDDING.md#token-tally-and-cost)).

A model without an entry has no cost: it is shown as missing, never as zero. An entry that is not an object is ignored.
