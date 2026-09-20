# Amazon Bedrock

Model prefix `amazon_bedrock/`. Bedrock authenticates in one of two ways: the AWS SDK's own credential chain (environment, shared credentials file, SSO, instance role), which stores nothing in `riffer-rig`, or a Bedrock bearer token. Bedrock needs the `aws-sdk-bedrockruntime` gem, which `riffer-rig` does not install: `gem install aws-sdk-bedrockruntime`.

| Field       | Kind             | Environment variables              | Stored in                                               |
| ----------- | ---------------- | ---------------------------------- | ------------------------------------------------------- |
| `region`    | required         | `AWS_REGION`, `AWS_DEFAULT_REGION` | `providers.amazon_bedrock` in `~/.riffer/settings.json` |
| `api_token` | optional, secret | `AWS_BEARER_TOKEN_BEDROCK`         | `~/.riffer/auth.json`                                   |

`region` also falls back to the region of the active profile in the AWS shared config (`~/.aws/config`), read through the AWS SDK when it is installed, so it is asked for only when the environment, settings and the shared config all come up empty.

`api_token` is never asked for. With no token, the SDK's credential chain is used and `Riffer::Rig::Credentials.status(:amazon_bedrock)` reports `:chain`. To use a bearer token, set `AWS_BEARER_TOKEN_BEDROCK` or store it:

```json
{ "amazon_bedrock": { "type": "api_key", "api_token": "…" } }
```

[Providers](PROVIDERS.md) covers the resolution order and the `$VAR` and `!command` forms a stored token can take.
