# OpenAI

Model prefix `openai/`. Create a key at https://platform.openai.com/api-keys.

| Field      | Kind             | Environment variable | Stored in                                       |
| ---------- | ---------------- | -------------------- | ----------------------------------------------- |
| `api_key`  | required, secret | `OPENAI_API_KEY`     | `~/.riffer/auth.json`                           |
| `base_url` | optional         | `OPENAI_BASE_URL`    | `providers.openai` in `~/.riffer/settings.json` |

`base_url` points the client at an OpenAI-compatible endpoint. It is never asked for: set the environment variable or write it to settings.

```json
{ "providers": { "openai": { "base_url": "https://proxy.example.com/v1" } } }
```

[Providers](PROVIDERS.md) covers the resolution order and the `$VAR` and `!command` forms a stored key can take.
