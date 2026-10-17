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

Everything loads exactly as the REPL does — settings from both scopes, credentials, `rig.rb` files (once trusted), skills — because each session builds its Runtime through the [Loader](EMBEDDING.md#building-a-runtime-with-the-loader) at the `cwd` the client sends in `session/new`. The model comes from the same [resolution order](PROVIDERS.md#resolution-order) as everywhere else: `RIFFER_MODEL`, then settings. The host cannot ask while a session builds, so a session whose model or credentials are missing is refused: `session/new` or `session/load` fails with the reason, and nothing is built.

## What the agent supports

- `session/new` builds a Runtime and answers with the Runtime's UUID as the `sessionId`. Each session is independent; a `session/cancel` during a turn reaches [`Runtime#cancel`](EMBEDDING.md#cancelling-a-turn) from the transport's reader thread, and the running turn ends with `stopReason: cancelled`.
- `session/prompt` streams text as `agent_message_chunk` updates and reports each tool call as a `tool_call` update, in progress, once its arguments are complete, then a `tool_call_update` for the same `toolCallId` when the call finishes: `completed`, or `failed` when its result is an error — a call an extension blocked or whose arguments did not parse included. The update carries the status and the result's text as its content; it is the stream's [`after_tool_call`](EMBEDDING.md#tool-call-events), and `before_tool_call` has no update of its own. A delivered [job exit notification](EMBEDDING.md#exit-notifications) arrives as a blank-line `agent_message_chunk`, so the replies either side of it stay apart. Prompt blocks arrive as text and resource links; a resource link is included as its name and URI. A completed turn answers `end_turn`, a step cap `max_turn_requests`, and a turn that stopped for tokens, the context window or a blocked output `max_tokens`. A turn that raises — a provider failure or a network failure — answers with an internal error whose message is the one the terminal and headless print, the provider's own explanation included, and the session takes the next `session/prompt` as usual.
- `available_commands_update` lists the Runtime's commands — `/reload`, `/trace`, `/auth`, `/model`, `/cost` and every skill — right after `session/new`, during `session/load` once the stored messages have replayed, and again before a `session/prompt` answers when a [reload](RELOADING.md) during it changed them.
- A `session/prompt` whose text starts with `/` followed by a name runs that [command](EMBEDDING.md#commands) instead of prompting the model: the name runs up to the first whitespace and the rest of the text is its arguments. The command's output streams as `agent_message_chunk` updates, a turn it starts streams as any other, and an unknown name is answered with `Unknown command: <name>`. A command that starts no turn answers `end_turn`.
- Notify lines ([Extensions](EXTENSIONS.md#error-isolation)) reach the client as `agent_message_chunk` updates, each a paragraph of its own so it stays apart from the next notify and from the reply. Load-time ones flush right after the `session/new` reply.
- A [background job](EMBEDDING.md#background-jobs) that exits while no `session/prompt` is in flight is reported at once, as an `agent_message_chunk` paragraph of its own: `Background job <id> exited with status <status>: <command>`, or `Background job <id> was killed by SIG<signal>: <command>` for a job ended by a signal. ACP has no agent-started turn, so the model is told at the start of the next `session/prompt`, whose stream opens with the blank-line break above. A job that exits while a prompt is in flight sends no update of its own.
- Tool calls always run: no tool call waits on the client. The agent sends `session/request_permission` only for a [question the host relays](#relaying-questions-to-the-client).
- `session/list` maps the saved sessions of the store — scoped to the `cwd` the client sends, all of them when it sends none — to ACP session info: the session id, the cwd, the first prompt as the title, and the session file's last update as `updated_at`.
- `session/load` restores a saved session: a [Loader](EMBEDDING.md#building-a-runtime-with-the-loader) at the request's `cwd` reads the stored entries and rebuilds the Runtime, the stored messages replay as updates in the order they were recorded — user turns as `user_message_chunk`, the assistant's text as `agent_message_chunk`, and each tool result as its completed `tool_call` (the result as its content; the arguments are not replayed), while a [job exit notification](EMBEDDING.md#exit-notifications) replays as a blank-line `agent_message_chunk` rather than as the user's turn, since the user never typed it — then the Runtime's commands go out as `available_commands_update`, and then the request answers. A following `session/prompt` continues the conversation; an unknown id fails with resource not found.
- MCP servers the client sends on `session/new` or `session/load` in stdio shape are declared to the Runtime through the [`rig.mcp` seam](MCP.md#declaring-servers-from-an-extension) as if an extension had declared them, so a reload rebuild keeps them and a same-name declaration replaces them. See [MCP](MCP.md#servers-over-acp) for the stdio limit.

## Serving connections from your own process

`riffer acp` serves one connection on stdio, closes its sessions' Runtimes — killing their background jobs — and exits. A Ruby process that owns its transports builds the agent itself, one per connection, over that connection's IO pair:

```ruby
live = {}
build = lambda do |cwd, host, servers|
  Riffer::Rig::ACP.build_runtime(cwd, host, servers, env: env, home: Dir.home).tap { |runtime| live[runtime.id] = runtime }
end

Riffer::Rig::ACP.for(input: input, output: output, env: env, home: Dir.home, cwd: Dir.pwd, build: build, adopt: ->(id) { live[id] }).run do |connection|
  # the client has disconnected; the process moves on when this block returns
end
```

- `input:` and `output:` are the connection's IO pair. `env:` — a `Riffer::Rig::Env`, or what `Riffer::Rig::Env.load` returned — and `home:` are what every session's Loader is built with, and `cwd:` is the working directory the agent falls back to when a `session/list` names none. All five are required.
- `build:` replaces how `session/new` builds its Runtime. It receives the request's `cwd`, the session's host and the client's MCP declarations, and returns the Runtime; `Riffer::Rig::ACP.build_runtime` is the default.
- `adopt:` lets a Runtime outlive the connection that built it. `session/load` calls it with the session id before reading the store: a Runtime it returns serves the session as it is — nothing is rebuilt and the request's MCP servers are not declared, so a client that reconnects reaches the Runtime still running its turn, and its `session/cancel` cancels that turn — and `nil` restores the session from the store as usual. The stored messages replay either way. An adopted Runtime's notify lines, job exit updates and [relayed questions](#relaying-questions-to-the-client) move to the adopting connection; a turn an earlier connection started keeps streaming to that one. The hook runs on a request thread, so guard what it reads.
- `run` blocks until the client disconnects, then yields the `ACP::AgentConnection` to its block, if one is given, and returns `0`. Requests still running when the client disconnects are not waited for. Once the block returns, `run` cancels any turn still running on the Runtimes the agent built itself — through the default `build:`, or restored from the store by `session/load` — and closes them, which kills their background jobs. A Runtime your `build:` returned or `adopt:` handed over stays open: closing it is yours to do.

## What it skips

- The other session-lifecycle methods: `session/resume`, `session/close`, `session/delete` and `authenticate` are not offered. [Sessions](SESSIONS.md) are still recorded to the store for the terminal to resume.
- MCP servers in `http` or `sse` shape are skipped with a warning; only the stdio shape is read.
- Terminal delegation (`terminal/*`) and file delegation (`fs/*`) to the client are never requested. Elicitation is requested only for a [question the host relays](#relaying-questions-to-the-client).
- Prompt blocks of other kinds than text and resource links are not advertised in `promptCapabilities`, so a compliant client does not send them.

A project `rig.rb` loads only once it is trusted: neither `session/new` nor `session/load` can [ask about it](#relaying-questions-to-the-client) while it builds the Runtime, so an untrusted file is skipped and nothing is stored. The session asks the client at its next [automatic reload](RELOADING.md#triggers), which a change to the file sets off.

## Relaying questions to the client

The host's `ask` and `confirm` reach the client, and each question blocks the turn until the client answers:

- `confirm` sends `session/request_permission` with two options, `Yes` (`allow_once`) and `No` (`reject_once`). Only `Yes` confirms.
- `ask` with `options:` sends `session/request_permission` with one `allow_once` option per choice and answers with the one the client selects.
- `ask` without options sends `elicitation/create` in form mode, scoped to the session, for one required string field named `answer`, and answers with what the client submits. A client that does not advertise `elicitation.form` is not sent the request, and the ask is declined.
- `ask` with `secret: true` is always declined: ACP forbids asking for a secret in a form.

A permission request has to name a tool call and a question has none, so each one carries a tool call of its own — a fresh `toolCallId`, `pending`, with the question as its `title`. Before the request is sent, a `tool_call` update announces that tool call on the session. When the request ends, a `tool_call_update` closes that `toolCallId`: `completed` when the client selected an option, `No` included, and `failed` otherwise.

Anything but a selected option or an accepted form — the client cancels, declines, answers with an error, or the connection closes — declines the question: `confirm` is `false` and `ask` is `nil`. A trust question the client declines is stored as a no, like any other ([Extensions](EXTENSIONS.md#the-rigrb-files)).

A question is relayed only once the session is built. While `session/new` or `session/load` is building the Runtime the host reports only `:notify`, so the questions of the build — trusting a project `rig.rb` included — are declined without being sent, and no answer is stored. The client learns the id of a new session only from the `session/new` reply, and a question sent during a `session/load` would hold up the load it belongs to.