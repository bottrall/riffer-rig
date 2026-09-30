# Embedding riffer-rig

Host riffer-rig inside another Ruby process with `Riffer::Rig::Runtime` — a runtime that builds its own `Riffer::Agent` from a per-instance `Riffer::Agent::Config`, runs extension blocks against a per-Runtime registrar, and streams a prompt. It never renders, never prints, and never reads the filesystem; anything a host needs is a Runtime feature so embedders get it too.

## Constructing a Runtime

```ruby
runtime = Riffer::Rig::Runtime.new(
  'anthropic/claude-sonnet-4-6',
  extensions: [Riffer::Rig.extension('my_ext') { |rig| rig.tool MyTool }],
  host: MyHost.new,
)
```

The constructor takes everything as keywords — `model:` (positional, required), `extensions:`, `tools:`, `settings:`, `host:`, `cwd:`, `name:`, `instructions:`, `max_steps:`, `credentials:`, `pricing:`, `riffer_config:`, `mcp_registry:`, `snapshot:`. All except the model are optional. `credentials:` is stored and exposed (`runtime.credentials`); only `/model` and a [restore](#snapshots) read it so far. `credentials:` already takes the shape the Loader will pass — each provider's resolved field values — so embedders building it today keep working when its ticket lands. Provider credentials reach riffer through `Riffer.config`, one set per process: `Riffer::Rig::Credentials.resolve` finds a provider's values and `Riffer::Rig::Credentials.apply` assigns them (see [Providers](PROVIDERS.md)), or set them yourself with `Riffer.configure`.

| Keyword         | Meaning                                                                     | Default                 |
| --------------- | --------------------------------------------------------------------------- | ----------------------- |
| `model`         | `"provider/name"`; required, positional                                     | —                       |
| `extensions:`   | ordered extension objects whose blocks run against this Runtime's registrar; `Riffer::Rig.bundled` gives the [bundled tools](TOOLS.md), [AGENTS.md section](INSTRUCTIONS.md#agentsmd), [skills](SKILLS.md) and [MCP client](MCP.md) | `[]`                    |
| `tools:`        | allowlist of tool identifiers; `nil` means every registered tool. [MCP tools](MCP.md#tool-names) are not filtered | `nil`                   |
| `settings:`     | merged settings hash (core keys top level, extension keys under their names); a command reads its extension's namespace as `ctx.settings` | `{}` |
| `host:`         | an object implementing [`Riffer::Rig::Hosts::_Host`](HOSTS.md)              | `Riffer::Rig::Hosts::Null.new` |
| `cwd:`          | working directory for the environment block, and the directory tools resolve relative paths against | `Dir.pwd`               |
| `name:`         | the name interpolated into the [base prompt](INSTRUCTIONS.md)               | `"riffer"`              |
| `instructions:` | replaces the base prompt; sections and the environment block still apply    | `nil` (use the base)    |
| `max_steps:`    | agent-loop step limit; `nil` runs the loop without a limit                  | `nil`                   |
| `credentials:`  | provider → resolved field values (`{ anthropic: { api_key: "…" } }`), stored as given and exposed; read by `/model` and a restore | `{}` |
| `pricing:`      | model → `Riffer::Rig::Settings::Pricing` entries (USD per million tokens), registered into riffer's pricing when the Runtime is built; see [tally](#token-tally-and-cost) | `{}` |
| `riffer_config:` | the `Riffer::Config` whose `pricing` receives the `pricing:` entries      | `Riffer.config`         |
| `mcp_registry:` | where declared [MCP servers](MCP.md) are registered and unregistered: an object with riffer's `register(name:, endpoint:, tags:, discovery_headers:)` and `unregister(name)` | `Riffer::Mcp` |
| `snapshot:`     | a hash from `to_h` to restore; see [Snapshots](#snapshots)                 | `nil`                   |

`runtime.settings` is the `settings:` hash with each extension's [declared defaults](EXTENSIONS.md#the-rigsetting-seam) filled into its namespace; core reads it only to hand each [command](#commands) its extension's namespace. `runtime.declared_settings` is the table of what extensions declared, extension name → key → default, for a host to render.

Two Runtimes in one process share nothing but the process-wide extension registry, riffer's provider repository and riffer's config, which holds the process's one set of provider credentials.

## Prompting

`prompt(text)` runs one turn on the calling thread. With a block it yields every riffer `StreamEvent` as it happens; without one it returns an `Enumerator`:

```ruby
runtime.prompt('Explain this repository') do |event|
  case event
  when Riffer::StreamEvents::TextDelta then print event.content
  when Riffer::StreamEvents::ToolCallDone then puts "\n[tool: #{event.name}]"
  end
end

runtime.prompt('and this one?').each { |event| ... }
```

One prompt runs at a time per Runtime; a second `prompt` or `ask` while one is running raises `Riffer::Rig::Runtime::BusyError`. Parallelism means more Runtimes, in more threads.

## Asking for a turn

`ask(text)` runs one turn to completion and returns riffer's `Riffer::Agent::Response` — the same loop `prompt` streams, gathered into the single value riffer already builds. The headless host and embedders build on it; the terminal builds on the stream.

```ruby
response = runtime.ask('Fix the failing test')
puts response.content
puts "outcome: #{response.outcome.reason}"
response.messages.each do |message|
  next unless message.is_a?(Riffer::Messages::Assistant)
  message.tool_calls.each { |call| puts "  #{call.name}(#{call.arguments})" }
end
if (usage = response.token_usage)
  puts "usage: #{usage.input_tokens} in / #{usage.output_tokens} out"
  puts format('cost: $%.4f', usage.cost) if usage.cost
end
```

How the run ended is riffer's `response.outcome` — `reason` is one of riffer's vocabulary (`completed`, provider finish reasons like `length` and `content_filter`, `max_steps`, `guardrail_blocked`, `interrupted`, …) and `detail` carries the specifics, such as the interrupt reason behind `:interrupted`. A [cancelled](#cancelling-a-turn) run ends the same way — `reason: :interrupted`, `detail: "cancelled"` — because riffer's outcome vocabulary has no `cancelled` entry yet. Hosts map `outcome.reason` to exit codes or UI.

## Token tally and cost

riffer prices usage at source: each provider looks its model up in `Riffer.config.pricing` and sets `cost` on the usage it reports. The Runtime registers every `pricing:` entry there when it is built, and `tally` returns riffer's running total for the Runtime's agent — `agent.context.token_usage`, a `Riffer::Providers::TokenUsage` summed over every model call of every `prompt` and `ask`, or `nil` before the first turn.

```ruby
pricing = { 'anthropic/claude-sonnet-4-6' => Riffer::Rig::Settings::Pricing.new(input: 3.0, output: 15.0, cache_write: 3.75, cache_read: 0.3) }
runtime = Riffer::Rig::Runtime.new('anthropic/claude-sonnet-4-6', pricing: pricing)
response = runtime.ask('Fix the failing test')
response.token_usage.cost # => this turn, in USD
runtime.tally.input_tokens # => every turn so far
runtime.tally.cost         # => every turn so far, in USD
```

Each turn's usage is riffer's: on the `ask` response as `response.token_usage`, and on the stream as the closing `turn_end` event's `usage` and `cost` — the same values. Rates are USD per million tokens. riffer counts cache reads and writes inside `input_tokens`, so the cached share is priced at the `cache_read` and `cache_write` rates and only the rest at `input`.

Missing pricing means `nil`, never zero: a model `Riffer.config.pricing` has no rates for reports no `cost`, and neither does the tally. Pricing is process-wide and keyed by model id, so two Runtimes that price the same model differently share whichever registered last. The terminal takes its pricing from the `models` block of `~/.riffer/settings.json` ([Configuration](CONFIGURATION.md#models)); an embedder passes its own, or registers rates itself with `Riffer.config.pricing.set`.

## Rig events

The stream a host consumes is riffer's `StreamEvents` unchanged, plus a few rig-level events from `Riffer::Rig::Events`. A rig event is any object with `type` and `to_h` (the RBS interface `Riffer::Rig::Events::_Event`). Rig's own are frozen value objects that include `Riffer::Rig::Support::Equatable`, so they are equal when their class and `to_h` match; each has `to_h` — with the type folded in, so a headless host can print every record verbatim as NDJSON — and `type`, the snake_case form of its class name.

| Rig event         | Carries                          | When                                                              |
| ----------------- | -------------------------------- | ----------------------------------------------------------------- |
| `session_start`   | `id`, `reason` (`:new`, `:restore`, `:reload`) | opens the first prompt after construction (or a restore, or a rebuild) |
| `session_end`     | `reason` (`:reload`, `:close`)   | opens the first prompt after a [rebuild](#rebuilding-after-a-code-reload), ahead of its `session_start`; on `close` (hooks only — see the note below) |
| `command_output`  | `command`, `text`                | a command called `ctx.say`                                        |
| `skill_activated` | `name`                           | a skill was activated by command                                  |
| `notify`          | `message`, `level`               | mirrors every `host.notify`, so a stream consumer sees extension errors too |
| `turn_end`        | `stop_reason`, `usage`, `cost`   | the last event of every `prompt`; `stop_reason` is riffer's outcome reason, or `:cancelled` after a `cancel`; `usage` is riffer's `TokenUsage` and `cost` its USD figure, `nil` when unpriced |

`session_start` carries `:new`, `:restore` on a Runtime built from a [snapshot](#snapshots), or `:reload` after a [rebuild](#rebuilding-after-a-code-reload); `session_end` carries `:reload` or `:close`. `close` refuses further prompts and asks with `Riffer::Rig::Runtime::ClosedError` and unregisters every [MCP server](MCP.md) the Runtime registered; its `session_end` reaches extension hooks but not the stream, since no prompt follows it.

Every `prompt` ends with `turn_end` — with a block or as an Enumerator — so a stream consumer never needs `ask` to learn how the turn ended and what it cost. The headless host prints this same stream as NDJSON; see [Headless mode](HEADLESS.md) for the wire shape.

## Cancelling a turn

`cancel` stops the running turn. It is thread-safe and meant to be called from another thread — a signal handler's worker, a UI thread, a request handler — while `prompt` or `ask` blocks the thread that started the turn. It returns `nil` immediately; the turn ends on its own thread.

```ruby
turn = Thread.new { runtime.prompt('refactor everything') { |event| render(event) } }
runtime.cancel
turn.join
```

The turn stops at the next message boundary — after the assistant message being streamed completes, or after the tool calls in flight return — not mid-token. The bundled `bash` tool does not wait that long: it polls the cancel flag, kills its command's process group and returns a tool error ending in `[cancelled]`. A tool of your own can do the same through `context[:cancel_flag].set?`.

A cancelled turn leaves the conversation usable. Tool calls that never got a result are filled with an "interrupted" tool error, riffer emits its `Riffer::StreamEvents::Interrupt` event with reason `:cancelled`, and the stream closes with `turn_end` carrying `stop_reason: :cancelled`. From `ask`, the response's outcome is `reason: :interrupted` with `detail: "cancelled"`. The next `prompt` or `ask` carries on from there.

`cancel` with no turn running is a no-op: the flag is cleared when the next turn starts.

## Commands

Slash commands are runtime objects: extensions register them with [`rig.command`](EXTENSIONS.md#the-rigcommand-seam), and every host drives them through the Runtime, so a command works the same in the terminal, headless and over ACP. Commands that end or replace the Runtime itself — `/exit`, `/new`, `/resume` — belong to the host, not here.

`commands` lists the registered commands in load order. Each is a `Riffer::Rig::Command` with a `name` (without the leading slash) and a `description`:

```ruby
runtime.commands.each { |command| puts "/#{command.name}  #{command.description}" }
```

`run_command(name, args)` runs one on the calling thread and returns `nil`; its output arrives as events. With a block it yields each one as it happens — `command_output` for every `ctx.say`, the whole stream of a turn the command starts with `ctx.prompt` (from `session_start`, if it is the Runtime's first turn, to `turn_end`), and a `notify` for anything the host was told. Without a block the events are discarded, as `ask` discards the stream.

```ruby
runtime.run_command('log', '5') do |event|
  case event
  when Riffer::Rig::Events::CommandOutput then puts event.text
  when Riffer::StreamEvents::TextDelta then print event.content
  when Riffer::Rig::Events::Notify then warn event.message
  end
end
```

A command runs under the same rule as `prompt`: one at a time per Runtime, so `run_command` while a prompt or command is running raises `Riffer::Rig::Runtime::BusyError`, and after `close` it raises `Riffer::Rig::Runtime::ClosedError`. A command that raises never escapes `run_command`: it is reported through `host.notify` at level `:error` (and so as a `notify` event), and the Runtime stays usable. An unknown name is reported the same way. `cancel` stops a turn a command started, as it stops any other.

## Switching the model

`model` is the effective `"provider/name"` string. Assigning `model=` switches it for this Runtime only: history, the tally, tools and the host all carry over, and the next model call goes to the new model. A string without a provider prefix, or with a provider riffer's registry does not know, raises `Riffer::ArgumentError` and leaves the model unchanged.

```ruby
runtime.model # => "anthropic/claude-sonnet-4-6"
runtime.model = 'openai/gpt-5'
```

`model` is also a core command, listed in `commands` first, ahead of the [`skill:<name>`](SKILLS.md#skillname) commands and every extension's: `run_command('model', 'openai/gpt-5')` validates before it assigns. A bare name or an unknown provider gets a `command_output` listing the providers; a provider whose required fields are missing from the Runtime's `credentials:` is refused through `notify` at level `:error`, as is `--save`, which is not available yet. With no argument it reports the current model.

## Rebuilding after a code reload

`rebuild(extensions:, settings:)` replaces everything the Runtime's extensions registered — tools, commands, prompt sections, hooks, skills sources, declared settings and MCP servers — with what the given extension list registers, run against a fresh registrar. It is the primitive behind hot reloading: an embedder without the Loader calls it after its own code reload (a Rails `to_prepare` block, say) with the re-created extension objects and the settings it wants now. The Runtime watches no files and has no `/reload` of its own, since it knows no filesystem conventions.

```ruby
Rails.application.reloader.to_prepare do
  runtime.rebuild(extensions: [*Riffer::Rig.bundled, MyApp.rig_extension], settings: MyApp.rig_settings)
end
```

The new registrations are built aside and swapped in only once every extension in the list has loaded. If any fails — its block raises, its `requires` is unmet, or its name collides with a core settings key — `rebuild` raises that error and nothing on the Runtime changes. This is stricter than construction, which skips a failing extension and records it on `errors`: a rebuild either swaps in the whole list or leaves the working one in place. After a successful rebuild `errors` is empty, and replacements across the new list are reported through `notify` as at construction.

Kept across a rebuild: the message history, the [tally](#token-tally-and-cost), the model (including a [`model=`](#switching-the-model) override — a `model` key in the new settings does not clobber it), `id`, `host`, and every constructor keyword other than `extensions:` and `settings:` (`tools:` still filters the new tools). An MCP server whose name, url and headers are unchanged is not registered again; a changed one is re-registered and a dropped one unregistered ([MCP](MCP.md#reload-and-close)). Providers are process-wide: riffer never unregisters one, so a provider registered before the rebuild stays registered, and an extension that registers it again just replaces the entry.

Once the Runtime's session has started, the old hooks get `session_end(reason: :reload)` before the swap and the new ones `session_start(reason: :reload)` after it — where an extension releases and re-acquires process-wide state — and the next prompt's stream opens with those two events. Before the first turn a rebuild fires neither, and the first prompt opens with `session_start(reason: :new)` as usual.

`rebuild` runs between turns only. Like `prompt`, it raises `Riffer::Rig::Runtime::BusyError` while a prompt or command is running — so from inside a hook or a command — and `Riffer::Rig::Runtime::ClosedError` after `close`. It returns `nil`.

## Capping the loop

`max_steps:` caps how many LLM steps one run may take (`nil` — the default — runs the loop without a limit). A run that hits the cap ends with `outcome.reason: :max_steps`; the model's partial output is still on the response.

```ruby
runtime = Riffer::Rig::Runtime.new('anthropic/claude-sonnet-4-6', max_steps: 8)
response = runtime.ask('do the thing')
puts response.outcome.reason # => :max_steps if the cap stopped the loop
```

## Snapshots

A Runtime saves and restores as a plain hash. `to_h` returns the snapshot; `Riffer::Rig::Runtime.new(model, snapshot: hash, ...)` builds a Runtime that carries on from it. The Runtime never touches disk: keeping the hash — as JSON, in a database, anywhere — is the embedder's job. [Sessions](SESSIONS.md) describes what a snapshot holds.

```ruby
snapshot = runtime.to_h
File.write('session.json', JSON.generate(snapshot))

snapshot = JSON.parse(File.read('session.json'), symbolize_names: true)
runtime = Riffer::Rig::Runtime.new(
  'anthropic/claude-sonnet-4-6',
  extensions: Riffer::Rig.bundled,
  credentials: credentials,
  snapshot: snapshot,
)
runtime.ask('where were we?')
```

The snapshot's keys are symbols; parse JSON with `symbolize_names: true`. A snapshot holds history, not registrations: tools, commands, hooks, prompt sections and declared settings come from the `extensions:` and `settings:` given at restore time, through the same path a fresh Runtime takes. The tally is not stored either — the restored Runtime's `tally` is the sum of its messages' `token_usage`.

History is data, and the present wins, so nothing in a snapshot blocks a restore:

- A tool call for a tool that no longer exists is just history the model reads.
- Tool calls at the tail with no result — a process killed mid-turn — are filled with an "interrupted" tool error on load, as a [cancel](#cancelling-a-turn) does, and are never run.
- The saved model (a `model=` or `/model` switch) applies only if its provider has an entry in `credentials:`; otherwise the given model is used and the host gets one `notify` at level `:warning`. A Runtime restored with its saved model keeps it as its own override, so its next `to_h` saves it again.
- Activated skills re-apply by name; a skill that no longer exists is dropped.

The first prompt of a restored Runtime opens with `session_start` carrying the snapshot's `id` and reason `:restore`, and extensions' `session_start` hooks see the same reason.

## Observing messages

`on_message { |message| }` registers an observer called with each message the conversation gains, in order: the user's prompt, each assistant message and each tool result, as riffer's `Riffer::Messages` objects. It is how a store appends to a session as it happens rather than snapshotting at the end:

```ruby
runtime.on_message { |message| log.puts(JSON.generate(message.to_h)) }
```

Observers run on the prompting thread, inside the turn, once per message; they survive a model switch. The system message is not delivered — it is rebuilt every turn — nor are the "interrupted" results filled in after a cancel or on restore.
