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

`url` is required and must be `https://`; `headers` are sent with every request. [Scopes and merging](CONFIGURATION.md#scopes-and-merging) covers a server declared in both files. An entry without a `url` stops the whole `mcp` extension from loading, and the session reports it.

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

Each field resolves like a [provider credential](CONFIGURATION.md#where-each-value-comes-from), and is stored in `~/.riffer/auth.json` under the server's name. A field may list several variables, tried in order. A `${field}` that names no declared field is an error.

Put a server with a literal secret header in your home settings rather than a project file, which is usually committed.

## Tool names

Each server's tools are listed when the session starts and named `<server>__<tool>`, with any character outside `a-z`, `A-Z`, `0-9`, `_` and `-` replaced by `_`: the `search` tool of the `docs` server is `docs__search`.

To keep a server's tools from the model, don't declare the server: the [`--tools` allowlist](TOOLS.md#identifiers) doesn't apply to them.

## When a server fails

A server whose URL isn't `https://`, whose tools can't be listed, or whose credential can't be resolved when riffer can't ask (headless) is [reported](TROUBLESHOOTING.md), and the session runs without its tools. A tool call that fails on the server comes back to the model as a tool error.

## Reloading

On a [reload](RELOADING.md), a server whose name, URL and headers are unchanged keeps its tools as listed; a changed server is listed again, and a removed one is dropped.

## Limits

- **HTTPS only.** Servers that run as a local command over stdio, and plain `http://` URLs, are not supported. An [ACP](ACP.md) client's stdio servers are reported as unsupported.
- **No session handshake.** Each request is sent on its own, without MCP's `initialize`, so a server that requires a session before `tools/list` can't be used.
- **One registry per process.** When [embedding](EMBEDDING.md) several Runtimes in one process, give their servers different names: a second Runtime declaring the same name takes it over from the first.

Extensions can declare servers in Ruby with [`rig.mcp`](EXTENSIONS.md#the-rigmcp-seam).
