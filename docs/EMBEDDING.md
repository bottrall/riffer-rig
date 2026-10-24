# Embedding riffer-rig

`Riffer::Rig::Runtime` runs the agent inside any Ruby process. It never prints, never reads the filesystem and assumes no terminal: everything the shipped hosts can do goes through the same API described here.

There are two ways to get one:

- **`Loader.runtime`** builds it from riffer-rig's files on disk — settings, credentials, `rig.rb`, skills, saved sessions — exactly as the terminal does.
- **`Runtime.new`** takes everything as arguments, for an app that keeps its configuration elsewhere.

## Building a Runtime with the Loader

```ruby
runtime = Riffer::Rig::Loader.runtime(cwd: Dir.pwd, host: MyHost.new)
```

The Loader reads the [settings](CONFIGURATION.md), picks the [model](CONFIGURATION.md#where-each-value-comes-from), ensures its [SDK gem](PROVIDERS.md#sdk-gems), resolves its [credentials](CONFIGURATION.md#where-each-value-comes-from), loads the bundled extensions and the [`rig.rb` files](EXTENSIONS.md#the-rigrb-files), and builds the Runtime. It also adds the `/reload` command, `/trace` when the session is saved, and [automatic reloading](RELOADING.md).

| Keyword             | Meaning                                                                                     | Default |
| ------------------- | ------------------------------------------------------------------------------------------- | ------- |
| `cwd:`              | the working directory; its `.riffer/settings.json` is the project scope                     | required |
| `host:`             | the [host](HOSTS.md): it receives notices, and questions such as a missing credential        | required |
| `options:`          | a [`Loader::Options`](#loader-options): the choices command-line flags make                 | `Loader::Options.new` |
| `store:`            | the [session store](STORES.md) that saves the session; `nil` saves nothing                  | `Stores::JSONL.new(home: home)` |
| `snapshot:`         | a [snapshot](#snapshots) to resume from                                                     | `nil` |
| `reload:`           | `:manual` turns off automatic reloading for this build                                      | the `reload` setting |
| `extra_extensions:` | extensions to load after the bundle and the `rig.rb` files, kept across reloads              | `[]` |
| `env:`              | the environment to read, as `Riffer::Rig::Env.load` returns it ([below](#credentials))      | `Riffer::Rig::Env.load` |
| `home:`             | the directory whose `.riffer/` holds the home files                                          | `Dir.home` |
| `riffer_config:`    | the `Riffer::Config` that receives credentials and catalog files                            | `Riffer.config` |

`Riffer::Rig::Loader.new(cwd:, host:, env:, home:, riffer_config:, store:)` keeps the Loader around: build with `runtime(options, reload:, extra_extensions:, snapshot:)`, reload with `reload(runtime, force: false)`, and find saved sessions with the [store methods](STORES.md#finding-sessions).

The host is asked only when its `capabilities` include `:ask`. Anything the Loader can't settle raises `Riffer::Rig::Loader::ConfigurationError`, whose message is written for the user: no model and no way to ask, an unknown provider, an invalid `RIFFER_MODEL` or reasoning level, a missing credential or SDK gem, or a settings or `auth.json` file that doesn't parse.

```ruby
begin
  runtime = Riffer::Rig::Loader.runtime(cwd: Dir.pwd, host: Riffer::Rig::Hosts::Null.new)
rescue Riffer::Rig::Loader::ConfigurationError => e
  warn e.message
  exit 2
end
```

### Loader options

```ruby
options = Riffer::Rig::Loader::Options.new(model: 'anthropic/claude-sonnet-4-6', skills: false)
runtime = Riffer::Rig::Loader.runtime(cwd: Dir.pwd, host: MyHost.new, options: options)
```

Every keyword is optional, and each matches a [command-line flag](CLI.md#flags):

| Keyword             | Meaning                                                              | Default |
| ------------------- | -------------------------------------------------------------------- | ------- |
| `model:`            | `"provider/name"`, over every other source                           | `nil`   |
| `reasoning:`        | the reasoning level, over every other source                         | `nil`   |
| `extensions: false` | skips the `rig.rb` files and gem autoload; bundled extensions still load | `true` |
| `skills: false`     | leaves out [skills](SKILLS.md)                                       | `true`  |
| `agents_md: false`  | leaves out [AGENTS.md](INSTRUCTIONS.md#agentsmd)                     | `true`  |
| `tools:`            | the [tool allowlist](TOOLS.md#identifiers)                           | `nil`   |
| `max_steps:`        | the [step limit](#capping-the-loop)                                  | `nil`   |

## Constructing a Runtime

```ruby
runtime = Riffer::Rig::Runtime.new(
  'anthropic/claude-sonnet-4-6',
  extensions: [*Riffer::Rig.bundled, Riffer::Rig.extension('my_ext') { |rig| rig.tool MyTool }],
  host: MyHost.new,
)
```

The model is positional; everything else is an optional keyword. Provider credentials reach riffer through `Riffer.config`, one set per process: resolve them with [`Credentials.install`](#credentials), or set them yourself with `Riffer.configure`.

| Keyword          | Meaning                                                                                      | Default |
| ---------------- | -------------------------------------------------------------------------------------------- | ------- |
| `extensions:`    | the extensions to run, in order; `Riffer::Rig.bundled` returns the [bundled ones](EXTENSIONS.md#bundled-extensions-and-replacement), and `Riffer::Rig.bundled(:read)` one of them | `[]` |
| `tools:`         | the [tool allowlist](TOOLS.md#identifiers); `nil` allows every tool                          | `nil`   |
| `settings:`      | the merged settings, with symbol keys: `{ model: '…', git: { depth: 10 } }`                  | `{}`    |
| `host:`          | the [host](HOSTS.md)                                                                         | `Riffer::Rig::Hosts::Null.new` |
| `cwd:`           | the working directory tools and the environment block use                                    | `Dir.pwd` |
| `name:`          | the agent's name in the [base prompt](INSTRUCTIONS.md#changing-the-base-prompt)              | `"riffer"` |
| `instructions:`  | replaces the base prompt                                                                     | `nil`   |
| `max_steps:`     | the [step limit](#capping-the-loop)                                                          | `nil`   |
| `reasoning:`     | the reasoning level ([Configuration](CONFIGURATION.md#reasoning))                            | `nil`   |
| `model_options:` | riffer `model_options` sent with every model call; `Riffer::Rig::Settings::ModelOptions.model_options(model)` builds the ones the Loader uses | `{}` |
| `native_tools:`  | the [provider-native tool](TOOLS.md#provider-native-tools) switches: `{ web_search: true }`  | `{}`    |
| `credentials:`   | each provider's resolved values, `{ anthropic: { api_key: '…' } }`, used by `/model` and when [restoring](#snapshots) | `{}` |
| `env:`, `auth_path:` | where [MCP `auth` fields](MCP.md#secret-headers) are read from and stored                | `Env.new`, `~/.riffer/auth.json` |
| `riffer_config:` | the `Riffer::Config` the agent reads its catalog and reasoning from                          | `Riffer.config` |
| `mcp_registry:`  | where MCP servers are registered                                                             | `Riffer::Mcp` |
| `clock:`         | a callable returning seconds, which stamps [tool call events](EVENTS.md#tool-call-events)    | the monotonic clock |
| `snapshot:`      | a [snapshot](#snapshots) to restore                                                          | `nil`   |

`runtime.settings` is the `settings:` hash with each extension's declared defaults filled in, and `runtime.declared_settings` lists what each extension declared, for a host to display. `runtime.errors` lists the extensions that [failed to load](EXTENSIONS.md#error-isolation).

Two Runtimes in one process share only the extension registry, riffer's providers and its config — so they share one set of provider credentials.

## Prompting

`prompt(text)` runs one turn on the calling thread. With a block it yields each [event](EVENTS.md) as it happens; without one it returns an `Enumerator`:

```ruby
runtime.prompt('Explain this repository') do |event|
  case event
  when Riffer::StreamEvents::TextDelta then print event.content
  when Riffer::StreamEvents::ToolCallDone then puts "\n[tool: #{event.name}]"
  end
end
```

`ask(text)` runs a turn to completion and returns riffer's `Riffer::Agent::Response`:

```ruby
response = runtime.ask('Fix the failing test')
puts response.content
puts response.outcome.reason      # :completed, :max_steps, :length, :interrupted, …
puts response.token_usage&.cost   # this turn, in USD, when priced
```

One turn runs at a time per Runtime: a second `prompt`, `ask`, command or rebuild while one runs raises `Riffer::Rig::Runtime::BusyError`, and `busy?` tells another thread whether one is running. For parallel work, use more Runtimes in more threads.

## Token tally and cost

riffer prices each model call from the [catalog](CONFIGURATION.md#catalog_files). `tally` is the Runtime's running total, a riffer `TokenUsage`, or `nil` before the first turn:

```ruby
Riffer.config.catalog_files = ['catalog.json']
runtime.ask('Fix the failing test').token_usage.cost # => this turn, in USD
runtime.tally.cost                                    # => every turn so far
```

Cache reads and writes count inside `input_tokens` and are priced at their own rates. A model with no catalog entry has a `cost` of `nil`, never zero. The Loader sets `catalog_files` from the settings; without the Loader, set it before the first request.

The `cost` command shows the tally, then each turn:

```text
session   ↑4100 · ↓132 · cache_write:900 · cache_read:900 · ~$0.0109
turn 1    ↑2600 · ↓120 · cache_write:900 · cache_read:900 · ~$0.0063
turn 2    ↑1500 · ↓12 · ~$0.0046
```

## Cancelling a turn

`cancel` stops the running turn. Call it from another thread — a UI thread, a request handler — while `prompt` or `ask` blocks; it returns at once, and the turn ends on its own thread.

```ruby
turn = Thread.new { runtime.prompt('refactor everything') { |event| render(event) } }
runtime.cancel
turn.join
```

A streaming reply stops at once and keeps the text it had reached. A running tool call finishes first, except the bundled `bash`, which kills its command; your own tool can check `context[:cancel_flag].set?` to do the same. The turn ends with `turn_end` and `stop_reason: :cancelled` (from `ask`, `outcome.reason` is `:interrupted` with `detail: "cancelled"`), and the next prompt carries on from there. [Background jobs](#background-jobs) keep running. With no turn running, `cancel` does nothing.

## Commands

Slash commands belong to the Runtime, so they work the same in every host. `commands` lists them — the Loader's `reload` and `trace`, the core `auth`, `model`, `reasoning` and `cost`, one `skill:<name>` per skill, and extensions' commands — each with a `name` (no slash) and a `description`.

`run_command(name, args)` runs one on the calling thread and yields its events: `command_output` for each `ctx.say`, a whole turn's events if the command starts one, and `notify` for anything reported. An unknown name, or a command that raises, is reported through the host and never raises from `run_command`.

```ruby
runtime.run_command('log', '5') do |event|
  case event
  when Riffer::Rig::Events::CommandOutput then puts event.text
  when Riffer::StreamEvents::TextDelta then print event.content
  when Riffer::Rig::Events::Notify then warn event.message
  end
end
```

`/exit`, `/new`, `/resume` and `/help` are the terminal's own: they end, replace or describe the Runtime, so a host implements them itself.

## Switching the model and reasoning level

```ruby
runtime.model = 'openai/gpt-5'
runtime.reasoning = 'low'
```

Both apply from the next model call and keep the conversation, tally and tools. An invalid value raises `Riffer::ArgumentError` and changes nothing. The `model` command does more than the setter: it ensures the provider's SDK gem and credentials first, refusing the switch if either is missing ([Configuration](CONFIGURATION.md#model)).

## Rebuilding after a code reload

`rebuild(extensions:, settings:)` replaces everything the extensions registered with what a new extension list registers. The Loader's `/reload` uses it; an app with its own code reloading calls it directly:

```ruby
Rails.application.reloader.to_prepare do
  runtime.rebuild(extensions: [*Riffer::Rig.bundled, MyApp.rig_extension], settings: MyApp.rig_settings)
end
```

The new extensions are loaded aside and swapped in only when all of them succeed. If any fails, `rebuild` raises its error and nothing changes — stricter than construction, which skips a failing extension. The conversation, tally, id, host, any model or reasoning switch and every other constructor keyword are kept. Extensions' `session_end` and `session_start` hooks run around the swap with reason `:reload`. `rebuild` runs between turns, or from a command or hook within one.

## Capping the loop

```ruby
runtime = Riffer::Rig::Runtime.new('anthropic/claude-sonnet-4-6', max_steps: 8)
runtime.ask('do the thing').outcome.reason # => :max_steps if the cap stopped it
```

`max_steps:` caps the model calls in one run. The model's partial output stays on the response. A turn continued for a [background job](#background-jobs) starts a new run with its own cap, but the turn isn't continued once its runs have used the cap between them.

## Snapshots

A Runtime saves to and restores from a plain hash. Storing it is up to you:

```ruby
File.write('session.json', JSON.generate(runtime.to_h))

snapshot = JSON.parse(File.read('session.json'), symbolize_names: true)
runtime = Riffer::Rig::Runtime.new('anthropic/claude-sonnet-4-6', extensions: Riffer::Rig.bundled, credentials: credentials, snapshot: snapshot)
```

| Key          | Holds                                                                                          |
| ------------ | ---------------------------------------------------------------------------------------------- |
| `:id`        | the session id, kept by the restored Runtime                                                   |
| `:messages`  | the conversation as riffer message hashes, system message first                                |
| `:model`     | a model switched to with `model=` or `/model`, or `nil`                                         |
| `:reasoning` | the reasoning level in effect, or `nil`                                                        |
| `:skills`    | the skills the model activated                                                                 |

A snapshot holds history, not configuration: tools, commands, hooks and settings come from the `extensions:` and `settings:` given when restoring. Nothing in a snapshot blocks a restore:

- a call to a tool that no longer exists is just history;
- tool calls left without a result by a crash get an "interrupted" error and are never run;
- a saved model is used only if `credentials:` has its provider, otherwise the given model is used and the host is told;
- skills that no longer exist are dropped;
- the tally is recomputed from the messages.

The first prompt after a restore opens with `session_start` and reason `:restore`.

## Observing messages

```ruby
runtime.on_message { |message| log.puts(JSON.generate(message.to_h)) }
```

`on_message` calls the block with each message the conversation gains — your prompt, each assistant reply, each tool result, each [background job notice](#background-jobs) — as riffer `Riffer::Messages` objects, on the turn's thread. This is how a store saves a session as it happens. The system message is not delivered, since it is rebuilt every turn.

## Background jobs

[Tools](TOOLS.md#background-jobs) describes jobs from the model's side. A host has two ways to follow them:

```ruby
runtime.on_job_exit { |completion| exits << completion }  # as each job exits
runtime.running_job_count                                  # => 2
```

`on_job_exit` runs on a background thread, once per job, the moment it exits. Push the completion onto a queue rather than rendering or prompting from the block. The completion is a frozen `Riffer::Rig::Runtime::JobCompletion` with `job_id`, `command`, `exit_status` (`nil` if a signal ended it), `signal` (such as `"TERM"`), `duration`, `output_path` and `tail` (the last 2,000 bytes).

The stream's [`job_exit`](EVENTS.md#rig-events) event marks the later moment the model is told, on the turn's thread.

### Waiting for jobs

A host whose model stops with jobs still running can wait and give the model a turn for each exit, as [headless](HEADLESS.md#background-jobs) does:

```ruby
runtime.prompt('run the three test suites in the background') { |event| render(event) }
while runtime.pending_jobs?
  break unless runtime.await_job_exit(timeout: 600)

  runtime.follow_up { |event| render(event) }
end
runtime.close
```

| Method                      | Does                                                                                      |
| --------------------------- | ----------------------------------------------------------------------------------------- |
| `pending_jobs?`             | true while a job runs or has exited without the model being told                         |
| `pending_job_exit_count`    | the exits the model hasn't been told of yet                                               |
| `await_job_exit(timeout:)`  | blocks until an exit is waiting (`true`) or the timeout passes (`false`); `close` ends it |
| `follow_up`                 | runs a turn with no user text that tells the model of every waiting exit, streaming like `prompt` |
| `close`                     | kills running jobs, deletes their output files, and refuses further prompts              |

### Job notices in the conversation

A store sees every notice the model read, through `on_message`. A notice delivered mid-turn is part of a tool result. One delivered as its own message is a `Riffer::Rig::Runtime::JobNotification`, a user-role message whose `to_h` adds `job_notification: true`, so anything reading saved messages can tell it from a prompt someone typed; one delivered by `follow_up` also carries `follow_up_exits`, the number of exits it reports. A snapshot restores these as `JobNotification`s.

## Credentials

`Riffer::Rig::Credentials` resolves provider credentials the way the Loader does, for an app that builds its Runtime directly:

```ruby
resolution = Riffer::Rig::Credentials.install(:azure_openai, host: host)
resolution.values  # => { endpoint: "https://…", api_key: "…" }
resolution.missing # => []
```

| Method                       | Does                                                                                     |
| ---------------------------- | ---------------------------------------------------------------------------------------- |
| `install(identifier, host:)` | resolves every field in [order](CONFIGURATION.md#where-each-value-comes-from), asking the host if it can, and applies them once none is missing |
| `apply(identifier, values)`  | assigns values from elsewhere to `Riffer.config`                                          |
| `store(identifier, values)`  | saves secrets to `auth.json` and plain values to settings                                |
| `remove(identifier)`         | deletes what `store` saved                                                               |
| `status(identifier)`         | `:env`, `:stored`, `:chain` or `:missing`                                                |

A file that doesn't parse comes back as a `String` message in place of the result. `install` runs `!command` values every time, so call it once and keep the result.

riffer-rig reads the process environment only through a `Riffer::Rig::Env`: `Env.new` snapshots it, and `Env.new('ANTHROPIC_API_KEY' => '…')` builds one from a hash for tests.
