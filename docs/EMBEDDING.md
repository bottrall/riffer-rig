# Embedding riffer-rig

Host riffer-rig inside another Ruby process with `Riffer::Rig::Runtime` — a runtime that builds its own `Riffer::Agent` from a per-instance `Riffer::Agent::Config`, runs extension blocks against a per-Runtime registrar, and streams a prompt. It never renders, never prints, and never reads the filesystem; anything a host needs is a Runtime feature so embedders get it too.

## Building a Runtime with the Loader

`Riffer::Rig::Loader` knows riffer-rig's filesystem conventions, so the Runtime does not have to. `Loader.runtime` builds a Runtime for a working directory the way the shipped hosts do:

```ruby
runtime = Riffer::Rig::Loader.runtime(cwd: Dir.pwd, host: MyHost.new)
```

In order, it:

1. reads `~/.riffer/settings.json` then `<cwd>/.riffer/settings.json` and merges them, the project winning key by key ([Configuration](CONFIGURATION.md)), and selects the model: the `model:` [option](#loader-options), then `RIFFER_MODEL`, then the settings, then onboarding;
2. resolves the model's provider credentials ([Providers](PROVIDERS.md#resolution-order)), assigns them to `Riffer.config` and keeps them for the Runtime's `credentials:`;
3. takes the [bundled extensions](TOOLS.md), minus those named in `extensions.disabled` and those the options strip;
4. runs `riffer/rig/extension` from every gem when [`extensions.autoload`](CONFIGURATION.md#extensions) is set, then `~/.riffer/rig.rb` and, once [trusted](EXTENSIONS.md#the-rigrb-files), `<cwd>/.riffer/rig.rb`, and appends the extensions the loads record to the bundle ([Extensions](EXTENSIONS.md#the-rigrb-files));
5. constructs the Runtime with the model, the credentials, the extensions, the merged settings, the `models` pricing table, the `reasoning` level as riffer `model_options`, and the options and keywords below.

Whatever `store:` records the build: the [header](SESSIONS.md#what-an-entry-holds) lands on the first message, then one entry per message, per `/model` switch and per model skill activation; `store: nil`, or `"sessions": {"save": false}` in settings ([Configuration](CONFIGURATION.md)), writes nothing ([Sessions](SESSIONS.md)). A build that records also gets the [`/trace`](SESSIONS.md#tracing-the-last-turn) command, which replays the last turn from the same store.

| Keyword       | Meaning                                                                  | Default |
| ------------- | ------------------------------------------------------------------------ | ------- |
| `cwd:`        | the working directory; its `.riffer/settings.json` is the project scope  | required |
| `host:`       | the [host](HOSTS.md) the Runtime gets, and the one onboarding and credential prompts ask | required |
| `options:`    | a [`Riffer::Rig::Loader::Options`](#loader-options): the model, what to leave out, the tool allowlist and the step limit | `Riffer::Rig::Loader::Options.new` |
| `reload: :manual` | drops the automatic reload check for this build ([Reloading](RELOADING.md#triggers)) | follows the `reload` setting |
| `extra_extensions:` | extensions loaded with the bundle and kept through a [reload](#rebuilding-after-a-code-reload), after the bundle and the `rig.rb` files | `[]` |
| `env:`        | a `Riffer::Rig::Env`, or what `Riffer::Rig::Env.load` returned            | `Riffer::Rig::Env.load` |
| `home:`       | the directory whose `.riffer/` holds `settings.json`, `auth.json`, `rig.rb`, `trust.json` and the default store's `sessions/` | `Dir.home` |
| `riffer_config:` | the `Riffer::Config` that receives the credentials and pricing        | `Riffer.config` |
| `store:`      | the [session store](SESSIONS.md#the-session-store) that records the build; `nil` opts one run out | `Stores::JSONL.new(home: home)` |

`Riffer::Rig::Loader.new(cwd:, host:, env:, home:, riffer_config:, store:)` takes the same setup and builds with `runtime(options, reload:, extra_extensions:)` for a host that keeps the Loader.

The host is asked only when its `capabilities` include `:ask`. With no model set anywhere, the Loader asks it for a model string, listing the providers, and writes the answer to `~/.riffer/settings.json`; a required credential that does not resolve is asked for the same way and stored ([Providers](PROVIDERS.md#rifferrigcredentials)). Anything the Loader cannot settle raises `Riffer::Rig::Loader::ConfigurationError` with a message fit to show the user: no model and a host that cannot ask (the null host), a model string without a known provider prefix, a bare `RIFFER_MODEL`, a required credential still missing, or a `settings.json` or `auth.json` that does not parse ([Configuration](CONFIGURATION.md)). A headless host should map it to exit status 2.

```ruby
begin
  runtime = Riffer::Rig::Loader.runtime(cwd: Dir.pwd, host: Riffer::Rig::Hosts::Null.new)
rescue Riffer::Rig::Loader::ConfigurationError => e
  warn e.message
  exit 2
end
```

### Loader options

`Riffer::Rig::Loader::Options` holds the per-build choices the `riffer` command-line flags make. It is a frozen value object with a reader for each keyword, and every keyword is optional:

```ruby
options = Riffer::Rig::Loader::Options.new(model: 'anthropic/claude-sonnet-4-6', skills: false)
runtime = Riffer::Rig::Loader.runtime(cwd: Dir.pwd, host: MyHost.new, options: options)
```

| Keyword             | Meaning                                                                                      | Default |
| ------------------- | -------------------------------------------------------------------------------------------- | ------- |
| `model:`            | `"provider/name"`, winning over `RIFFER_MODEL` and the settings                              | `nil`   |
| `extensions: false` | skips the `rig.rb` files and the gem `riffer/rig/extension` autoload; the bundle still loads | `true`  |
| `skills: false`     | leaves out the bundled [`skills`](SKILLS.md) extension                                       | `true`  |
| `agents_md: false`  | leaves out the bundled [`agents_md`](INSTRUCTIONS.md#agentsmd) extension                     | `true`  |
| `tools:`            | the Runtime's tool allowlist                                                                 | `nil`   |
| `max_steps:`        | the Runtime's step limit                                                                     | `nil`   |

## Constructing a Runtime

```ruby
runtime = Riffer::Rig::Runtime.new(
  'anthropic/claude-sonnet-4-6',
  extensions: [Riffer::Rig.extension('my_ext') { |rig| rig.tool MyTool }],
  host: MyHost.new,
)
```

The constructor takes everything as keywords — `model:` (positional, required), `extensions:`, `tools:`, `settings:`, `host:`, `cwd:`, `name:`, `instructions:`, `max_steps:`, `model_options:`, `native_tools:`, `credentials:`, `env:`, `auth_path:`, `pricing:`, `riffer_config:`, `mcp_registry:`, `clock:`, `snapshot:`. All except the model are optional. `credentials:` is stored and exposed (`runtime.credentials`); only `/model` and a [restore](#snapshots) read it so far. It takes the shape the [Loader](#building-a-runtime-with-the-loader) passes — each provider's resolved field values. Provider credentials reach riffer through `Riffer.config`, one set per process: `Riffer::Rig::Credentials.install` resolves a provider's values and assigns them (see [Providers](PROVIDERS.md#rifferrigcredentials)), or set them yourself with `Riffer.configure`.

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
| `model_options:` | riffer `model_options` sent with every model call (`{ reasoning: 'high' }`, `{ cache_control: { type: :ephemeral } }`); `Riffer::Rig::Settings::ModelOptions.model_options(model, reasoning)` builds them from the settings | `{}` |
| `native_tools:` | the [provider-native tool](TOOLS.md#provider-native-tools) switches, as the `tools.native` setting holds them (`{ web_search: true }`) | `{}` |
| `credentials:`  | provider → resolved field values (`{ anthropic: { api_key: "…" } }`), stored as given and exposed; read by `/model` and a restore | `{}` |
| `env:`          | the `Riffer::Rig::Env` an MCP server's [`auth` fields](MCP.md#secret-headers) resolve from | `Riffer::Rig::Env.new` |
| `auth_path:`    | the `auth.json` those fields are read from and stored in | `~/.riffer/auth.json` |
| `pricing:`      | model → `Riffer::Rig::Settings::Pricing` entries (USD per million tokens), registered into riffer's pricing when the Runtime is built; see [tally](#token-tally-and-cost) | `{}` |
| `riffer_config:` | the `Riffer::Config` whose `pricing` receives the `pricing:` entries      | `Riffer.config`         |
| `mcp_registry:` | where declared [MCP servers](MCP.md) are registered and unregistered: an object with riffer's `register(name:, endpoint:, tags:, discovery_headers:)` and `unregister(name)` | `Riffer::Mcp` |
| `clock:`        | a callable returning seconds as a `Float`, which stamps the [tool call events](#tool-call-events) | the process's monotonic clock |
| `snapshot:`     | a hash from `to_h` to restore; see [Snapshots](#snapshots)                 | `nil`                   |

`runtime.settings` is the `settings:` hash with each extension's [declared defaults](EXTENSIONS.md#the-rigsetting-seam) filled into its namespace; core reads it only to hand each [command](#commands) its extension's namespace. `runtime.declared_settings` is the table of what extensions declared — extension name → key → default, names and keys as Symbols — for a host to render.

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

One prompt runs at a time per Runtime; a second `prompt` or `ask` while one is running raises `Riffer::Rig::Runtime::BusyError`. Parallelism means more Runtimes, in more threads. `busy?` is `true` while a prompt given a block, `ask`, [command](#commands) or [rebuild](#rebuilding-after-a-code-reload) holds the Runtime, so a thread outside the turn — an [`on_job_exit`](#background-jobs) subscriber, say — can tell whether a turn is running.

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

Missing pricing means `nil`, never zero: a model `Riffer.config.pricing` has no rates for reports no `cost`, and neither does the tally. Pricing is process-wide and keyed by model id, so two Runtimes that price the same model differently share whichever registered last. The terminal takes its pricing from the merged `models` blocks of the two settings files ([Configuration](CONFIGURATION.md#models)); an embedder passes its own, or registers rates itself with `Riffer.config.pricing.set`.

`cost` is a core command, listed in `commands` after [`model`](#switching-the-model). `run_command('cost')` answers with one `command_output`: the tally on the `session` line, then a line for each turn in the order the session's messages hold them:

```
session   ↑4100 · ↓132 · cache_write:900 · cache_read:900 · ~$0.0109
turn 1    ↑2600 · ↓120 · cache_write:900 · cache_read:900 · ~$0.0063
turn 2    ↑1500 · ↓12 · ~$0.0046
```

A line holds the input and output tokens, each cache count above zero, and the cost when every model call it sums was priced. A turn is a prompt and every message up to the next one — a [job exit notification](#exit-notifications) starts no turn of its own — so a [restored](#snapshots) session lists the turns it was saved with; a turn whose model calls reported no usage reads `no usage`. The `session` line is the tally itself, so it still counts a turn that a [`before_request`](EXTENSIONS.md#the-rigon-seam) hook has since taken out of the messages. Before any usage is recorded the command answers `No usage recorded yet`.

## Rig events

The stream a host consumes is riffer's `StreamEvents` unchanged, plus a few rig-level events from `Riffer::Rig::Events`. A rig event is any object with `type` and `to_h` (the RBS interface `Riffer::Rig::Events::_Event`). Rig's own are frozen value objects that include `Riffer::Rig::Support::TypedValue`, which derives `type` and `to_h` from the type and attribute list each class declares and makes them equal when their class and `to_h` match; each has `to_h` — with the type folded in, so a headless host can print every record verbatim as NDJSON — and `type`, the snake_case form of its class name. A class opts in with `extend Riffer::Rig::Support::TypedValue::Schema`, `include Riffer::Rig::Support::TypedValue`, and a `typed_value :type, :attr, ...` declaration; every attribute it names must have a public reader, because `to_h` reads each one by name.

| Rig event         | Carries                          | When                                                              |
| ----------------- | -------------------------------- | ----------------------------------------------------------------- |
| `session_start`   | `id`, `reason` (`:new`, `:restore`, `:reload`) | opens the first prompt after construction (or a restore, or a rebuild) |
| `session_end`     | `reason` (`:reload`, `:close`)   | opens the first prompt after a [rebuild](#rebuilding-after-a-code-reload), ahead of its `session_start`; on `close` (hooks only — see the note below) |
| `command_output`  | `command`, `text`                | a command called `ctx.say`                                        |
| `skill_activated` | `name`                           | a skill was activated by command                                  |
| `notify`          | `message`, `level`               | mirrors every `host.notify`, so a stream consumer sees extension errors too |
| `before_tool_call` | `call_id`, `tool`, `args`, `at` | as a tool starts, after its `before_tool_call` hooks               |
| `after_tool_call` | `call_id`, `tool`, `args`, `result`, `at`, `duration` | as every tool call finishes, after its `after_tool_call` hooks |
| `job_exit`        | `job_id`, `command`, `exit_status`, `duration`, `output_path` | as a [background job's exit](#exit-notifications) is delivered to the model, one per job |
| `turn_end`        | `stop_reason`, `usage`, `cost`   | the last event of every `prompt`; `stop_reason` is riffer's outcome reason, or `:cancelled` after a `cancel`; `usage` is riffer's `TokenUsage` and `cost` its USD figure, `nil` when unpriced |

`session_start` carries `:new`, `:restore` on a Runtime built from a [snapshot](#snapshots), or `:reload` after a [rebuild](#rebuilding-after-a-code-reload); `session_end` carries `:reload` or `:close`. `close` refuses further prompts and asks with `Riffer::Rig::Runtime::ClosedError` and unregisters every [MCP server](MCP.md) the Runtime registered; its `session_end` reaches extension hooks but not the stream, since no prompt follows it.

### Tool call events

`before_tool_call` and `after_tool_call` are the events the [extension hooks](EXTENSIONS.md#the-rigon-seam) of the same names receive, and the stream carries them as well, each yielded at the moment it happens rather than when the batch returns. riffer's `ToolCallDone` announces every call of a response, with its `call_id`, before any of them runs; then, one call at a time, a `before_tool_call` marks the tool starting and an `after_tool_call` the call finishing. They sit in the stream after the response's `ToolCallDone` events and before the first event of the next response, so a consumer can show a batch in flight.

The stream gets one `before_tool_call` per call that runs, yielded once the call's `before_tool_call` hooks have settled and immediately before the tool runs; its `args` are the arguments the tool runs with, after any hook rewrote them. A call that will not run — a hook blocked it, or its arguments are not a JSON object — has none. A call to a tool that does not exist passes its hooks like any other, so it has one.

The stream gets exactly one `after_tool_call` for every call, whatever became of it. `result` is the call's `Riffer::Tools::Response`, and `result.error?` says whether it failed, with `result.error_type` naming the kind: the tool's own error when the tool failed, `:unknown_tool` for a tool that does not exist, `:blocked` for a call a hook blocked, with the `args` the model sent, and `:validation_error` for arguments that are not a JSON object, whose `args` are empty. It is the event the `after_tool_call` hooks observed, yielded once they have run. Tools run one at a time, so a call's `after_tool_call` precedes the next call's `before_tool_call`. The exception is a turn that ends inside the batch — a tool that raises outside `StandardError` — which takes the remaining events with it.

`call_id` is riffer's id for the call — the one on `ToolCallDone` and on the tool message — and `tool` is the tool's name. `at` is a monotonic timestamp in seconds, comparable only with the other `at` values of the same process: on `before_tool_call` the moment the tool started, on `after_tool_call` the moment it returned. `duration` is the seconds between the two, so it measures the tool alone: time spent in `before_tool_call` and `after_tool_call` hooks, a hook that waits on a person included, is left out, and a call that never ran has a `duration` of `0.0`. Summing the `duration`s of a batch gives its serial tool time.

The timestamps come from the Runtime's `clock:`, a callable returning seconds as a `Float`; it defaults to the process's monotonic clock, and a test passes its own.

Every `prompt` ends with `turn_end` — with a block or as an Enumerator — so a stream consumer never needs `ask` to learn how the turn ended and what it cost. The headless host prints this same stream as NDJSON; see [Headless mode](HEADLESS.md) for the wire shape.

## Cancelling a turn

`cancel` stops the running turn. It is thread-safe and meant to be called from another thread — a signal handler's worker, a UI thread, a request handler — while `prompt` or `ask` blocks the thread that started the turn. It returns `nil` immediately; the turn ends on its own thread.

```ruby
turn = Thread.new { runtime.prompt('refactor everything') { |event| render(event) } }
runtime.cancel
turn.join
```

A reply in flight stops at once, whether the turn is still waiting on the provider or the reply is streaming: the request is abandoned, and the text that had streamed is kept as the assistant message — delivered to [`on_message`](#observing-messages) like any other — while reasoning or a tool call still arriving is dropped. A turn cancelled this way reports no `usage` on its `turn_end`. Tool calls in flight are not cut off: the turn stops when they return. The bundled `bash` tool does not wait that long: it polls the cancel flag, kills its command's process group and returns a tool error ending in `[cancelled]`. A tool of your own can do the same through `context[:cancel_flag].set?`. [Background jobs](#background-jobs) keep running through a cancel, and their exits are still delivered; `close` ends them.

A cancelled turn leaves the conversation usable. Tool calls that never got a result are filled with an "interrupted" tool error, the stream carries riffer's `Riffer::StreamEvents::Interrupt` event with reason `:cancelled`, and it closes with `turn_end` carrying `stop_reason: :cancelled`. From `ask`, the response's outcome is `reason: :interrupted` with `detail: "cancelled"`. The next `prompt` or `ask` carries on from there.

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

`model` is also a core command, listed in `commands` after [`auth`](PROVIDERS.md#auth) and ahead of the [`skill:<name>`](SKILLS.md#skillname) commands and every extension's: `run_command('model', 'openai/gpt-5')` validates before it assigns. A bare name or an unknown provider gets a `command_output` listing the providers; the provider is set up first, its SDK gem ensured and then any required field missing from the Runtime's `credentials:` resolved through [`Credentials.install`](PROVIDERS.md#rifferrigcredentials), and the switch is refused through `notify` at level `:error` when the gem cannot be loaded or a field is still missing. `--save` also writes the model to `~/.riffer/settings.json`, and on its own saves the current one. With no argument it reports the current model.

## Rebuilding after a code reload

`rebuild(extensions:, settings:)` replaces everything the Runtime's extensions registered — tools, commands, prompt sections, hooks, skills sources, declared settings and MCP servers — with what the given extension list registers, run against a fresh registrar. It is the primitive behind hot reloading: an embedder without the Loader calls it after its own code reload (a Rails `to_prepare` block, say) with the re-created extension objects and the settings it wants now, and a Loader-built Runtime gets it through `/reload` ([Reloading](RELOADING.md)). The Runtime watches no files and has no `/reload` of its own, since it knows no filesystem conventions.

```ruby
Rails.application.reloader.to_prepare do
  runtime.rebuild(extensions: [*Riffer::Rig.bundled, MyApp.rig_extension], settings: MyApp.rig_settings)
end
```

The new registrations are built aside and swapped in only once every extension in the list has loaded. If any fails — its block raises, its `requires` is unmet, or its name collides with a core settings key — `rebuild` raises that error and nothing on the Runtime changes. This is stricter than construction, which skips a failing extension and records it on `errors`: a rebuild either swaps in the whole list or leaves the working one in place. After a successful rebuild `errors` is empty, and replacements across the new list are reported through `notify` as at construction.

Kept across a rebuild: the message history, the [tally](#token-tally-and-cost), the model (including a [`model=`](#switching-the-model) override — a `model` key in the new settings does not clobber it), `id`, `host`, and every constructor keyword other than `extensions:` and `settings:` (`tools:` still filters the new tools). An MCP server whose name, url and headers are unchanged is not registered again; a changed one is re-registered and a dropped one unregistered ([MCP](MCP.md#reload-and-close)). Providers are process-wide: riffer never unregisters one, so a provider registered before the rebuild stays registered, and an extension that registers it again just replaces the entry.

Once the Runtime's session has started, the old hooks get `session_end(reason: :reload)` before the swap and the new ones `session_start(reason: :reload)` after it — where an extension releases and re-acquires process-wide state — and the next prompt's stream opens with those two events. Before the first turn a rebuild fires neither, and the first prompt opens with `session_start(reason: :new)` as usual.

`rebuild` runs between turns only. Like `prompt`, it raises `Riffer::Rig::Runtime::BusyError` while another thread holds the Runtime mid-prompt, command or hook, and `Riffer::Rig::Runtime::ClosedError` after `close`. A nested rebuild from the thread that already holds it — a command such as the Loader's `/reload`, or a hook at a quiet boundary — proceeds, since a rebuild swaps configuration rather than entering the turn. It returns `nil`.

## Capping the loop

`max_steps:` caps how many LLM steps one run may take (`nil` — the default — runs the loop without a limit). A run that hits the cap ends with `outcome.reason: :max_steps`; the model's partial output is still on the response.

```ruby
runtime = Riffer::Rig::Runtime.new('anthropic/claude-sonnet-4-6', max_steps: 8)
response = runtime.ask('do the thing')
puts response.outcome.reason # => :max_steps if the cap stopped the loop
```

The cap applies to each run. A turn the Runtime [continues for a job exit notice](#exit-notifications) starts a new run with its own cap, and no continuation starts once the turn's runs have together used the cap: the notice then arrives at the start of the next turn.

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

`on_message { |message| }` registers an observer called with each message the conversation gains, in order: the user's prompt, each assistant message, each tool result and each [job exit notification](#exit-notifications), as riffer's `Riffer::Messages` objects. It is how a store appends to a session as it happens rather than snapshotting at the end:

```ruby
runtime.on_message { |message| log.puts(JSON.generate(message.to_h)) }
```

Observers run on the prompting thread, inside the turn, once per message; they survive a model switch. The system message is not delivered — it is rebuilt every turn — nor are the "interrupted" results filled in after a cancel or on restore.

## Background jobs

A `bash` call with `run_in_background` starts a job that outlives the tool call and the turn that started it. The Runtime watches every job and reports its exit as it happens, whether or not a turn is running:

```ruby
exits = Queue.new
runtime.on_job_exit { |completion| exits << completion }
runtime.running_job_count # => 2
```

`on_job_exit { |completion| }` registers a subscriber called once per job, when the job exits: by itself, or on a signal such as `bash_kill`'s. The completion is a frozen `Riffer::Rig::Runtime::JobCompletion`:

| Reader        | Value                                                                                                          |
| ------------- | -------------------------------------------------------------------------------------------------------------- |
| `job_id`      | The id `bash` returned when it started the job                                                                 |
| `command`     | The shell command                                                                                              |
| `exit_status` | The exit status; `1` for a job ended by a signal                                                               |
| `duration`    | Seconds from start to exit, as a `Float`                                                                       |
| `output_path` | The file holding the job's output, or the most recent of it once it passes the [cap](TOOLS.md#background-jobs) |
| `tail`        | The last 2,000 bytes of that output, with invalid characters replaced                                          |

Subscribers run on a background thread, not the thread running the turn, and one at a time. Hand the completion to your own loop — push it onto a queue — rather than rendering, prompting or closing the Runtime from the block.

`running_job_count` is the number of jobs still running. It is thread-safe, and has already dropped by the time a subscriber hears of that job's exit.

### Waiting for jobs

A host whose model stops with jobs still running can wait for them on its own thread and give the model a turn for each exit, with no user text — what [headless](HEADLESS.md#background-jobs) does before it exits:

```ruby
runtime.prompt('run the three test suites in the background') { |event| render(event) }
while runtime.pending_jobs?
  break unless runtime.await_job_exit(timeout: 600)

  runtime.follow_up { |event| render(event) }
end
runtime.close
```

`pending_jobs?` is true while any job is running or has exited without the model being told of it yet, so a job that exits just as a turn ends is never missed. `await_job_exit(timeout:)` blocks until an exit is waiting to be told and returns `true`, or returns `false` once `timeout` seconds pass without one; it returns `true` at once when an exit is already waiting, and without a `timeout` it waits for as long as it takes. It neither delivers nor consumes the exit, it is safe to call from any thread, and `close` from another thread ends the wait at once.

`follow_up` runs a turn with no user text: it tells the model of every exit waiting to be told, as one [notification](#exit-notifications), and streams the model's reply exactly as `prompt` does — with a block it yields each event and returns `nil`, without one it returns an `Enumerator`. It is a turn like any other: one prompt or follow-up runs at a time, it ends with a `turn_end`, and it is [continued](#exit-notifications) for exits that land as the model finishes. With no exit waiting it does not call the model, and its `turn_end` has `stop_reason` `:completed`.

`pending_job_exit_count` is the number of exits the model has not been told of yet. It is thread-safe, and counts an exit by the time a subscriber hears of it — the [terminal](TERMINAL.md#background-jobs) reads it to announce an exit and start a `follow_up` the moment a job exits while it waits for input, and to skip one when a turn has told the model already.

`close` ends delivery: the jobs it kills, and any exit that lands after it, reach no subscriber. A host that swaps one Runtime for another closes the old one and subscribes on the new one. `close` also removes the output file of every job, so read what you need from an `output_path` first.

### Exit notifications

The model is told of each exit too, as part of the conversation, so it never polls for one ([Tools](TOOLS.md#background-jobs) has the notice it reads and the three points it can arrive at). The Runtime delivers a notice only on the thread running the turn, at a point where the session can change — never from the background thread a subscriber runs on — so a long reply or a long tool call delays it until the next such point.

Each delivery puts one `job_exit` event per job on the stream, before the message that carries the notice reaches `on_message`. It is the moment to render an exit in the transcript; `on_job_exit` is the one to keep a live count with, since it fires when the job exits rather than when the model is told.

`on_message` observers see every notice, because a store has to keep what the model read:

- A notice delivered during a turn is part of a tool result: the `Riffer::Messages::Tool` an observer receives holds the tool's output, a blank line, and the notice. The `result` on that call's `after_tool_call` event is the tool's output alone.
- A notice delivered as the model finishes its reply, ahead of the next prompt, or by a [follow-up](#waiting-for-jobs), is a `Riffer::Rig::Runtime::JobNotification` — a `Riffer::Messages::User`, so every provider serializes it as a user turn — whose `to_h` adds `job_notification: true`. The key is how anything reading stored messages tells a notice from a prompt the user typed. A [snapshot](#snapshots) restores a hash carrying it as a `JobNotification`. The notice a follow-up delivers opens a turn of its own rather than joining a prompt's, so its `to_h` also adds `follow_up_exits`, the number of exits it reports; `follow_up_exits` on the object returns it, and `nil` for any other notice.

A turn the Runtime continues for a notice is still one turn: one `turn_end`, whose `usage` and the `Riffer::Agent::Response` of `ask` cover every reply in it.
