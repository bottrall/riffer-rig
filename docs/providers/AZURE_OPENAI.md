# Azure OpenAI

Model prefix `azure_openai/`. The endpoint and key are on the resource's Keys and Endpoint page in the Azure portal, https://portal.azure.com.

| Field      | Kind             | Environment variable    | Stored in                                             |
| ---------- | ---------------- | ----------------------- | ----------------------------------------------------- |
| `endpoint` | required         | `AZURE_OPENAI_ENDPOINT` | `providers.azure_openai` in `~/.riffer/settings.json` |
| `api_key`  | required, secret | `AZURE_OPENAI_API_KEY`  | `~/.riffer/auth.json`                                 |

Both fields are required, so both are asked for when unresolved. The endpoint goes to settings and the key to `auth.json`:

```json
{ "providers": { "azure_openai": { "endpoint": "https://my-resource.openai.azure.com" } } }
```

```json
{ "azure_openai": { "type": "api_key", "api_key": "…" } }
```

[Providers](PROVIDERS.md) covers the resolution order and the `$VAR` and `!command` forms a stored key can take.
