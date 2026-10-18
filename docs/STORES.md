# Session stores

The [Loader](EMBEDDING.md#building-a-runtime-with-the-loader) saves every session to a store as it runs. The default store writes the JSONL files [Sessions](SESSIONS.md) describes; an app can pass its own, such as one over its database tables, with the `store:` keyword.

## The store interface

A store is any object with these four methods (the RBS interface `Riffer::Rig::Stores::_Store`):

| Method            | Does                                                                            |
| ----------------- | ------------------------------------------------------------------------------- |
| `append(id, entry)` | adds one entry to the session, creating it on the first call                  |
| `read(id)`        | returns the session's entries in order                                          |
| `list(cwd: nil)`  | returns each session's header, for one working directory or all of them, with `updated` set to when the session last changed |
| `delete(id)`      | removes the session; an unknown id does nothing                                 |

```ruby
runtime = Riffer::Rig::Loader.runtime(cwd: Dir.pwd, host: host, store: MyStore.new)
```

`store: nil` saves nothing. The default is `Riffer::Rig::Stores::JSONL.new(home: Dir.home)`.

## Entries

Entries are frozen value objects in `Riffer::Rig::Stores`; a store decides how to serialize them.

| Class            | Appended                                    | Holds                                                                     |
| ---------------- | ------------------------------------------- | ------------------------------------------------------------------------- |
| `Header`         | once, with the first message                | `schema_version`, `id`, `cwd`, `created_at`, `model`, `riffer_rig_version`, `riffer_version`, `title` (the first prompt, on one line) |
| `MessageEntry`   | for each message, as it lands               | the riffer message hash, under `message`; the system message is not saved |
| `ModelEntry`     | for each `/model` switch                    | the new `model`                                                           |
| `ReasoningEntry` | for each `/reasoning` switch                | the new `reasoning` level                                                 |
| `SkillEntry`     | for each skill the model activates          | the skill's `name`                                                        |

Every entry but the header carries `recorded_at`, a UTC ISO 8601 time with milliseconds that never goes backwards within a session; `recorded_time` returns it as a `Time`. It drives [`/trace`](SESSIONS.md#tracing-the-last-turn) and may be `nil`.

On resume, the entries fold back into a [snapshot](EMBEDDING.md#snapshots): the last model and reasoning entries win, skill entries accumulate, and the messages are the history.

## Finding sessions

The Loader picks the session to drive; hosts never see the store.

| Loader method               | Returns                                                                                   |
| --------------------------- | ----------------------------------------------------------------------------------------- |
| `continue(options)`         | a Runtime for the most recently updated session in the Loader's `cwd`, or `nil`            |
| `resume(id, options)`       | a Runtime for that session, or `nil`; `extra_extensions:` works as it does for `runtime`  |
| `list(all: false)`          | the session headers for the Loader's `cwd`, or every directory's with `all: true`          |
| `delete(id)`                | removes the session                                                                       |

`options` is an optional [`Loader::Options`](EMBEDDING.md#loader-options), as for `runtime`.
