# Hosts

A host receives questions and out-of-band messages from a `Riffer::Rig::Runtime`. The contract is the RBS interface `Riffer::Rig::Hosts::_Host`: a host is any object that implements every method below.

| Method                             | Purpose                                                     |
| ---------------------------------- | ----------------------------------------------------------- |
| `ask(question, options:, secret:)` | free text or a choice from `options`; `secret:` hides input |
| `confirm(question)`                | yes or no                                                   |
| `notify(message, level:)`          | out-of-band message; never enters the model's context       |
| `progress(label) { }`              | wraps slow work                                             |
| `capabilities`                     | the `Set` of methods the host truly supports                |

A host implements all five, including the ones it declines. Whoever calls `ask` or `confirm` checks `capabilities` first, so a host that declines one is never asked and the caller takes the declined path. `progress` is always called, because its block is the work.

A host that cannot interact includes `Riffer::Rig::Hosts::NonInteractive`, which supplies the declines (`ask` returns `nil`, `confirm` returns `false`, `progress` yields), and leaves `:ask` and `:confirm` out of its `capabilities`. A method the host defines itself replaces the mixin's.

```ruby
class MyHost
  include Riffer::Rig::Hosts::NonInteractive

  def capabilities = Set[:notify].freeze
  def notify(message = nil, level: :info) = warn("[#{level}] #{message}")
end
```

## The null host

`Riffer::Rig::Hosts::Null` is the do-nothing host and the Runtime's default: every capability is declined (`NonInteractive` declines `ask`, `confirm` and `progress`, and `notify` is a no-op).

## The mirror

The Runtime wraps the host it is given in a `Riffer::Rig::Hosts::Mirror`, which is what `runtime.host` returns. The mirror forwards every call to the wrapped host and queues a `notify` event for each `notify`, so a consumer of the event stream sees what the host saw.

## Writing a host

A host is two pieces: an object implementing `Riffer::Rig::Hosts::_Host`, which the Runtime asks and tells things out of band, and a loop that builds a Runtime and renders its event stream. The `riffer` terminal is the reference for both. Its loop is `Riffer::Rig::Terminal` (`lib/riffer/rig/terminal.rb`, with its presentation under `lib/riffer/rig/terminal/`), and its host object is `Riffer::Rig::Terminal::Host` (`lib/riffer/rig/terminal/host.rb`), which the loop holds as a collaborator rather than being the host itself. Keep your host object inside your host's own namespace, as the terminal does; `Riffer::Rig::Hosts` holds only the contract and the reusable `NonInteractive`, `Null` and `Mirror`.

A host uses only the public API of the Runtime, the hosts, the Loader and the events. The terminal is held to that by a test: nothing under `Riffer::Rig::Terminal` names another `Riffer::Rig` constant. Anything a host needs beyond that becomes a Runtime or Loader feature, so embedders get it too.

### Building the Runtime

Build the Runtime with [`Loader.runtime`](EMBEDDING.md#building-a-runtime-with-the-loader), passing your host object as `host:`. Command-line flags are Loader keywords (`model:`, `extensions:`, `skills:`, `agents_md:`, `tools:`, `max_steps:`); a host translates its arguments into them and does nothing else with configuration. Onboarding and credential prompts reach the host through `ask` (with `secret: true` for a key), and only when `capabilities` includes `:ask`; the offer to install a provider's SDK gem reaches it through `confirm`, and only when `capabilities` includes `:confirm`. `Riffer::Rig::Loader::ConfigurationError` carries a message written for the user: the terminal prints it and exits with status 1.

```ruby
host = MyHost.new
runtime = Riffer::Rig::Loader.runtime(cwd: Dir.pwd, host: host, model: 'anthropic/claude-sonnet-4-6', skills: false)
```

### Driving it

- A line of text is `runtime.prompt(text) { |event| ... }`, which yields riffer's `StreamEvents` and rig's events as the turn runs.
- A line starting with `/` is `runtime.run_command(name, args) { |event| ... }`; the names come from `runtime.commands`. An unknown name is reported through the host's `notify`, so a host needs no list of its own. Only commands that end or replace the Runtime stay in the host: the terminal's are `/exit` and `/quit`.
- `runtime.cancel` stops the running turn at the next message boundary; the terminal calls it on Ctrl-C (from a thread, since the cancel flag takes a lock that Ruby refuses inside a signal handler). The turn ends with riffer's `Interrupt` event and a `turn_end` whose `stop_reason` is `:cancelled`.
- `runtime.on_message` delivers each message as the session records it; the terminal renders tool results from it.
- `runtime.close` when the session ends.

### Rendering the stream

The terminal renders `TextDelta` as streamed prose, `ToolCallDone` as the call, `SkillActivation` and the rig `skill_activated` event as a skill line, `command_output` as a line of its own, and `Interrupt` as a note. `turn_end` carries the turn's `usage`, which the terminal prints with `runtime.tally` (every turn so far) and its `cost`. It skips the stream's `notify` events: the mirror queues one for each `host.notify`, which the terminal's host has already printed. It also renders nothing for the stream's [`before_tool_call` and `after_tool_call`](EMBEDDING.md#tool-call-events) events — it draws each tool result from `runtime.on_message`; headless prints them as NDJSON records, and ACP turns `after_tool_call` into the call's completing `tool_call_update`. A host that matches on the events it knows and ignores the rest needs no change when the stream grows.

### The terminal's host

`Riffer::Rig::Terminal::Host` reports all four capabilities:

| Method     | In the terminal                                                                           |
| ---------- | ----------------------------------------------------------------------------------------- |
| `ask`      | prints the question and reads a line; `secret:` reads without echo; `options:` are numbered and a number picks one |
| `confirm`  | asks `[y/N]`; only an answer starting with `y` confirms                                    |
| `notify`   | prints the message as a line of its own, red for `level: :error`                           |
| `progress` | prints the label and runs the block under the spinner                                      |

The other two tiers follow the same shape and include `NonInteractive`. `Riffer::Rig::Headless::Host` reports `Set[:notify, :progress]` and prints both to stderr ([Headless](HEADLESS.md)). `Riffer::Rig::ACP::Host` reports `Set[:notify]`, turns `notify` into a `session/update` on the session it belongs to, and buffers the ones raised while the Runtime is still building ([ACP](ACP.md)). Built with `relay: true` it also reports `:ask` and `:confirm` once the client knows its session, and [relays both to the client](ACP.md#relaying-questions-to-the-client).
