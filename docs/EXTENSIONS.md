# Extensions

An extension is a named registrar block. Requiring a file records it; `Runtime.new` runs it against a fresh registrar of its own.

## The unit: a named registrar block

```ruby
Riffer::Rig.extension('git', requires: '>= 0.3') do |rig|
  rig.tool GitLog
end
```

`Riffer::Rig.extension(name, requires: nil) { |rig| }` records the block in a process-level registry keyed by name and returns the extension object. Re-executing the same file (a reload) replaces the block rather than appending a duplicate. `requires:` is a `Gem::Requirement` string checked against the riffer-rig version when the block is recorded; a mismatch does not raise but is a load error, reported when a Runtime loads the extension (see [Error isolation](#error-isolation)).

`Runtime.new(extensions: [...])` runs each block, in order, against a fresh registrar of its own and merges what they register. Two Runtimes never share tools or commands; per-Runtime state lives in the block's locals, per-process state lives outside the block. Same process, no sandbox.

## The `rig.tool` seam

```ruby
rig.tool klass
```

Adds a `Riffer::Tool` to the Runtime; its identifier is its name everywhere. When the extension block runs, the registrar collects the tool classes and the Runtime passes them to its agent. `tools:` on `Runtime.new` is an allowlist of tool identifiers over what extensions registered — `nil` (the default) means every registered tool. A later registration of the same identifier replaces the earlier tool and keeps its place in the list; that is how a user replaces a [bundled tool](TOOLS.md#replacing-a-tool).

## The `rig.prompt` seam

```ruby
rig.prompt(:git_status) { |ctx| "Branch: #{`git branch --show-current`}" }
```

Adds a named section to the system message. Sections render after the base prompt, in load order, and before the environment block; [Instructions](INSTRUCTIONS.md) shows the whole assembly.

- The block is evaluated at the start of every turn — each `prompt` or `ask` — so its content is always current without a reload. It receives the Runtime as `ctx` (`ctx.cwd`, `ctx.settings`, `ctx.host`) and returns the section's text.
- A later registration of the same name replaces the earlier block and keeps the earlier one's place in the order, so a user can swap a section an extension owns without disabling that extension.
- The text is appended as-is. A section that needs framing — a heading, a sentence saying whose instructions these are — writes that framing itself; the base prompt names no contributor. A section that returns `nil` or an empty string is left out of that turn's message.

## The `rig.command` seam

```ruby
rig.command('log', description: 'Recent commits') { |ctx| ctx.say `git log -n #{ctx.args} --oneline` }
rig.command('review', description: 'Review the diff') { |ctx| ctx.prompt "Review this diff:\n#{`git diff`}" }
```

Adds a slash command to the Runtime. Commands are runtime objects, not host features, so a command works the same in every host: the host lists them with `runtime.commands` and runs one with `runtime.run_command(name, args)` (see [Embedding](EMBEDDING.md#commands)). The name is given without the leading slash. A later registration of the same name — from the same extension or a later one — replaces the earlier command and keeps its place in the list.

The block receives a `ctx`:

| Member                                  | Does                                                                                                   |
| --------------------------------------- | ------------------------------------------------------------------------------------------------------ |
| `args`                                  | the text after the command name, as one string (`""` when there is none)                               |
| `runtime`                               | the Runtime running the command                                                                        |
| `host`                                  | the Runtime's host (the [mirror](HOSTS.md#the-mirror))                                                 |
| `settings`                              | this extension's namespace of the Runtime's settings — `settings[:git]` for an extension named `git`, with its [declared defaults](#the-rigsetting-seam) filled in — or `{}` when it has none |
| `say(text)`                             | emits a `command_output` event carrying the command's name and `text`                                  |
| `emit(event)`                           | emits a [rig event](EMBEDDING.md#rig-events), such as `Riffer::Rig::Events::SkillActivated`, to the caller of `run_command`; any object with `type` and `to_h` (`Riffer::Rig::Events::_Event`) qualifies, and including `Riffer::Rig::Support::Equatable` gives it equality by class and `to_h` |
| `prompt(text)`                          | sends `text` to the model as a user turn, so a prompt template is a command; the turn's events stream to the caller of `run_command` |
| `ask(question, options: nil, secret: false)` | forwards to the host and returns its answer, or `nil` when the host does not support `:ask`       |
| `confirm(question)`                     | forwards to the host and returns its answer, or `false` when the host does not support `:confirm`      |

`ask` and `confirm` check `host.capabilities` first, so a host that declines them — the null host, headless — is never asked and the command takes the declined path.

A command runs synchronously, one at a time, under the same rule as `prompt`: `run_command` while a prompt or another command is running raises `Riffer::Rig::Runtime::BusyError`. A command that calls `ctx.runtime.prompt` or `ctx.runtime.ask` hits the same rule; `ctx.prompt` is the way to run a turn from a command. A command that raises is caught and reported through the host's `notify` at level `:error`, and the Runtime stays usable.

## The `rig.on` seam

```ruby
rig.on(:before_tool_call) { |e| next :block, 'no force pushes' if e.tool == 'bash' && e.args[:command] =~ /push --force/ }
rig.on(:before_prompt) { |e| "#{e.text}\n\nAnswer in one paragraph." }
rig.on(:turn_end) { |e| warn "turn cost $#{e.cost}" if e.cost }
```

Adds a hook for one event of the Runtime's lifecycle or loop. The block receives the event object; every event is immutable, so a hook that wants to change something returns the change rather than mutating the event. Hooks for the same event run in load order — extension order, then registration order within an extension. An unknown event name raises `Riffer::ArgumentError` when the extension block runs.

| Event              | Kind        | The event carries                                  | Fires                                                                 |
| ------------------ | ----------- | -------------------------------------------------- | --------------------------------------------------------------------- |
| `session_start`    | lifecycle   | `id`, `reason` (`:new`, `:restore`, `:reload`)     | as the Runtime's first turn starts (`:new`, or `:restore` after a snapshot), and after a `rebuild` swaps this extension in (`:reload`) |
| `session_end`      | lifecycle   | `reason` (`:reload`, `:close`)                     | before a `rebuild` swaps this extension out (`:reload`), and on `close` (`:close`), if a session started |
| `before_prompt`    | vetoable    | `text`                                             | as each `prompt` or `ask` starts, before the text reaches the session |
| `before_request`   | vetoable    | `messages` (the whole request)                     | before every LLM call: at the start of the turn and again after each round of tool results |
| `before_tool_call` | vetoable    | `tool` (the identifier), `args` (symbol keys)      | before each tool runs                                                 |
| `after_tool_call`  | observe     | `tool`, `args` (as run), `result` (the tool's `Riffer::Tools::Response`) | after each tool runs                        |
| `after_response`   | observe     | `message` (the `Riffer::Messages::Assistant`)      | after each model response is added to the session                     |
| `turn_end`         | observe     | `stop_reason`, `usage`, `cost`                     | as each turn ends, `ask` included                                     |
| `stream`           | passthrough | the riffer `StreamEvent` itself                    | for every riffer stream event of a turn, `ask` included               |

Lifecycle hooks are where an extension acquires and releases process-wide state; `session_start` carries `:restore` on a Runtime built from a [snapshot](EMBEDDING.md#snapshots).

A vetoable hook may return:

- a replacement payload — a `String` for `before_prompt`, an args `Hash` for `before_tool_call`, an `Array` of `Riffer::Messages::Base` for `before_request`. The next hook receives an event built from it, and the last one wins. Any other return value (including `nil`) changes nothing.
- `:block`, or `[:block, reason]` (`next :block, 'reason'` inside the block). Later hooks do not run. A blocked tool call becomes a tool error carrying the reason (error type `:blocked`) that the model sees, and the turn carries on. A blocked prompt never reaches the model or the session, the host is told the reason through `notify` at level `:warning`, and the turn ends with stop reason `:guardrail_blocked`. A blocked request also notifies the host: at the start of the turn it ends the turn with `:guardrail_blocked`, and after tool results it interrupts the turn (`:interrupted`, the reason in the outcome's `detail`).

A replacement request is written back to the session, so later requests carry it too. A replacement tool payload changes what the tool runs with; the model's own tool call in the history is left as it sent it.

Observe and passthrough hooks change nothing: their return values are ignored, and a `stream` hook sees each riffer event unchanged, the same object the host receives.

Hooks run on the thread running the turn, one at a time — tools run sequentially so their hooks never overlap.

## The `rig.skills` seam

```ruby
rig.skills { |ctx| Riffer::Skills::FilesystemBackend.new(File.join(ctx.cwd, 'docs/skills')) }
```

Adds a source of [Agent Skills](SKILLS.md). The block receives the Runtime as `ctx`, as a prompt section's does, and returns a `Riffer::Skills::Backend`; it runs when the Runtime is built and again on every rebuild. Every source's skills join one catalog, the model's riffer skills catalog; when two sources have a skill of the same name, the earlier source wins. Each skill in the catalog gets a core [`skill:<name>` command](SKILLS.md#skillname). A Runtime with no source has no catalog.

## The `rig.mcp` seam

```ruby
rig.mcp 'tracker', url: 'https://tracker.example.com/mcp', headers: { 'Authorization' => 'Bearer …' }
```

Declares an HTTPS MCP server for the Runtime: `rig.mcp(name, url:, headers: {})`. The Runtime registers the server with riffer's MCP client, and the agent gets its tools as `<server>__<tool>`; a later declaration of the same name replaces the earlier one. [MCP](MCP.md) covers naming, why the `tools:` allowlist does not apply, failures, what a rebuild keeps and the same-name limit across Runtimes.

## Bundled extensions and replacement

The four tools ship as bundled extensions — `Riffer::Rig.bundled(:read)`, `:write`, `:edit`, `:bash` — and so do the `:agents_md` prompt section, `Riffer::Rig.bundled(:agents_md)`, the skills directories, `Riffer::Rig.bundled(:skills)`, and the MCP client, `Riffer::Rig.bundled(:mcp)`, all built on the same seams as any other extension; `Riffer::Rig.bundled` returns them all in load order. [Tools](TOOLS.md) describes the tools, [Instructions](INSTRUCTIONS.md#agentsmd) the AGENTS.md section, [Skills](SKILLS.md) the skills and [MCP](MCP.md) the MCP client.

A later extension replaces anything an earlier one registered by registering under the same name: a tool with the same identifier, a command with the same name, a prompt section with the same name, an MCP server with the same name. Later wins, and the Runtime reports each replacement across extensions through the host's `notify` at level `:info`, as "Extension LATER replaces KIND NAME from EARLIER". Nothing is deregistered, so the original extension is still there to pass to another Runtime.

## The `rig.setting` seam

```ruby
Riffer::Rig.extension('git') do |rig|
  rig.setting :depth, default: 3
  rig.command('log', description: 'Recent commits') { |ctx| ctx.say `git log -n #{ctx.settings[:depth]} --oneline` }
end
```

Declares a key under the extension's namespace of the settings: `"git": { "depth": 10 }` in `settings.json` (see [Configuration](CONFIGURATION.md#extension-namespaces)), read as `ctx.settings[:depth]`.

- When the Runtime's `settings:` hash lacks the key, the declared default applies; a provided value overrides it. `runtime.settings` holds the result, so a prompt section reads the same values through `ctx.settings[:git]`.
- A command's `ctx.settings` is its own extension's namespace only; core keys and other extensions' namespaces are not in it. Keys present in the namespace but never declared are passed through unchanged.
- `runtime.declared_settings` lists what each extension declared, extension name → key → default, so a host can render a table of them. Nothing else in core reads it.
- A later declaration of the same key replaces the earlier default.
- While the block runs, `rig.settings` is the same namespace — the Runtime's `settings:` values over the defaults declared so far — so an extension can register according to its settings.

Core settings keys stay top level, so an extension cannot take one as its name: an extension named `model`, `reasoning`, `models`, `reload`, `extensions`, `sessions`, `providers` or `tools` is rejected with a `Riffer::Rig::Registrar::NameCollisionError` before its block runs, and reported as a load error (see [Error isolation](#error-isolation)).

## Error isolation

The Runtime wraps each registrar block. A block that raises a `StandardError`, an extension whose `requires:` the running riffer-rig does not satisfy, or an extension named after a core settings key is a load error:

- The extension is skipped, including anything its block registered before it raised; the rest load, in order.
- `runtime.errors` records it as a `Riffer::Rig::Extension::Failure`, whose `extension` is the extension object and `error` the exception (a `Riffer::Rig::Extension::RequirementError` for an unmet `requires:`, a `Riffer::Rig::Registrar::NameCollisionError` for a core key taken as a name). An empty array means every extension loaded.
- The host gets one `notify` at level `:error`, `"Extension <name> failed to load: <message>"`, which the [mirror](HOSTS.md#the-mirror) also queues as a `notify` event for the next `prompt` or `run_command` to emit.

Errors go to the host only, never into the model's context.

At run time a hook that raises is caught and reported through the host's `notify` at level `:error` (`"before_tool_call hook failed: …"`), and the turn continues: the remaining hooks run, and a raising vetoable hook counts as no veto. Unlike a load error it is not recorded on `runtime.errors`. The `notify` event reaches the stream next to the event being handled.

## API versioning

The registrar surface — `Riffer::Rig.extension` and the `rig.*` seams — is public API of riffer-rig and follows its release policy (see [Releasing](../README.md#releasing)); there is no separate API number. While riffer-rig is 0.x, a breaking change to the surface ships in a minor release with a BREAKING CHANGES section in the changelog, after one minor of deprecation where feasible.

Pin the riffer-rig versions an extension is written against with `requires:`:

```ruby
Riffer::Rig.extension('git', requires: '~> 0.7') do |rig|
  # ...
end
```

A riffer-rig outside the requirement reports the extension as a load error rather than running its block.
