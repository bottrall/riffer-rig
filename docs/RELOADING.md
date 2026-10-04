# Reloading

A reload rebuilds the registrar from the extension files re-executed as they are on disk: `/reload`, the runtime command the Loader installs, scrubs the tracked files from Ruby's `$LOADED_FEATURES`, loads both `rig.rb` files again ([Extensions](EXTENSIONS.md#the-rigrb-files)), re-reads the settings, credentials and trust, and swaps a freshly built registrar in atomically. History, the tally, the `/model` override and the session id survive the swap; the tools, commands, prompt sections and handlers are whatever the files say now.

## What reloads

Both `rig.rb` files, every local file they `require` or `require_relative` (anything under `~/.riffer` or the project), `settings.json` in both scopes, `auth.json`, and trust status — a project `rig.rb` that first appears mid-session goes through the same trust confirm as at startup. Settings are re-read whole, so `extensions.disabled` re-applies too; the settings' `model` key is not read, and the model in effect is kept.

## What does not

Extension gems (`riffer-rig-*`), riffer-rig's own code and riffer stay as loaded. Skills and AGENTS.md need no reload: their sections are evaluated per turn ([Skills](SKILLS.md), [Instructions](INSTRUCTIONS.md)).

## The mechanism

On first load the Loader diffs `$LOADED_FEATURES` around loading each `rig.rb`; the new entries under `~/.riffer` or the project are the tracked files, gem paths dropped, and the `rig.rb` files themselves are tracked too. A reload deletes those entries from `$LOADED_FEATURES` and loads each `rig.rb` again, so plain `require` and `require_relative` re-execute with no author-side convention, and a `require` added since the last load is picked up from that reload on.

Classes are reopened in place, not removed: edited and added methods take effect. `Riffer::Rig.extension("name")` records into the process registry keyed by name, so re-execution replaces the block rather than duplicating it.

## Triggers

`/reload` always reloads and re-discovers the file set. Embedders call `Loader#reload(runtime, force: false)` themselves ([Embedding](EMBEDDING.md#building-a-runtime-with-the-loader)): without `force` it is a no-op while the tracked file set and the two `rig.rb` paths look exactly as the last discovery left them, which is the entry point the automatic check at the `before_request` boundary will use. That check is not built yet.

## Failure

The new registrar is built aside; nothing on the Runtime changes until it is complete. If a `rig.rb` itself raises, the reload is abandoned: the live registrar stays, the host gets one `notify`, and the mtime snapshot advances so a failing reload is not retried on every request. A single extension block failing follows the standard rule: skipped and reported, the rest swap in ([Extensions](EXTENSIONS.md#error-isolation)). Errors go to the host only, never into the model's context.

## Known limits

- Reopened classes keep deleted methods and renamed constants until restart.
- Gem-packaged extensions do not reload.
- Two Runtimes in one process share the process-level extension registry and providers; a reload in one does not rebuild the other.