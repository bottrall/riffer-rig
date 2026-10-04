# Sessions

A session is one conversation with a `Riffer::Rig::Runtime`: its id, its history and the choices made during it. The Runtime can save a session as a plain hash and carry on from one ([below](#what-a-snapshot-holds)); the Loader stores every session it builds as it runs, one JSONL file per session under `~/.riffer/sessions/`. Picking a stored session to resume from is not here yet; until it is, an embedder reads the entries directly or keeps snapshots itself ([Embedding](EMBEDDING.md#snapshots)).

## The session store

The Loader appends to a store: any object implementing the four `Riffer::Rig::Stores::_Store` methods — `append(id, entry)`, `read(id)`, `list(cwd: nil)` and `delete(id)`. It defaults to `Stores::JSONL` and takes `store:` per build; a Rails host implements the four over its own tables and passes its own. Hosts never see the store — they only choose which session to drive.

## Where sessions live

`Stores::JSONL` writes one file per session at `~/.riffer/sessions/<cwd-slug>/<session id>.jsonl`, one entry per line, so `cat` and `jq` work and a crash loses at most one line. The slug is the cwd with every run of characters outside alphanumerics, `.`, `_` and `-` collapsed to a single hyphen; it groups a project's sessions so listing is a directory read, but the `cwd` in the header entry is the truth, not the directory name.

## What an entry holds

Each line is a JSON object with a `type`:

| `type`    | Holds                                                                                                                                               |
| --------- | --------------------------------------------------------------------------------------------------------------------------------------------------- |
| `header`  | written on the first message: `schema_version`, `id`, `cwd`, `created_at`, `model`, `riffer_rig_version`, `riffer_version`, `title` (the first prompt truncated to one line) |
| `message` | one conversation message as a riffer message hash under `message`, appended as it lands; the system message is not among them                        |
| `model`   | one per `/model` switch, holding the new `model` string                                                                                              |
| `skill`   | one per skill the model activated, holding the skill name; a `/skill:<name>` run is not one                                                          |

## Opting out

Every Loader-built session is saved, one-shots included. Skip one run with `store: nil` — `--no-save` on the command line — or all of them with `"sessions": {"save": false}` in settings ([Configuration](CONFIGURATION.md)).

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
