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

The constructor takes everything as keywords — `model:` (positional, required), `extensions:`, `tools:`, `settings:`, `host:`, `cwd:`, `name:`, `instructions:`, `max_steps:`. All except the model are optional. Keywords not yet honoured are accepted and documented as such: `pricing:` and `snapshot:` are accepted and ignored until their tickets land, and `settings:` is stored and exposed (`runtime.settings`) but nothing reads it yet. `pricing:` already takes the shape the Loader will pass — `Settings::Pricing` entries — so embedders building it today keep working when its ticket lands.

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
| `credentials:`  | provider → resolved credential values; see [Per-runtime credentials](#per-runtime-credentials) | `{}` |
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

## Per-runtime credentials

`credentials:` gives one Runtime its own provider keys: a hash keyed by provider identifier, each value a hash of that provider's resolved values. The Runtime never resolves them — no environment lookup, no `auth.json` — it stores the hash as given.

```ruby
alice = Riffer::Rig::Runtime.new('anthropic/claude-sonnet-4-6', credentials: { anthropic: { api_key: alice_key } })
bob = Riffer::Rig::Runtime.new('anthropic/claude-sonnet-4-6', credentials: { anthropic: { api_key: bob_key } })

[alice, bob].map { |runtime| Thread.new { runtime.ask('hello') } }.each(&:join)
```

While `prompt` or `ask` runs, the Runtime is current for the executing fiber. When riffer-rig loads it installs one Proc per built-in provider (`anthropic`, `openai`, `gemini`, `openrouter`, `azure_openai`, `amazon_bedrock`) into `Riffer.config.<provider>.client`; riffer resolves that Proc on every LLM call and gets a client built with the current Runtime's `api_key` (the bearer token, for Bedrock). Runtimes holding different keys prompt in parallel threads without seeing each other's. A blockless `prompt` enumerated externally with `.next` runs its body in its own fiber, so `Runtime.current` reads nil on the caller's side between `.next` calls even though the LLM call inside resolves the right Runtime. A Runtime builds each provider's client once and keeps it.

`Riffer.configure` remains the fallback a host may use at its edge. Where the current Runtime holds no `api_key` for a provider — or a riffer agent runs outside any Runtime — the client is built from `Riffer.config` exactly as riffer builds it: `api_key`, `base_url`, `endpoint`, `region`, `api_token` and the SDK's own environment variables all still apply. Non-secret values such as `base_url`, `endpoint` and `region` always come from `Riffer.config`.

```ruby
Riffer.configure { |config| config.openai.api_key = ENV.fetch('OPENAI_API_KEY') }

Riffer::Rig::Runtime.new('openai/gpt-5').ask('hello') # uses the configured key
```

A `client` the host sets on `Riffer.config.<provider>` before requiring `riffer/rig` is left in place, and that provider then ignores per-runtime credentials.

`Riffer::Rig.credentials(:identifier)` returns the current Runtime's values for one provider — `nil` outside a prompt, or when the Runtime holds none. An extension provider calls it when building its client:

```ruby
def build_client
  Acme::Client.new(api_key: Riffer::Rig.credentials(:acme)&.fetch(:api_key))
end
```

riffer keeps a provider's built client for the life of the provider instance, which is one Runtime's agent, so the key read there stays that Runtime's.

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

## Rig events

The stream a host consumes is riffer's `StreamEvents` unchanged, plus a few rig-level events from `Riffer::Rig::Events`. They are immutable `Data` value objects; each has `to_h` — with the type folded in, so a headless host can print every record verbatim as NDJSON — and `type`, the snake_case form of its class name.

| Rig event         | Carries                          | When                                                              |
| ----------------- | -------------------------------- | ----------------------------------------------------------------- |
| `session_start`   | `id`, `reason` (`:new`, `:restore`, `:reload`) | opens the first prompt after construction (or a restore, or a rebuild) |
| `session_end`     | `reason` (`:reload`, `:close`)   | on `close` (queued — see the note below) |
| `command_output`  | `command`, `text`                | a command called `ctx.say`                                        |
| `skill_activated` | `name`                           | a skill was activated by command                                  |
| `notify`          | `message`, `level`               | mirrors every `host.notify`, so a stream consumer sees extension errors too |
| `turn_end`        | `stop_reason`, `usage`, `cost`   | the last event of every `prompt`; `usage` is riffer's `TokenUsage` and `cost` its USD figure, `nil` when unpriced |

`session_start` and `session_end` currently carry reason `:new` and `:close` only — `:restore` and `:reload` arrive with the snapshot and rebuild tickets. `close` refuses further prompts and asks with `Riffer::Rig::Runtime::ClosedError`; `session_end` waits on the rebuild ticket, which owns the stream's session_end reasons.

Every `prompt` ends with `turn_end` — with a block or as an Enumerator — so a stream consumer never needs `ask` to learn how the turn ended and what it cost. The headless host prints this same stream as NDJSON; see [Headless mode](HEADLESS.md) for the wire shape.

## Capping the loop

`max_steps:` caps how many LLM steps one run may take (`nil` — the default — runs the loop without a limit). A run that hits the cap ends with `outcome.reason: :max_steps`; the model's partial output is still on the response.

```ruby
runtime = Riffer::Rig::Runtime.new('anthropic/claude-sonnet-4-6', max_steps: 8)
response = runtime.ask('do the thing')
puts response.outcome.reason # => :max_steps if the cap stopped the loop
```
