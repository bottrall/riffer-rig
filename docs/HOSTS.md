# Hosts

A host receives questions and out-of-band messages from a `Riffer::Rig::Runtime`. The contract is the RBS interface `Riffer::Rig::Hosts::_Host`: a host is any object that implements every method below.

| Method                             | Purpose                                                     |
| ---------------------------------- | ----------------------------------------------------------- |
| `ask(question, options:, secret:)` | free text or a choice from `options`; `secret:` hides input |
| `confirm(question)`                | yes or no                                                   |
| `notify(message, level:)`          | out-of-band message; never enters the model's context       |
| `progress(label) { }`              | wraps slow work                                             |
| `capabilities`                     | the `Set` of methods the host truly supports                |

A host implements all five, including the ones it declines. `capabilities` is checked before asking, so a host that declines a capability is never asked and the caller takes the declined path.

```ruby
class MyHost
  def capabilities = Set[:notify].freeze
  def ask(question = nil, options: nil, secret: false) = nil
  def confirm(question = nil) = false
  def notify(message = nil, level: :info) = warn("[#{level}] #{message}")
  def progress(label = nil, &block) = block&.call
end
```

## The null host

`Riffer::Rig::Hosts::Null` is the do-nothing host and the Runtime's default: every capability is declined (`ask` returns `nil`, `confirm` returns `false`, `notify` is a no-op, `progress` yields).

## The mirror

The Runtime wraps the host it is given in a `Riffer::Rig::Hosts::Mirror`, which is what `runtime.host` returns. The mirror forwards every call to the wrapped host and queues a `notify` event for each `notify`, so a consumer of the event stream sees what the host saw.

## Writing a host

A host is two pieces: an object implementing `Riffer::Rig::Hosts::_Host`, which the Runtime asks and tells things out of band, and a loop that builds a Runtime and renders its event stream. The `riffer` terminal is the reference for both. Its loop is `Riffer::Rig::Terminal` (`lib/riffer/rig/terminal.rb`, with its presentation under `lib/riffer/rig/terminal/`), and its host object is `Riffer::Rig::Terminal::Host` (`lib/riffer/rig/terminal/host.rb`), which the loop holds as a collaborator rather than being the host itself. Keep your host object inside your host's own namespace, as the terminal does; `Riffer::Rig::Hosts` holds only the contract and the reusable `Null` and `Mirror`.

A host uses only the public API of the Runtime, the hosts, the Loader and the events. The terminal is held to that by a test: nothing under `Riffer::Rig::Terminal` names another `Riffer::Rig` constant. Anything a host needs beyond that becomes a Runtime or Loader feature, so embedders get it too.

### Building the Runtime

Build the Runtime with [`Loader.runtime`](EMBEDDING.md#building-a-runtime-with-the-loader), passing your host object as `host:`. Command-line flags are Loader keywords (`model:`, `extensions:`, `skills:`, `agents_md:`, `tools:`, `max_steps:`); a host translates its arguments into them and does nothing else with configuration. Onboarding and credential prompts reach the host through `ask` (with `secret: true` for a key), and only when `capabilities` includes `:ask`. `Riffer::Rig::Loader::ConfigurationError` carries a message written for the user: the terminal prints it and exits with status 1.

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

The terminal renders `TextDelta` as streamed prose, `ToolCallDone` as the call, `SkillActivation` and the rig `skill_activated` event as a skill line, `command_output` as a line of its own, and `Interrupt` as a note. `turn_end` carries the turn's `usage`, which the terminal prints with `runtime.tally` (every turn so far) and its `cost`. It skips the stream's `notify` events: the mirror queues one for each `host.notify`, which the terminal's host has already printed.

### Rendering markdown

`Riffer::Rig::Terminal::Markdown.render(source, theme:, width:)` turns markdown into the text a terminal prints, one `"\n"`-terminated line per row; the terminal does not route answers through it yet. It is a pure function: the `Theme` decides the styling and `width` is the columns available, or `nil` to leave lines unwrapped.

| Construct | Rendered as |
| --------- | ----------- |
| Headings (`#` to `######`) | bold and coloured, marks dropped |
| Paragraphs | lines joined and wrapped through the `Wrapper` |
| Bold, italic, inline code | the matching style, markers dropped |
| Links and images | the label as an OSC 8 hyperlink, underlined |
| Lists | `•` for unordered items, the source number for ordered ones, nested by indentation |
| Fenced code | the language as a label, then each line behind a `│` gutter |
| Block quotes | the quoted blocks behind a `┃` gutter |
| Horizontal rules | a line across the width |
| Tables | a plain grid: columns padded to their widest cell, a rule under the header |

A disabled theme (not a TTY, or `--no-color`) writes no escape sequence at all, and keeps what colour would have carried: a heading keeps its `#` marks, inline code keeps its backticks, and a link prints as `label (target)`.

The source is model output, so nothing in it reaches the terminal as an instruction. Control characters other than the newline are removed before parsing (a tab becomes four spaces), which leaves an escape sequence as inert text; HTML is printed as written; and a link becomes a hyperlink only when its target is `http`, `https` or `mailto` and made of printable ASCII, so it cannot end the OSC 8 sequence early. Any other target prints as `label (target)`. A source in another encoding is transcoded to UTF-8, and a byte that is not valid text becomes `�` rather than raising.

Width is counted in characters, as the `Wrapper` counts it. A code line longer than the width is cut rather than word-wrapped, because wrapping would fold its indentation. A table is not fitted to the width: a grid wider than the terminal overflows.

Four limits bound the work a source can ask for, and what exceeds one prints as text rather than being dropped. Whatever sits inside more than 16 nested quotes or list items prints as text. A table with more than 32 pipes on any line, or whose grid would be wider than 500 characters, prints as a paragraph instead of a grid. A bold or italic span, an inline code span, or a link label, longer than 1000 characters prints with its markers.

Left as written: setext headings, indented code blocks, reference-style links, hard line breaks, and strikethrough.

### The terminal's host

`Riffer::Rig::Terminal::Host` reports all four capabilities:

| Method     | In the terminal                                                                           |
| ---------- | ----------------------------------------------------------------------------------------- |
| `ask`      | prints the question and reads a line; `secret:` reads without echo; `options:` are numbered and a number picks one |
| `confirm`  | asks `[y/N]`; only an answer starting with `y` confirms                                    |
| `notify`   | prints the message as a line of its own, red for `level: :error`                           |
| `progress` | prints the label and runs the block under the spinner                                      |

The other two tiers follow the same shape. `Riffer::Rig::Headless::Host` reports `Set[:notify, :progress]` and prints both to stderr ([Headless](HEADLESS.md)). `Riffer::Rig::ACP::Host` reports `Set[:notify]`, turns `notify` into a `session/update` on the session it belongs to, and buffers the ones raised while the Runtime is still building ([ACP](ACP.md)).
