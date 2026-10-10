# Tools

riffer-rig ships four tools — `read`, `write`, `edit` and `bash` — each registered by its own bundled extension, so a host can pass any subset of them and a later extension can replace any one.

## The four tools

| Tool    | Does                                                                                                                                                        | Guidance in its description                                                                          |
| ------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------- |
| `read`  | returns a file with line numbers; `offset` (1-based) and `limit` (default 2000 lines) slice a large file; a missing file is a tool error                    | "Read a file before editing it, and read rather than guess what a file contains."                   |
| `write` | creates or overwrites a file, making any parent directories                                                                                                 | "Use this for new files or full rewrites; prefer edit for changes to an existing file."             |
| `edit`  | replaces an exact string, which must be unique unless `replace_all` is set; a missing or ambiguous match is a tool error                                    | "Prefer this over write for existing files; pass enough surrounding text to make old_string unique." |
| `bash`  | runs a command in the working directory in its own process group and returns combined stdout/stderr; a non-zero exit is a tool error; `timeout_ms` (default 120000) caps each call; output is truncated at 30,000 bytes; a Runtime `cancel` kills the process group; `run_in_background` starts the command as a background job and returns a job id and output path immediately | "Use this for exploring and running things: ls, rg or grep, find, tests, git, package managers."    |

The guidance sentence ends each tool's description. It is the only coding guidance the model gets: the base prompt names no tools, so the guidance travels with the tool and disappears when the tool is left out.

Tools never raise. A bad argument, a missing file or a failing command comes back to the model as a tool error it can read and act on.

## Background jobs

`bash` takes a `run_in_background` flag: instead of waiting, the command runs in its own process group with stdout and stderr redirected to a private temp file, and the call returns a job id and the output path immediately. The job lives in the Runtime's in-process registry — `{pid, output path, started_at}` keyed by job id, with elapsed time and, once reaped, the exit status. Each registry touch reaps finished children and sweeps completed jobs out, so the registry cannot grow unbounded across a session. A Runtime `cancel` or `close` kills every outstanding job's process group.

Relative paths resolve against the Runtime's `cwd:` (and `bash` runs there), not the process directory, so two Runtimes in one process can work in different directories. A tool called outside a Runtime falls back to `Dir.pwd`.

## Identifiers

A tool's name everywhere — in `tools:` on `Runtime.new` and `Loader.runtime`, and on `--tools` — is its riffer `identifier`: `read`, `write`, `edit`, `bash`, and whatever identifier an extension tool declares.

```ruby
Riffer::Rig::Runtime.new('anthropic/claude-sonnet-4-6', extensions: Riffer::Rig.bundled, tools: %w[read bash])
```

The allowlist covers the tools extensions register. Tools from [MCP servers](MCP.md) are added by riffer inside the agent and are not filtered by it.

## The bundled extensions

`Riffer::Rig.bundled(:read)` returns the bundled extension of that name — the same `Riffer::Rig::Extension` type `Riffer::Rig.extension` returns — and `Riffer::Rig.bundled` with no argument returns all of them in load order: `read`, `write`, `edit`, `bash`, then `agents_md` ([Instructions](INSTRUCTIONS.md#agentsmd)), `skills` ([Skills](SKILLS.md)) and `mcp` ([MCP](MCP.md)). An unknown name raises `KeyError`. An embedder composes them with its own:

```ruby
Riffer::Rig::Runtime.new(
  'anthropic/claude-sonnet-4-6',
  extensions: [Riffer::Rig.bundled(:read), Riffer::Rig.bundled(:bash), MyExt]
)
```

The bundled extensions are not recorded in the `Riffer::Rig.extensions` registry, so a user extension that happens to share a name never overwrites one.

## Provider-native tools

Web search — and, later, code execution and file search — is a provider-native tool: the model runs it inside the provider's own request, so it is core, not something an extension could add. It is off by default and switched on per tool in the `tools.native` block of settings ([Configuration](CONFIGURATION.md#toolsnative)):

```json
{ "tools": { "native": { "web_search": true } } }
```

The Loader passes the switches to the Runtime, which adds the provider option to every request only when the current provider supports the tool; otherwise nothing happens and no error is raised. `web_search` is supported by `anthropic`, `openai` and `azure_openai`. On a provider without native search — `gemini`, `openrouter`, `amazon_bedrock` — the switch does nothing, and the user brings a third-party tool. An embedder building a Runtime directly passes the switches itself as the `native_tools:` keyword.

A switch value can be an object instead of `true`, passed through to the provider as the tool's options, e.g. `{"web_search": {"max_uses": 3}}`.

`/model provider/name` re-derives the options for the new provider along with the rest of the model options: the tool turns on and off as the provider supports it, so a switch never errors and never leaves an option the new provider would reject.

## Replacing a tool

Register a tool with the same identifier from a later extension:

```ruby
class SandboxedBash < Riffer::Tool
  identifier 'bash'
  description 'Run a shell command inside the sandbox.'
  # params and call as for any riffer tool
end

sandbox = Riffer::Rig.extension('sandbox') { |rig| rig.tool SandboxedBash }
Riffer::Rig::Runtime.new('anthropic/claude-sonnet-4-6', extensions: [*Riffer::Rig.bundled, sandbox])
```

The later registration wins and takes the earlier tool's place in the list. The Runtime reports each replacement through the host's `notify` at level `:info` — "Extension sandbox replaces tool bash from bash" — which also reaches the stream as a `notify` event. Nothing is deregistered: `Riffer::Rig.bundled(:bash)` still returns the original. Commands and prompt sections follow the same rule; see [Extensions](EXTENSIONS.md).
