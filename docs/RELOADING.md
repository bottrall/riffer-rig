# Reloading

You can edit your extensions and settings without restarting the session. A reload re-runs both `rig.rb` files and re-reads the settings, credentials and trust, then swaps the result in. The conversation, its token tally, any `/model` or `/reasoning` switch and the session id are kept.

## What reloads

| Reloads                                                                              | Needs a restart                                    |
| ------------------------------------------------------------------------------------ | -------------------------------------------------- |
| both `rig.rb` files, and every file under `~/.riffer` or the project they `require` | extensions installed as gems (`riffer-rig-*`)      |
| `settings.json` in both scopes, including `extensions.disabled`                     | riffer-rig and riffer themselves                   |
| `auth.json` and `trust.json`                                                         | a method you deleted or a constant you renamed     |
| the skills directories                                                               |                                                    |

The settings' `model` key is not re-read: the model in effect is kept. AGENTS.md never needs a reload; it is read every turn. A project `rig.rb` that appears mid-session asks to be trusted, as at startup.

Plain `require` and `require_relative` reload with nothing extra for you to do. Classes are reopened rather than replaced, so edited and added methods take effect, but deleted methods and renamed constants linger until you restart.

## When it reloads

| `reload` setting   | Reloads                                                                                  |
| ------------------ | ---------------------------------------------------------------------------------------- |
| `"auto"` (default) | when a `rig.rb` file, or a file one requires, has changed — checked before each model request; and on `/reload` |
| `"manual"`         | only on `/reload`                                                                        |

`/reload` always reloads. A change to `settings.json`, `auth.json` or the skills directories on its own does not trigger an automatic reload: run `/reload` to pick it up. An automatic reload that fires mid-turn applies from the next turn.

## When it fails

Nothing changes until the reload has fully succeeded. If a `rig.rb` raises, or a settings, `auth.json` or `trust.json` file no longer parses, the reload is abandoned, the session keeps working as before, and you see one message; it is not retried until the files change again. A single extension that fails is [skipped and reported](EXTENSIONS.md#error-isolation) while the rest reload. Errors are shown to you, never to the model.

[Embedding](EMBEDDING.md#rebuilding-after-a-code-reload) covers reloading from your own app.
