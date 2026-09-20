# Anthropic

Model prefix `anthropic/`, for example `anthropic/claude-sonnet-4-6`. Create a key at https://console.anthropic.com/settings/keys.

| Field     | Kind             | Environment variable | Stored in             |
| --------- | ---------------- | -------------------- | --------------------- |
| `api_key` | required, secret | `ANTHROPIC_API_KEY`  | `~/.riffer/auth.json` |

```json
{ "anthropic": { "type": "api_key", "api_key": "sk-ant-…" } }
```

[Providers](PROVIDERS.md) covers the resolution order and the `$VAR` and `!command` forms a stored key can take.
