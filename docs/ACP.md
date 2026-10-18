# ACP

`riffer acp` runs riffer-rig as an [Agent Client Protocol](https://agentclientprotocol.com) agent over stdio, so editors and other ACP clients can use it without a terminal.

## Registering with an editor

Register the command `riffer acp`. In [Zed](https://zed.dev), open Agent Settings → External Agents → Add Agent → Add Custom Agent, or add it to `settings.json` yourself:

```json
{
  "agent_servers": {
    "Riffer": { "type": "custom", "command": "riffer", "args": ["acp"], "env": {} }
  }
}
```

Each session loads exactly as the terminal does — settings, credentials, trusted `rig.rb` files, skills — for the working directory the client sends. The model comes from `RIFFER_MODEL` or the settings ([precedence](CONFIGURATION.md#where-each-value-comes-from)). The agent can't ask while a session starts, so a session whose model or credentials are missing is refused with the reason: set them up in the terminal first.

## What the agent supports

| ACP method                    | Support                                                                                          |
| ----------------------------- | ------------------------------------------------------------------------------------------------ |
| `session/new`                 | starts a session; the `sessionId` is the riffer-rig session id                                   |
| `session/prompt`              | runs a turn, or a [command](#commands) when the text starts with `/`                             |
| `session/cancel`              | cancels the running turn; it ends with `cancelled`                                               |
| `session/load`                | resumes a [saved session](SESSIONS.md), replaying its messages first; an unknown id is "resource not found" |
| `session/list`                | lists saved sessions for the client's `cwd` (all of them without one), titled by their first prompt |
| `session/request_permission`  | sent only to [relay a question](#questions); tool calls never wait for permission                |
| `elicitation/create`          | sent only to [relay a free-text question](#questions)                                           |
| `session/resume`, `session/close`, `session/delete`, `authenticate` | not offered                                               |
| `terminal/*`, `fs/*`          | never requested                                                                                   |

Prompts may contain text and resource links; a resource link is passed to the model as its name and URI.

## What the client sees

| In the session                                  | ACP update                                                                                  |
| ----------------------------------------------- | ------------------------------------------------------------------------------------------- |
| the reply streaming                             | `agent_message_chunk`                                                                        |
| a tool call, once its arguments are complete    | `tool_call`, in progress                                                                     |
| that tool call finishing                        | `tool_call_update`: `completed`, or `failed` for an error (a blocked call included), with the result text |
| a notice or warning                             | `agent_message_chunk`, as a paragraph of its own                                             |
| a [background job](TOOLS.md#background-jobs) exiting between prompts | `agent_message_chunk`: `Background job <id> exited with status <status>: <command>`; the model hears at the next prompt |
| the available commands                          | `available_commands_update`, after `session/new`, after a `session/load` replay, and when a reload changes them |

| How the turn ended                                     | `stopReason`         |
| ------------------------------------------------------ | -------------------- |
| completed, or a command that started no turn          | `end_turn`           |
| hit the step limit                                     | `max_turn_requests`  |
| output length limit, context window, or blocked output | `max_tokens`         |
| cancelled                                              | `cancelled`          |

A turn that fails — a provider or network error — answers with an internal error carrying the same message the terminal would print, and the session stays usable.

## Commands

A prompt starting with `/name` runs that command instead of prompting the model, with the rest of the text as its arguments: `/reload`, `/trace`, `/auth`, `/model`, `/reasoning`, `/cost`, every `/skill:<name>`, and commands from extensions. Output arrives as `agent_message_chunk` updates; an unknown name answers `Unknown command: <name>`.

## Questions

When riffer-rig needs an answer — trusting a project `rig.rb`, a missing credential during `/auth`, an extension's own question — it asks the client:

| riffer-rig asks                 | The client gets                                                     | The answer                         |
| ------------------------------- | ------------------------------------------------------------------- | ---------------------------------- |
| yes or no                       | `session/request_permission` with `Yes` and `No`                    | yes only if `Yes` was selected     |
| a choice                        | `session/request_permission` with one option per choice             | the selected option                |
| free text                       | `elicitation/create`, one required string field named `answer`     | the submitted text; declined if the client doesn't support form elicitation |
| a secret                        | nothing — ACP forbids asking for secrets in a form                  | declined                           |

Each question appears in the session as a pending tool call titled with the question, closed when it is answered. Anything other than a selected option or a submitted form — cancelling, an error, a disconnect — declines the question.

Questions can't be asked while a session is starting. A project `rig.rb` that isn't trusted yet is therefore skipped at `session/new`, and the client is asked about it the next time the file changes. To avoid that, trust it once in the terminal.

## Limits

MCP servers the client sends with `session/new` or `session/load` aren't used: stdio servers can't be registered, because riffer-rig's [MCP client](MCP.md#limits) speaks only HTTPS, and servers in ACP's `http` or `sse` shape are skipped. Each is reported.

## Serving connections from your own process

`riffer acp` serves one connection on stdio, then exits. A Ruby process that manages its own connections builds the agent itself, once per connection:

```ruby
live = {}
build = lambda do |cwd, host, servers|
  Riffer::Rig::ACP.build_runtime(cwd, host, servers, env: env, home: Dir.home).tap { |runtime| live[runtime.id] = runtime }
end

Riffer::Rig::ACP.for(input: input, output: output, env: env, home: Dir.home, cwd: Dir.pwd, build: build, adopt: ->(id) { live[id] }).run do |connection|
  # the client has disconnected; the process moves on when this block returns
end
```

| Keyword            | Meaning                                                                                                   |
| ------------------ | --------------------------------------------------------------------------------------------------------- |
| `input:`, `output:` | the connection's IO pair                                                                                 |
| `env:`, `home:`    | what each session's [Loader](EMBEDDING.md#building-a-runtime-with-the-loader) is built with: a `Riffer::Rig::Env` (or `Env.load`'s result) and the home directory |
| `cwd:`             | the directory `session/list` uses when the client sends none                                              |
| `build:`           | how `session/new` builds a Runtime from the client's `cwd`, host and MCP servers; default `ACP.build_runtime` |
| `adopt:`           | called by `session/load` with the session id; return a still-running Runtime to hand it to this connection — a client that reconnects mid-turn reaches the same turn — or `nil` to restore from the store. It runs on a request thread |

`run` blocks until the client disconnects, yields the connection, and returns `0`. It then cancels and closes the Runtimes it built or restored itself; a Runtime your `build:` returned or `adopt:` handed over is yours to close.
