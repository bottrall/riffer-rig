# Sessions

A session is one conversation with a `Riffer::Rig::Runtime`: its id, its history and the choices made during it. The Runtime can save a session as a plain hash and carry on from one ([below](#what-a-snapshot-holds)); the Loader stores every session it builds as it runs, one JSONL file per session under `~/.riffer/sessions/`, and picks one to resume ([below](#resuming)). An embedder without the Loader reads the entries directly or keeps snapshots itself ([Embedding](EMBEDDING.md#snapshots)).

## The session store

The Loader appends to a store: any object implementing the four `Riffer::Rig::Stores::_Store` methods — `append(id, entry)`, `read(id)`, `list(cwd: nil)` and `delete(id)`. Entries cross the store as typed POROs — `Stores::Header`, `Stores::MessageEntry`, `Stores::ModelEntry` and `Stores::SkillEntry` — and each store serialises them itself; `Hash` remains only where it is already the documented currency, the JSON lines on disk and the riffer message payloads. The store defaults to `Stores::JSONL` and is taken per build with `store:`; a Rails host implements the four over its own tables and passes its own. Hosts never see the store — they only choose which session to drive.

## Where sessions live

`Stores::JSONL` writes one file per session at `~/.riffer/sessions/<cwd-slug>/<session id>.jsonl`, one entry per line, so `cat` and `jq` work and a crash loses at most one line. The slug is the cwd with every run of characters outside alphanumerics, `.`, `_` and `-` collapsed to a single hyphen; it groups a project's sessions so listing is a directory read, but the `cwd` in the header entry is the truth, not the directory name.

## What an entry holds

Each entry is a frozen PORO in `Riffer::Rig::Stores` — a new entry type is a new class. The JSONL store serialises each one to a line of JSON under its `type`; the line holds:

| Class                  | Holds                                                                                                                                               |
| ---------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------- |
| `Stores::Header`       | written on the first message: `schema_version`, `id`, `cwd`, `created_at`, `model`, `riffer_rig_version`, `riffer_version`, `title` (the first prompt truncated to one line); the store stamps the listed header with `updated` |
| `Stores::MessageEntry` | one conversation message as a riffer message hash under `message`, appended as it lands; the system message is not among them                        |
| `Stores::ModelEntry`   | one per `/model` switch, holding the new `model` string                                                                                              |
| `Stores::SkillEntry`   | one per skill the model activated, holding the skill name; a `/skill:<name>` run is not one                                                          |

## Opting out

Every Loader-built session is saved, one-shots included. Skip one run with `store: nil` — `--no-save` on the command line — or all of them with `"sessions": {"save": false}` in settings ([Configuration](CONFIGURATION.md)).

## Resuming

The Loader picks the session to drive; hosts never see the store:

| Method           | Picks                                                                          |
| ---------------- | ------------------------------------------------------------------------------ |
| `continue`       | the most recently updated session whose header cwd matches the build's, or nil |
| `resume(id)`     | the session with that id, or nil when the store has none                        |
| `list(all: false)` | the header entries, the build's cwd only unless `all: true` escapes the scope |
| `delete(id)`     | removes the session; an unknown id is a no-op                                   |

A listed header carries the session's update time as `updated`, stamped by the store while it holds the physical artifact — for `Stores::JSONL` the file's mtime, which its last append set; `continue` picks the most recently `updated` session wherever `list` happens to place it.

On the command line, `riffer -c` continues the most recent session in the directory and `riffer -r <id>` resumes by id. With no match the REPL tells you and starts fresh. Bare `riffer -r` opens the [picker](#the-picker) before the first session starts; picking a session resumes it, leaving the picker starts a fresh one.

Resuming folds the session's entries back into a snapshot and builds a Runtime over it: the last `model` entry wins, skill activations accumulate, and the `message` entries are the history. Everything else is today's — the settings, credentials, extensions and tools of the new build, and its model selection, unless the session recorded a `/model` switch, which is restored when its provider still has credentials ([Restoring](#restoring) has the rules, including the healed tail of a file cut mid-turn). A resumed session keeps its id and appends to the same file.

## The picker

In the REPL, `/resume` opens the picker over the sessions of the current directory, and `/resume --all` over every directory's. Each row shows the session's first prompt as its title and the relative time of its last update, most recent first.

The picker reads one line at a time:

- Typing text filters the rows to titles containing it (case-insensitive).
- Enter switches to the session when a single row remains.
- A row number — `2`, Enter — switches to that row directly.
- Ctrl-D starts a delete: type the number of the row, then confirm with `y` (`n` or anything else keeps it). The session is removed from the store.
- Enter with several rows, or Ctrl-C, leaves the picker.

Switching replaces the Runtime the terminal drives and re-renders the banner: the conversation you left is already saved, keeps its id and file, and `/resume` appends to it. `/new` starts a fresh session in place the same way — a new id, empty history — and the session you left stays on disk.

## What a snapshot holds

`runtime.to_h` returns a hash with symbol keys:

| Key         | Holds                                                                                                                                  |
| ----------- | -------------------------------------------------------------------------------------------------------------------------------------- |
| `:id`       | the Runtime's id, a UUIDv7 minted when the session began; a restored Runtime keeps it, so it names the session across restarts        |
| `:messages` | the conversation as riffer message hashes (`Riffer::Messages::Base#to_h`), system message first, read back with `Riffer::Messages::Base.from_hash` |
| `:model`    | the model the session switched to with `model=` or `/model`, or `nil` when it kept the model it was built with                          |
| `:skills`   | the names of the skills the model activated in the session ([Skills](SKILLS.md#what-the-model-sees)); a skill run with `/skill:<name>` is not one |

A snapshot survives a JSON round trip: generate it with `JSON.generate`, parse it back with `symbolize_names: true`, and pass the result as `snapshot:`.

## What it leaves out

Nothing a restore can rebuild from the present is stored:

- **Registrations** — tools, commands, hooks, prompt sections and declared settings come from the extensions and settings the restoring Runtime is given, so a session resumed after an extension changed runs the extension as it is now.
- **The tally** — a restored Runtime sums its messages' token usage instead.
- **The base prompt and environment** — the system message is rebuilt at the start of every turn, so the saved one is replaced on the first prompt after a restore.
- **Credentials** — they come from the restoring Runtime's `credentials:`; a saved model whose provider has none there is not applied.

## Restoring

History is data, and the present wins: nothing in a snapshot blocks a restore. A tool call for a tool that no longer exists is just history; tool calls left without a result by a crash are filled with an "interrupted" tool error rather than run; a skill that no longer exists is dropped; and a saved model without credentials falls back to the given model with one `notify`. The first prompt after a restore opens with `session_start` carrying the saved id and reason `:restore`. [Embedding](EMBEDDING.md#snapshots) has the details and an example.
