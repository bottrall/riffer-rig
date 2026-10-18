# Configuration

Settings live in two files with the same name and shape, both optional:

- `~/.riffer/settings.json` — the home scope, for every project.
- `<cwd>/.riffer/settings.json` — the project scope, for sessions started in that directory.

`Riffer::Rig::Loader` reads home then project and merges them key by key, the project winning: a top-level key set in both takes the project's value, and an extension namespace merges the same way one level down, so a project can change one key of a namespace and keep the rest from home. Three keys merge differently: `extensions.disabled` and `catalog_files` lists add up across both scopes, and an [MCP server](MCP.md) declared in both is replaced whole by the project's. A file that is missing or blank counts as empty.

A file that is not valid JSON, or does not hold a JSON object, is never read as empty and never written over. The Loader raises `Riffer::Rig::Loader::ConfigurationError` naming the file and, for a parse error, the line and column where parsing stopped, so `riffer` stops before the session starts; fix the file and run it again. The file's text is left out of the message.

## Core keys

Every core key is top level and optional:

| Key             | What it sets |
| --------------- | ------------ |
| `model`         | the model new sessions start with, as `"provider/name"` ([below](#model)) |
| `reasoning`     | the reasoning effort, which riffer translates to the provider's own parameter ([below](#reasoning)) |
| `catalog_files` | the model catalog JSON files holding pricing and reasoning maps ([below](#catalog_files)) |
| `providers`     | non-secret provider fields such as an endpoint or region ([Providers](PROVIDERS.md#the-providers-block-in-settings); read from the home file only) |
| `extensions`    | `disabled`, the bundled extensions to leave out ([below](#extensions)); `autoload`, gem extension autoload ([below](#extensions)) |
| `reload`        | `"auto"` (default) or `"manual"`, the hot-reload trigger ([Reloading](RELOADING.md#triggers)) |
| `sessions`      | `save`, set it to `false` to stop saving sessions to the store ([Sessions](SESSIONS.md)) |
| `tools`      | the provider-native tool switches (`native`) ([below](#toolsnative)) |

## `model`

`model` is the model new sessions start with, as a `"provider/name"` string: the provider's identifier, a slash, then the provider's own model name.

```json
{ "model": "anthropic/claude-sonnet-4-6" }
```

The provider is one of `anthropic`, `openai`, `gemini`, `openrouter`, `azure_openai` or `amazon_bedrock` ([Providers](PROVIDERS.md) has each one's setup). Everything after the first slash is passed to the provider unchanged, so a name with slashes of its own works as written: `openrouter/anthropic/claude-sonnet-4-6`. A string without a provider prefix, or with a provider riffer does not know, is rejected with a hint listing the providers, never inferred from the bare name.

There is no built-in default. The model is the first of these that is set, highest first:

1. `model:` in the [`Loader::Options`](EMBEDDING.md#loader-options) given to `Loader.runtime` (the `--model` flag);
2. the `RIFFER_MODEL` environment variable, e.g. `RIFFER_MODEL=openai/gpt-5 riffer`;
3. `model` in the project settings, then in the home settings;
4. onboarding: the Loader asks the host for a model string, listing the providers, and writes the answer to `~/.riffer/settings.json`. A host that cannot ask (the null host, so headless and embedded use) declines, and the Loader raises `Riffer::Rig::Loader::ConfigurationError` instead.

A bare `RIFFER_MODEL` is rejected even when a higher source wins, since it is a mistake in the environment either way.

A `model` that is not a string is never skipped as unset: the Loader raises `Riffer::Rig::Loader::ConfigurationError` naming the file, even when a higher source wins, the same as for a file that does not parse.

`/model provider/name` overrides this key for the current session only: the override wins until the session ends. Switching resolves the new provider's missing credentials and missing SDK gem the same way startup does, and `/model --save` writes the model in effect to this key in the home settings, leaving every other key unchanged — or, when the home file no longer parses, writes nothing and reports the file ([Switching the model](https://github.com/bottrall/riffer-rig#switching-the-model)).

## `reasoning`

`reasoning` is the reasoning effort: `off`, `low`, `medium`, `high`, `xhigh` or `max`. Riffer translates the level into the provider's own request parameters: each provider maps it to its own shape (Anthropic's `thinking` and `output_config`, OpenAI's and OpenRouter's `reasoning`, Gemini's `thinkingConfig`, Bedrock's `additional_model_request_fields`), and an entry for the model in a [catalog file](#catalog_files) overrides the provider's default mapping. Which levels a provider accepts is the provider's business: a level it does not know reaches the provider as written. A level outside the six raises `Riffer::ArgumentError` when the session starts. Omitting `reasoning` leaves the model's default. Anthropic models also get prompt caching (`cache_control`) whatever the level.

```json
{ "model": "anthropic/claude-sonnet-4-6", "reasoning": "high" }
```

The level is the first of these that is set, highest first: the `--reasoning` flag, a resumed session's recorded `/reasoning` switch, the `RIFFER_REASONING` environment variable, then `reasoning` in the settings.

A level from `--reasoning` or `RIFFER_REASONING` that the selected model's provider does not accept — including any level for a provider that takes none, such as gemini — is rejected before the session starts with a `Riffer::Rig::Loader::ConfigurationError` naming the levels the provider accepts. A level from the settings is never rejected: an unrecognized one silently leaves the model's default, so a level every provider accepts can stay in the file across model switches.

`/reasoning level` switches the level for the current session only: `/reasoning` alone shows the level in effect, a level the current model's provider does not accept is refused with the levels it does, and `/reasoning --save` writes the level in effect to the home settings, leaving every other key unchanged — or, when the home file no longer parses, writes nothing and reports the file. A switch is recorded in the [session store](SESSIONS.md#resuming) and restored on resume; a `--reasoning` chosen for the run wins over the restored switch for that run only.

When the model switches mid-session — `/model` — the level is re-derived for the new provider: one it does not accept silently leaves the new model's default.

## `catalog_files`

`catalog_files` lists the [model catalog](https://github.com/bottrall/riffer/blob/main/docs/CATALOG.md) JSON files the Loader hands to riffer — per-model pricing and per-level reasoning mappings riffer cannot derive from the model name:

```json
{ "catalog_files": ["~/.riffer/models.json", ".riffer/models.json"] }
```

The lists of the two scopes add up, the home files loading before the project's, and a later file wins a repeated model key, so a project file can add models or override a price. The file format — `version`, `pricing`, per-level `reasoning` fragments and aliases — is riffer's, documented at the link above.

A model without an entry has no cost: it is shown as missing, never as zero. A value that is not an array of strings is ignored.

`catalog_files` replaces the `models` pricing table: move each entry into a catalog file's `pricing` — the same four rates, USD per million tokens — and point `catalog_files` at the file.

## `mcp`

`mcp` is the bundled `mcp` extension's namespace. `mcp.servers` declares the HTTPS MCP servers whose tools the model gets, keyed by server name — a `url` with optional `headers`:

```json
{
  "mcp": {
    "servers": {
      "docs": { "url": "https://docs.example.com/mcp" },
      "tracker": { "url": "https://tracker.example.com/mcp", "headers": { "Authorization": "Bearer <token>" } }
    }
  }
}
```

Keep a server with a secret header in `~/.riffer/settings.json` rather than a committed project file. [MCP](MCP.md) has the format, how a project server overrides a home one, and what happens on reload.

## `extensions`

`extensions.disabled` names bundled extensions the Loader leaves out — any of `read`, `write`, `edit`, `bash`, `agents_md`, `skills` and `mcp`:

```json
{ "extensions": { "disabled": ["mcp", "bash"] } }
```

The lists in the two scopes add up, so a project can disable more but cannot re-enable what home disabled. A disabled extension is simply not passed to the Runtime; nothing it would register exists. An embedder calling `Loader.runtime` can also strip `skills` and `agents_md` for one Runtime, with `skills: false` and `agents_md: false` in its [`Loader::Options`](EMBEDDING.md#loader-options).

`extensions.autoload` (default `false`) makes the Loader run `riffer/rig/extension` from every gem `Gem.find_files` finds, before the `rig.rb` files ([Gem extensions](EXTENSIONS.md#gem-extensions)). Set it in either scope; the project's value wins. `extensions: false` in the `Loader::Options` (the `--no-extensions` flag) skips both the autoload and the `rig.rb` files; the bundle still loads.

## `tools.native`

`tools.native` switches the provider-native tools on, per tool. They are off by default; a switch the current provider cannot honour does nothing and raises nothing ([Tools](TOOLS.md#provider-native-tools)):

```json
{ "tools": { "native": { "web_search": true } } }
```

A switch value can be an object, passed through to the provider as the tool's options. The Loader hands the switches to the Runtime at build, and a `/model` switch re-derives them for the new provider, so the tool is there exactly when the provider supports it.

## `reload`

`reload` picks the hot-reload trigger: `"auto"` (the default) reloads the `rig.rb` files, settings, credentials and trust automatically at every `before_request` boundary, `"manual"` drops that check and leaves [`/reload`](RELOADING.md#triggers) and [`Runtime#rebuild`](EMBEDDING.md#rebuilding-after-a-code-reload). The mode is read when the Runtime is built; an automatic session honours a later flip to `manual` at its next boundary, while a manual session picks up `auto` on the next build. The Loader keyword `reload: :manual` on `Loader.runtime` overrides the setting for one build ([Reloading](RELOADING.md#triggers)):

```json
{ "reload": "manual" }
```

## Extension namespaces

Core keys — `model`, `reasoning`, `catalog_files`, `reload`, `extensions`, `sessions`, `providers` and `tools` — stay at the top level. Every other top-level key is an extension's namespace, named after the extension, holding the keys that extension declares with [`rig.setting`](EXTENSIONS.md#the-rigsetting-seam); `mcp` is one of these, the bundled `mcp` extension's own namespace:

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
