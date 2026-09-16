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

The constructor takes everything as keywords — `model:` (positional, required), `extensions:`, `tools:`, `settings:`, `host:`, `cwd:`, `name:`, `instructions:`, `max_steps:`. All except the model are optional. Keywords not yet honoured are accepted and documented as such: `credentials:`, `pricing:` and `snapshot:` are accepted and ignored until their tickets land, and `settings:` is stored and exposed (`runtime.settings`) but nothing reads it yet. `pricing:` and `credentials:` already take the shapes the Loader will pass — `Settings::Pricing` entries and plain key strings respectively — so embedders building them today keep working when their tickets land.

| Keyword         | Meaning                                                                     | Default                 |
| --------------- | --------------------------------------------------------------------------- | ----------------------- |
| `model`         | `"provider/name"`; required, positional                                     | —                       |
| `extensions:`   | ordered extension objects whose blocks run against this Runtime's registrar | `[]`                    |
| `tools:`        | allowlist of tool identifiers; `nil` means every registered tool            | `nil`                   |
| `settings:`     | merged settings hash, stored and exposed but not yet read                   | `{}`                    |
| `host:`         | an object implementing the [Host duck](HOSTS.md)                            | `Riffer::Rig::Host.new` |
| `cwd:`          | working directory for the environment block and for tools                   | `Dir.pwd`               |
| `name:`         | the name interpolated into the [base prompt](INSTRUCTIONS.md)               | `"riffer"`              |
| `instructions:` | replaces the base prompt wholesale (the environment block still applies)    | `nil` (use the base)    |
| `max_steps:`    | agent-loop step limit; `nil` runs the loop without a limit                  | `nil`                   |
| `credentials:`  | provider → resolved key string; accepted and ignored until per-runtime credentials land | `{}`       |
| `pricing:`      | model → `Riffer::Rig::Settings::Pricing` entries (USD per million tokens); accepted and ignored until the token tally moves behind the Runtime | `{}` |

Two Runtimes in one process share nothing but the process-wide extension registry and riffer's provider repository.

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

`ask(text)` runs one turn to completion and returns a `Riffer::Rig::Turn` — the same loop `prompt` streams, gathered into a single value. The headless host and embedders build on it; the terminal builds on the stream.

```ruby
turn = runtime.ask('Fix the failing test')
puts turn.text
turn.tool_calls.each { |call| puts "  #{call.name}(#{call.arguments})" }
puts "usage: #{turn.usage.input_tokens} in / #{turn.usage.output_tokens} out"
puts format('cost: $%.4f', turn.cost) if turn.cost
```

A `Turn` is a frozen value with:

| Reader       | Meaning                                                                    |
| ------------ | -------------------------------------------------------------------------- |
| `text`       | the assistant's final text for the turn                                    |
| `stop_reason`| one of the stop reasons below                                              |
| `tool_calls` | every tool call the model made this turn — `id`, `name`, `arguments`       |
| `usage`      | the run's `Riffer::Providers::TokenUsage` (nil when the provider reports none) |
| `cost`       | the priced cost of the run; nil until pricing moves behind the Runtime    |

Stop reasons are the provider's finish reasons that can end a turn plus the loop's own `max_steps` (the step limit was reached) and the rig's `cancelled` (produced by a future ticket); anything else riffer reports about a run surfaces as `error`:

`stop`, `length`, `context_window`, `content_filter`, `malformed_output`, `max_steps`, `cancelled`, `error`.

Hosts map them to exit codes or UI; the Runtime only reports them on the `Turn`.

## Capping the loop

`max_steps:` caps how many LLM steps one turn may take (`nil` — the default — runs the loop without a limit). A turn that hits the cap ends with `stop_reason: :max_steps`; the model's partial output is still on the `Turn`.

```ruby
runtime = Riffer::Rig::Runtime.new('anthropic/claude-sonnet-4-6', max_steps: 8)
turn = runtime.ask('do the thing')
puts turn.stop_reason # => :max_steps if the cap stopped the loop
```
