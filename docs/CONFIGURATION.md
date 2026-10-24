# Configuration

Settings live in two files with the same name and shape, both optional:

- `~/.riffer/settings.json` — the home scope, for every project.
- `<cwd>/.riffer/settings.json` — the project scope, for sessions started in that directory.

A file that is missing or blank counts as empty. A file that is not valid JSON, or does not hold a JSON object, is never read as empty and never written over: `riffer` stops before the session starts, naming the file and the line and column where parsing stopped, and leaves the file's text out of the message.

## Where each value comes from

The highest source that is set wins.

| Value            | 1             | 2                                       | 3                  | 4                                     | 5                                  |
| ---------------- | ------------- | --------------------------------------- | ------------------ | ------------------------------------- | ---------------------------------- |
| Model            | `--model`     | a resumed session's `/model` switch[^1] | `RIFFER_MODEL`     | `model` in project, then home settings | asked on first run, saved to home[^2] |
| Reasoning level  | `--reasoning` | a resumed session's `/reasoning` switch | `RIFFER_REASONING` | `reasoning` in project, then home settings | the model's own default        |
| Provider credential[^3] | the provider's environment variables | `auth.json` (secrets) or the `providers` block (plain values) | a provider fallback, such as [Bedrock's region](PROVIDERS.md#amazon-bedrock) | asked for, then stored (required fields only) | — |

[^1]: Restored only when its provider still has credentials.
[^2]: Headless and ACP never ask: a missing model is a configuration error.
[^3]: Each field resolves on its own. A field with several variables tries them in the order [Providers](PROVIDERS.md) lists them, and a blank value counts as unset. A secret is asked for without echo. A required secret that resolves nowhere is neither asked for nor reported missing while the provider's SDK credential chain is configured, such as [Anthropic's](PROVIDERS.md#anthropic): the SDK authenticates instead. A secret that does resolve wins over the chain.

Inside a session, `/model` and `/reasoning` override all of these until the session ends ([below](#model)). A flag beats a resumed session's switch for that run only: resuming again without it restores the switch. [Providers](PROVIDERS.md) lists each provider's fields and variables.

## Scopes and merging

The project file wins over the home file key by key. A few keys merge differently:

| Key                     | Read from        | When both scopes set it                                                  |
| ----------------------- | ---------------- | ------------------------------------------------------------------------ |
| most core keys          | both             | the project's value wins                                                 |
| an extension namespace  | both             | merged one level down, so a project can change one key and keep the rest |
| `extensions.disabled`   | both             | the lists add up: a project can disable more, never re-enable            |
| `catalog_files`         | both             | the lists add up, home files first; a later file wins a repeated model   |
| `mcp.servers`           | both             | merged by server name; a project server replaces a home one whole        |
| `providers`             | home only        | —                                                                        |

## Core keys

Every core key is top level and optional. Every other top-level key is an [extension namespace](#extension-namespaces).

| Key             | What it sets |
| --------------- | ------------ |
| `model`         | the model new sessions start with, as `"provider/name"` ([below](#model)) |
| `reasoning`     | the reasoning effort ([below](#reasoning)) |
| `catalog_files` | the model catalog files holding pricing and reasoning maps ([below](#catalog_files)) |
| `providers`     | non-secret provider fields such as an endpoint or region ([Providers](PROVIDERS.md#the-providers-block-in-settings)) |
| `extensions`    | `disabled` and `autoload` ([below](#extensions)) |
| `reload`        | `"auto"` (default) or `"manual"` ([below](#reload)) |
| `sessions`      | `{"save": false}` stops saving sessions ([Sessions](SESSIONS.md#opting-out)) |
| `tools`         | the provider-native tool switches ([below](#toolsnative)) |

## `model`

```json
{ "model": "anthropic/claude-sonnet-4-6" }
```

The provider's identifier, a slash, then the provider's own model name. The provider is one of `anthropic`, `openai`, `gemini`, `openrouter`, `azure_openai` or `amazon_bedrock`, or one an [extension registers](CUSTOM_PROVIDERS.md). Everything after the first slash goes to the provider unchanged, so `openrouter/anthropic/claude-sonnet-4-6` works as written.

A name without a known provider prefix is rejected with the list of providers; riffer never guesses the provider from a bare name. A bare `RIFFER_MODEL` is rejected even when `--model` is also given.

`/model provider/name` switches the model for the current session, keeping the conversation. It sets up the new provider the way startup does — offering its [SDK gem](PROVIDERS.md#sdk-gems) and asking for missing credentials — and leaves the model unchanged if that fails. `/model` alone shows the model in use.

`/model --save` writes the model in effect to the home `settings.json`, so new sessions start with it; `/model provider/name --save` switches and saves in one step. A switch that fails saves nothing.

## `reasoning`

```json
{ "model": "anthropic/claude-sonnet-4-6", "reasoning": "high" }
```

One of `off`, `low`, `medium`, `high`, `xhigh` or `max`. riffer translates the level into each provider's own parameters, and a model's entry in a [catalog file](#catalog_files) can override that mapping. Leaving `reasoning` out keeps the model's default.

| Source                          | A level riffer does not accept…                                   |
| ------------------------------- | ----------------------------------------------------------------- |
| `--reasoning`, `RIFFER_REASONING` | is rejected before the session starts, listing the accepted levels |
| `settings.json`                 | is ignored, and the model's default applies                       |

Settings are lenient so that one level can stay in the file while you switch between providers.

`/reasoning level` switches the level for the current session and is restored when you resume it; `/reasoning` alone shows the level in effect (`default` when none is set). `/reasoning --save` and `/reasoning level --save` save to the home settings, as `/model` does. The level stays in effect across a `/model` switch. A custom provider with no mapping for the level fails the next request, naming the catalog file to add.

## `catalog_files`

```json
{ "catalog_files": ["~/.riffer/models.json", ".riffer/models.json"] }
```

The [model catalog](https://riffer.ai/guides/catalog/) files riffer reads for per-model pricing and reasoning mappings. A model without a catalog entry is unpriced, so riffer counts no cost for it ([how the terminal shows that](TERMINAL.md#the-status-line)). The file format is riffer's.

## `mcp`

The bundled `mcp` extension's namespace, declaring the MCP servers whose tools the model gets. [MCP](MCP.md) has the format.

## `extensions`

```json
{ "extensions": { "disabled": ["mcp", "bash"], "autoload": true } }
```

- `disabled` leaves out bundled extensions: any of `read`, `write`, `edit`, `bash`, `agents_md`, `skills` and `mcp`. Nothing a disabled extension would register exists.
- `autoload` (default `false`) loads every installed gem that ships `riffer/rig/extension` ([Gem extensions](EXTENSIONS.md#gem-extensions)).

[`--no-extensions`](CLI.md#flags) overrides `autoload` for one run.

## `tools.native`

```json
{ "tools": { "native": { "web_search": true } } }
```

Switches on [provider-native tools](TOOLS.md#provider-native-tools), per tool. They are off by default. A value can be an object instead of `true`, passed to the provider as the tool's options: `{"web_search": {"max_uses": 3}}`. A switch the current provider does not support does nothing.

## `reload`

```json
{ "reload": "manual" }
```

`"auto"` (the default) or `"manual"`; [Reloading](RELOADING.md#when-it-reloads) has when each one reloads.

## Extension namespaces

Every top-level key that is not a core key belongs to the extension of that name, holding the keys it declares with [`rig.setting`](EXTENSIONS.md#the-rigsetting-seam):

```json
{
  "model": "anthropic/claude-sonnet-4-6",
  "git": { "depth": 10 }
}
```

A key left out takes the extension's declared default. An extension cannot be named after a core key.
