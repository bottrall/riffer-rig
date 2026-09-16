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

How the run ended is riffer's `response.outcome` — `reason` is one of riffer's vocabulary (`completed`, provider finish reasons like `length` and `content_filter`, `max_steps`, `guardrail_blocked`, `interrupted`, …) and `detail` carries the specifics, such as the interrupt reason behind `:interrupted`. A future cancel will end runs the same way until #110 gives `cancelled` a vocabulary entry upstream. Hosts map `outcome.reason` to exit codes or UI.

## Capping the loop

`max_steps:` caps how many LLM steps one run may take (`nil` — the default — runs the loop without a limit). A run that hits the cap ends with `outcome.reason: :max_steps`; the model's partial output is still on the response.

```ruby
runtime = Riffer::Rig::Runtime.new('anthropic/claude-sonnet-4-6', max_steps: 8)
response = runtime.ask('do the thing')
puts response.outcome.reason # => :max_steps if the cap stopped the loop
```
