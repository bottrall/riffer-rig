# ACP

`riffer acp` serves the same Runtimes the REPL drives as an [Agent Client Protocol](https://agentclientprotocol.com) (ACP) agent over stdio, so editors and other ACP clients can run riffer without a terminal. The wire layer is the [`acp-sdk`](https://github.com/bottrall/acp-sdk) gem; the agent is `Riffer::Rig::ACP` (`lib/riffer/rig/acp.rb`) and its host object is `Riffer::Rig::ACP::Host` (`lib/riffer/rig/acp/host.rb`).

## Registering with an editor

An editor registers the agent as the command `riffer acp`. In [Zed](https://zed.dev)'s `settings.json`:

```json
{
  "agent": {
    "version": "1",
    "profiles": {
      "riffer": {
        "name": "Riffer",
        "command": "riffer",
        "args": ["acp"]
      }
    }
  }
}
```

Everything loads exactly as the REPL does — settings from both scopes, credentials, `rig.rb` files (once trusted), skills — because each session builds its Runtime through the [Loader](EMBEDDING.md#building-a-runtime-with-the-loader) at the `cwd` the client sends in `session/new`. The model comes from the same [resolution order](PROVIDERS.md#resolution-order) as everywhere else: `RIFFER_MODEL`, then settings. The host cannot ask, so a session whose model or credentials are missing is refused: `session/new` fails with the reason, and nothing is built.

## What the agent supports

- `session/new` builds a Runtime and answers with the Runtime's UUID as the `sessionId`. Each session is independent; a `session/cancel` during a turn reaches [`Runtime#cancel`](EMBEDDING.md#cancelling-a-turn) from the transport's reader thread, and the running turn ends with `stopReason: cancelled`.
- `session/prompt` streams text as `agent_message_chunk` updates and reports each tool call as a `tool_call` update once its arguments are complete. Prompt blocks arrive as text and resource links; a resource link is included as its name and URI. A completed turn answers `end_turn`, a step cap `max_turn_requests`, and a turn that stopped for tokens, the context window or a blocked output `max_tokens`.
- `available_commands_update` lists the Runtime's commands — `/reload`, `/auth`, `/model` and every skill — right after `session/new`.
- Notify lines ([Extensions](EXTENSIONS.md#error-isolation)) reach the client as `agent_message_chunk` updates. Load-time ones flush right after the `session/new` reply.
- Tool calls always run: the agent never sends `session/request_permission`, so no tool call waits on the client.
- MCP servers the client sends on `session/new` in stdio shape are declared to the Runtime through the [`rig.mcp` seam](MCP.md#declaring-servers-from-an-extension) as if an extension had declared them, so a reload rebuild keeps them and a same-name declaration replaces them. See [MCP](MCP.md#servers-over-acp) for the stdio limit.

## What it skips

- `session/load`, `session/list` and the other session-lifecycle methods: the agent does not advertise `loadSession`, and `session/resume`, `session/close`, `session/delete` and `authenticate` are not offered. [Sessions](SESSIONS.md) are still recorded to the store for the terminal to resume.
- MCP servers in `http` or `sse` shape are skipped with a warning; only the stdio shape is read.
- Terminal delegation (`terminal/*`) and file delegation (`fs/*`) to the client are never requested, and neither is elicitation.
- Prompt blocks of other kinds than text and resource links are not advertised in `promptCapabilities`, so a compliant client does not send them.

A project `rig.rb` loads over ACP only once a terminal session has trusted it: the host declines `confirm`, so an untrusted file is stored as not trusted and never asked about again.