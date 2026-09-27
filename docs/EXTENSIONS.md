# Extensions

An extension is a named registrar block. Requiring a file records it; `Runtime.new` runs it against a fresh registrar of its own.

## The unit: a named registrar block

```ruby
Riffer::Rig.extension('git', requires: '>= 0.3') do |rig|
  rig.tool GitLog
end
```

`Riffer::Rig.extension(name, requires: nil) { |rig| }` records the block in a process-level registry keyed by name and returns the extension object. Re-executing the same file (a reload) replaces the block rather than appending a duplicate. `requires:` is a `Gem::Requirement` string checked against the riffer-rig version when the block is recorded; a mismatch raises `Riffer::ArgumentError`.

`Runtime.new(extensions: [...])` runs each block, in order, against a fresh registrar of its own and merges what they register. Two Runtimes never share tools or commands; per-Runtime state lives in the block's locals, per-process state lives outside the block. Same process, no sandbox.

## The `rig.tool` seam

```ruby
rig.tool klass
```

Adds a `Riffer::Tool` to the Runtime; its identifier is its name everywhere. When the extension block runs, the registrar collects the tool classes and the Runtime passes them to its agent. `tools:` on `Runtime.new` is an allowlist of tool identifiers over what extensions registered — `nil` (the default) means every registered tool.

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
| `settings`                              | this extension's namespace of the Runtime's `settings:` — `settings[:git]` for an extension named `git` — or `{}` when it has none |
| `say(text)`                             | emits a `command_output` event carrying the command's name and `text`                                  |
| `prompt(text)`                          | sends `text` to the model as a user turn, so a prompt template is a command; the turn's events stream to the caller of `run_command` |
| `ask(question, options: nil, secret: false)` | forwards to the host and returns its answer, or `nil` when the host does not support `:ask`       |
| `confirm(question)`                     | forwards to the host and returns its answer, or `false` when the host does not support `:confirm`      |

`ask` and `confirm` check `host.capabilities` first, so a host that declines them — the null host, headless — is never asked and the command takes the declined path.

A command runs synchronously, one at a time, under the same rule as `prompt`: `run_command` while a prompt or another command is running raises `Riffer::Rig::Runtime::BusyError`. A command that calls `ctx.runtime.prompt` or `ctx.runtime.ask` hits the same rule; `ctx.prompt` is the way to run a turn from a command. A command that raises is caught and reported through the host's `notify` at level `:error`, and the Runtime stays usable.

## Error isolation

The Runtime wraps each registrar block. A failure skips that extension; the rest load. Errors go to the host only, never into the model's context.
