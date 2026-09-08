# Embedding riffer-rig

Host riffer-rig inside another Ruby process with `Riffer::Rig::Session` — a runtime that builds its own `Riffer::Agent` from a per-instance `Riffer::Agent::Config`, runs extension blocks against a per-Session registrar, and streams a prompt. It never renders, never prints, and never reads the filesystem; anything a host needs is a Session feature so embedders get it too.

## Constructing a Session

```ruby
session = Riffer::Rig::Session.new(
  'anthropic/claude-sonnet-4-6',
  extensions: [Riffer::Rig.extension('my_ext') { |rig| rig.tool MyTool }],
  host: MyHost.new,
)
```

The constructor takes everything as keywords — `model:` (positional, required), `extensions:`, `tools:`, `settings:`, `host:`, `cwd:`, `name:`, `instructions:`. All except the model are optional. Keywords not yet honoured are accepted and documented as such: `credentials:`, `pricing:`, `max_steps:` and `snapshot:` are accepted and ignored until their tickets land, and `settings:` is stored and exposed (`session.settings`) but nothing reads it yet.

| Keyword         | Meaning                                                                     | Default                 |
| --------------- | --------------------------------------------------------------------------- | ----------------------- |
| `model`         | `"provider/name"`; required, positional                                     | —                       |
| `extensions:`   | ordered extension objects whose blocks run against this Session's registrar | `[]`                    |
| `tools:`        | allowlist of tool identifiers; `nil` means every registered tool            | `nil`                   |
| `settings:`     | merged settings hash, stored and exposed but not yet read                   | `{}`                    |
| `host:`         | an object implementing the [Host duck](HOSTS.md)                            | `Riffer::Rig::Host.new` |
| `cwd:`          | working directory for the environment block and for tools                   | `Dir.pwd`               |
| `name:`         | the name interpolated into the [base prompt](INSTRUCTIONS.md)               | `"riffer"`              |
| `instructions:` | replaces the base prompt wholesale (the environment block still applies)    | `nil` (use the base)    |
| `credentials:`  | accepted and ignored until per-session credentials land                     | `{}`                    |
| `pricing:`      | accepted and ignored until the token tally moves behind the Session         | `{}`                    |
| `max_steps:`    | accepted and ignored until it maps to riffer's `config.max_steps`           | `nil`                   |
| `snapshot:`     | accepted and ignored until session persistence lands                        | `nil`                   |

Two Sessions in one process share nothing but the process-wide extension registry and riffer's provider repository.

## Prompting

`prompt(text)` runs one turn on the calling thread. With a block it yields every riffer `StreamEvent` as it happens; without one it returns an `Enumerator`:

```ruby
session.prompt('Explain this repository') do |event|
  case event
  when Riffer::StreamEvents::TextDelta then print event.content
  when Riffer::StreamEvents::ToolCallDone then puts "\n[tool: #{event.name}]"
  end
end

session.prompt('and this one?').each { |event| ... }
```

One prompt runs at a time per Session; a second while one is running raises `Riffer::Rig::Session::BusyError`. Parallelism means more Sessions, in more threads.
