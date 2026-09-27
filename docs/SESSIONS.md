# Sessions

A session is one conversation with a `Riffer::Rig::Runtime`: its id, its history and the choices made during it. The Runtime can save a session as a plain hash and carry on from one; storing those hashes, listing them and picking one to resume belong to the session store, which is not here yet. Until it is, an embedder keeps snapshots itself ([Embedding](EMBEDDING.md#snapshots)).

## What a snapshot holds

`runtime.to_h` returns a hash with symbol keys:

| Key         | Holds                                                                                                                                  |
| ----------- | -------------------------------------------------------------------------------------------------------------------------------------- |
| `:id`       | the Runtime's id, a UUIDv7 minted when the session began; a restored Runtime keeps it, so it names the session across restarts        |
| `:messages` | the conversation as riffer message hashes (`Riffer::Messages::Base#to_h`), system message first, read back with `Riffer::Messages::Base.from_hash` |
| `:model`    | the model the session switched to with `model=` or `/model`, or `nil` when it kept the model it was built with                          |
| `:skills`   | the names of the skills activated in the session                                                                                       |

A snapshot survives a JSON round trip: generate it with `JSON.generate`, parse it back with `symbolize_names: true`, and pass the result as `snapshot:`.

## What it leaves out

Nothing a restore can rebuild from the present is stored:

- **Registrations** — tools, commands, hooks, prompt sections and declared settings come from the extensions and settings the restoring Runtime is given, so a session resumed after an extension changed runs the extension as it is now.
- **The tally** — a restored Runtime sums its messages' token usage instead.
- **The base prompt and environment** — the system message is rebuilt at the start of every turn, so the saved one is replaced on the first prompt after a restore.
- **Credentials** — they come from the restoring Runtime's `credentials:`; a saved model whose provider has none there is not applied.

## Restoring

History is data, and the present wins: nothing in a snapshot blocks a restore. A tool call for a tool that no longer exists is just history; tool calls left without a result by a crash are filled with an "interrupted" tool error rather than run; a skill that no longer exists is dropped; and a saved model without credentials falls back to the given model with one `notify`. The first prompt after a restore opens with `session_start` carrying the saved id and reason `:restore`. [Embedding](EMBEDDING.md#snapshots) has the details and an example.
