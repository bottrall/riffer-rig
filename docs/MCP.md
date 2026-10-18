# MCP

riffer-rig can give the model the tools of [Model Context Protocol](https://modelcontextprotocol.io) servers reached over HTTPS.

## Declaring servers

The bundled `mcp` extension reads servers from `mcp.servers` in either [settings file](CONFIGURATION.md), keyed by name:

```json
{
  "mcp": {
    "servers": {
      "docs": { "url": "https://docs.example.com/mcp" },
      "tracker": {
        "url": "https://tracker.example.com/mcp",
        "headers": { "X-Team": "platform" }
      }
    }
  }
}
```

`url` is required and must be `https://`; `headers` are sent with every request. A server declared in both files takes the project's entry whole — its headers are not merged with the home entry's. An entry without a `url` stops the whole `mcp` extension from loading, and the session reports it.

## Secret headers

Keep tokens out of `settings.json`: declare an `auth` block naming the environment variables that hold each credential, and reference the fields from the headers as `${field}`:

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

Each field resolves like a [provider credential](PROVIDERS.md#resolution-order): the environment first (a field may list several variables, tried in order), then `~/.riffer/auth.json` under the server's name, then a prompt without echo, stored for next time. A `${field}` that names no declared field is an error.

Put a server with a literal secret header in your home settings rather than a project file, which is usually committed.

## Tool names

Each server's tools are listed when the session starts and named `<server>__<tool>`, with any character outside `a-z`, `A-Z`, `0-9`, `_` and `-` replaced by `_`: the `search` tool of the `docs` server is `docs__search`.

MCP tools are not filtered by `--tools`; to keep a server's tools from the model, don't declare the server.

## When a server fails

A server that cannot be used is reported, and the session runs without its tools:

| Problem                                         | Reported as                                                                                     |
| ----------------------------------------------- | ----------------------------------------------------------------------------------------------- |
| the URL is not `https://`, or listing tools fails | `MCP server NAME failed to register: …`                                                       |
| a credential can't be resolved and riffer can't ask (headless) | `MCP server NAME failed to register: MCP server NAME has no FIELD (ENV_VAR); set it in the environment or run riffer interactively to paste it` |
| a tool call fails on the server                  | a tool error the model sees                                                                    |

## Reloading

On a [reload](RELOADING.md), a server whose name, URL and headers are unchanged keeps its tools as listed; a changed server is listed again, and a removed one is dropped.

## Limits

- **HTTPS only.** Servers that run as a local command over stdio, and plain `http://` URLs, are not supported. An [ACP](ACP.md) client's stdio servers are reported as unsupported.
- **No session handshake.** Each request is sent on its own, without MCP's `initialize`, so a server that requires a session before `tools/list` can't be used.
- **One registry per process.** When [embedding](EMBEDDING.md) several Runtimes in one process, give their servers different names: a second Runtime declaring the same name takes it over from the first.

Extensions can declare servers in Ruby with [`rig.mcp`](EXTENSIONS.md#the-rigmcp-seam).
