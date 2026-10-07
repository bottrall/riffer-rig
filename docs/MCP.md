# MCP

A Runtime can hand the model the tools of [Model Context Protocol](https://modelcontextprotocol.io) servers. A server is reached over HTTPS: the Runtime registers it with riffer's MCP client, which lists the server's tools over MCP's Streamable HTTP transport and calls them the same way, sending any headers you give it (an `Authorization` token, say) with every request. Servers that run as a local command over stdio are not supported, and neither are plain `http://` URLs.

## Declaring servers in settings

The bundled `mcp` extension (`Riffer::Rig.bundled(:mcp)`) declares every server under its own settings namespace, `mcp.servers`, keyed by the server's name:

```json
{
  "mcp": {
    "servers": {
      "docs": { "url": "https://docs.example.com/mcp" },
      "tracker": {
        "url": "https://tracker.example.com/mcp",
        "headers": { "Authorization": "Bearer <token>" }
      }
    }
  }
}
```

`url` is required and must be `https://`; `headers` is optional and defaults to none. An embedder passes the same shape in the Runtime's `settings:` hash, with symbol keys: `{ mcp: { servers: { docs: { url: 'https://docs.example.com/mcp' } } } }` (see [Embedding](EMBEDDING.md#constructing-a-runtime)). An entry without a `url` fails the whole `mcp` extension, which is reported as a load error (see [Extensions](EXTENSIONS.md#error-isolation)).

Put a server that needs a secret header in your home `~/.riffer/settings.json`, not the project's `.riffer/settings.json`, which is usually committed with the project — the same goes for its `auth` block ([Secret headers](#secret-headers)).

Settings come in two scopes, `~/.riffer/settings.json` then the project's `.riffer/settings.json`. `Riffer::Rig::Mcp.merge(home, project)` merges the two `mcp` hashes by server name: a server declared in only one scope is kept, and a project server replaces the home server of the same name whole — its `headers` are not merged with the home server's.

```ruby
Riffer::Rig::Mcp.merge(home_settings[:mcp] || {}, project_settings[:mcp] || {})
```

[`Loader.runtime`](EMBEDDING.md#building-a-runtime-with-the-loader) merges the two scopes this way and passes the bundled `mcp` extension unless `extensions.disabled` names it. The `riffer` terminal builds its Runtime this way, so servers declared in either settings file reach its model.

`mcp` is an ordinary extension name, not a core settings key: `mcp.servers` is simply the bundled extension's own namespace, the same as any other extension's. To run without it, leave it out of the Runtime's `extensions:`, or list it in `extensions.disabled` ([Configuration](CONFIGURATION.md#extensions)).

## Secret headers

A server that authenticates with a token need not put the token in `settings.json`. Declare an `auth` block with a field per credential — the field's value is one or more environment variable names — and reference the fields from the header values as `${field}`:

```json
{
  "mcp": {
    "servers": {
      "kagi": {
        "url": "https://mcp.kagi.com/mcp",
        "auth": { "api_key": "KAGI_API_KEY" },
        "headers": { "Authorization": "Bearer ${api_key}" }
      }
    }
  }
}
```

When the Runtime is built, each field resolves like a provider credential: the environment first, then the entry stored under the server's name in `~/.riffer/auth.json`, then a prompt — asked once with no echo and stored there for every run after. A field may name several environment variables, tried in order. Header values of a server without an `auth` block are sent exactly as written; with one, every `${field}` must name a declared field, and a reference to anything else fails the registration.

A credential that cannot be resolved — unset everywhere, with no stored entry and a host that cannot ask — is reported through `notify` at level `:error` as "MCP server NAME failed to register: MCP server NAME has no FIELD (ENV_VAR); set it in the environment or run riffer interactively to paste it", and the Runtime runs without that server's tools. A rebuild re-resolves the block, so a server whose resolved headers changed is registered again ([Reload and close](#reload-and-close)).

## Declaring servers from an extension

Any extension declares a server of its own with the `rig.mcp` seam; the bundled extension is only the settings-driven convention on top of it.

```ruby
Riffer::Rig.extension('tracker') do |rig|
  rig.mcp 'tracker', url: 'https://tracker.example.com/mcp', headers: { 'Authorization' => "Bearer #{ENV.fetch('TRACKER_TOKEN')}" }
end
```

`rig.mcp(name, url:, headers: {}, auth: {})` declares one server. An extension-declared server can carry an `auth` block and `${field}` header references of its own ([Secret headers](#secret-headers)). A stdio server is declared with `rig.mcp(name, command:, args: [], env: {})` instead — exactly one of `url` and `command`, never both; a declaration with neither raises `ArgumentError`. Server names are shared across extensions: a later declaration of the same name, from the same extension or a later one, replaces the earlier one, and a replacement across extensions is reported through `notify` at level `:info` as "Extension LATER replaces MCP server NAME from EARLIER".

An extension block can read its own settings namespace as `rig.settings` while it runs, with the defaults it declared with [`rig.setting`](EXTENSIONS.md#the-rigsetting-seam) filled in. That is how the bundled extension reads `mcp.servers`.

## Tool names

When the Runtime is built it registers each server with riffer, which lists the server's tools there and then; the agent gets them after the tools extensions registered. A tool is named with riffer's MCP naming, `<server>__<tool>`, each part with every character outside `a-z`, `A-Z`, `0-9`, `_` and `-` replaced by `_`: the `search` tool of the `docs` server is `docs__search`. Each tool keeps the server's description and input schema; the server validates the arguments. A tool call that fails on the server is a tool error the model sees.

The `tools:` allowlist does not apply to MCP tools: riffer adds them inside the agent, after the allowlist has filtered the extension tools, so a Runtime built with `tools: %w[read]` still gets every MCP tool. Leave a server out of the declarations to keep its tools from the model.

A server that cannot be registered — its URL is not `https://`, or listing its tools fails — is reported through `notify` at level `:error` as "MCP server NAME failed to register: …", and the Runtime runs without its tools.

riffer's client sends each request on its own, without MCP's `initialize` handshake, so a server that insists on a session before `tools/list` cannot be registered.

## Reload and close

On a [rebuild](EMBEDDING.md#rebuilding-after-a-code-reload), a server whose name, url and headers are unchanged is not registered again: its tools stay as they were listed. A server whose url or headers changed is registered again, which replaces its earlier registration and lists its tools afresh, and a server the new extension list no longer declares is unregistered.

`close` unregisters every server the Runtime registered.

## Servers in more than one Runtime

riffer keeps one MCP registry per process, keyed by server name. Each Runtime tags its registrations with its own `id`, so its agent sees only the servers it declared, even when other Runtimes in the process declare servers of their own.

Two Runtimes in one process must not declare servers of the same name: the later registration replaces the earlier one, so the first Runtime loses that server's tools. A Runtime never unregisters a server another Runtime has since registered under the same name.

## Servers over ACP

An [ACP](ACP.md) client supplies its own MCP servers with `session/new`, in stdio shape only: a command, its args and an env map. The agent declares each one through the `rig.mcp` seam, so it reaches the Runtime as if an extension named `acp` had declared it, keeps it through a reload rebuild, and can be replaced by a same-name declaration. A server in `http` or `sse` shape is skipped with one warning notify.

A stdio declaration still cannot be registered: riffer's MCP client speaks HTTPS only, so the Runtime reports "MCP server NAME runs over stdio, which riffer cannot register yet" through `notify` at level `:error` and runs without its tools.
