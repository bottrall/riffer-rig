# Gemini

Model prefix `gemini/`. Create a key at https://aistudio.google.com/app/apikey.

| Field     | Kind             | Environment variable | Stored in             |
| --------- | ---------------- | -------------------- | --------------------- |
| `api_key` | required, secret | `GEMINI_API_KEY`     | `~/.riffer/auth.json` |

```json
{ "gemini": { "type": "api_key", "api_key": "…" } }
```

[Providers](PROVIDERS.md) covers the resolution order and the `$VAR` and `!command` forms a stored key can take.
