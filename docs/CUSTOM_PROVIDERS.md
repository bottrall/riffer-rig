# Custom providers

An extension registers a provider class under a new prefix, and the Loader then treats it like a built-in: onboarding, `/model` hints and `/auth` list it, and its credentials resolve the same way. See [Providers](PROVIDERS.md) for how resolution and storage work.

## Registering a provider

```ruby
# .riffer/rig.rb
require 'acme_sdk'

class AcmeProvider < Riffer::Providers::Base
  # ... the provider hooks (see riffer's custom-provider guide)
end

Riffer::Rig.extension('acme') do |rig|
  rig.provider(:acme, setup: {
    url: 'https://acme.example.com/keys',
    fields: [{ name: :api_key, env: ['ACME_API_KEY'], secret: true, required: true }]
  }) { AcmeProvider }
end
```

`rig.provider(prefix, setup: nil) { klass }` is process-wide: it registers the class with riffer's provider repository (`Riffer::Providers::Repository.register`) the first time an extension runs it, and the registration never goes away. Re-registering the same prefix — a reload, or a second Runtime building the extension — replaces the entry with the same class and is idempotent. Providers are stateless, so the one repository and one set of credentials per process is by design.

## The setup

The `setup:` hash describes what rig needs before it can use the provider, the same way the built-in table does. Rig converts it to a frozen `Riffer::Rig::ProviderSetup` (with `ProviderSetup::Field` entries) when the extension registers and stores it, so `ProviderSetup.for(:acme)` returns it and the Loader resolves the provider like a built-in.

- `url` (optional) — where to create a key, shown in credential messages.
- `fields` — each field has `name` (the value's key), `env` (one or more env var names, tried in order), `secret` (hidden input, stored in `auth.json`; default false), `required` (only required fields are prompted; default false), and an optional `fallback:` Proc tried after env and disk, before prompting. The full field behaviour is in [Providers](PROVIDERS.md#resolution-order).
- `chain` (optional, default false) — offers the SDK's own credential chain.
- `sdk` (optional) — a `[gem, requirement]` pair the Loader or `/model` installs on demand, exactly like a built-in provider's.

Without a `setup:`, the generic fallback applies: one required secret `api_key` read from `<IDENTIFIER>_API_KEY` — for `:acme`, `ACME_API_KEY`.

## Reading the credentials

The provider class reads the resolved values through `Riffer::Rig.credentials(:acme)` when it builds its client:

```ruby
class AcmeProvider < Riffer::Providers::Base
  private

  def build_client
    AcmeSdk::Client.new(api_key: Riffer::Rig.credentials(:acme)[:api_key])
  end
end
```

`Riffer::Rig.credentials(identifier)` is a process-wide read of the values `Riffer::Rig::Credentials.apply` last received for that provider; it is nil before anything is applied. Built-in providers get the same lookup plus the assignment onto `Riffer.config`; a custom provider has no config member, so the process-wide read is its delivery path. Both stay current across `/model` switches and `/auth` re-runs, which re-apply the values.

A Loader-built Runtime resolves the provider's required fields at build time: it reads the env vars, the stored `auth.json` entry and the `providers` block of the home settings, prompts for what is still missing when the host can ask, and raises the configuration error naming the missing fields and their env vars otherwise — the same flow a built-in provider goes through.