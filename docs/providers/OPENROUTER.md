# OpenRouter

Model prefix `openrouter/`, followed by OpenRouter's own model id, for example `openrouter/z-ai/glm-5.3-flash`. Create a key at https://openrouter.ai/keys.

| Field     | Kind             | Environment variable | Stored in             |
| --------- | ---------------- | -------------------- | --------------------- |
| `api_key` | required, secret | `OPENROUTER_API_KEY` | `~/.riffer/auth.json` |

```json
{ "openrouter": { "type": "api_key", "api_key": "sk-or-…" } }
```

[Providers](PROVIDERS.md) covers the resolution order and the `$VAR` and `!command` forms a stored key can take.
