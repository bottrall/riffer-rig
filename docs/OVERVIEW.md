# Overview

riffer-rig is **a general-purpose agent for Ruby developers who want to own their harness**. It runs as a terminal agent and, because the runtime is separate from the terminal, it also runs inside any Ruby process: a Rails app, a script, a job. You extend it in Ruby — tools, commands, providers and hooks are ordinary Ruby classes on [riffer](https://github.com/janeapp/riffer)'s primitives, and the same objects work whether the host is the terminal or your app. It ships with a coding toolkit (read, write, edit, bash) as the default bundle, because a shell and file access are the most efficient way to get almost any task done, but the prompt gives it no coding identity. It is built and maintained by riffer's lead maintainer as a personal MIT project, so the framework grows whatever the agent needs.

## The two claims

Measured against pi, OpenCode, Claude Code and Codex:

1. **Runs in your Ruby process.** None of the four can be embedded from Ruby; all give Ruby a subprocess with JSONL, HTTP or RPC.
2. **Extend it in Ruby.** pi offers in-process code extensions in TypeScript; nobody offers them in Ruby.

The agent is general purpose, not a "coding agent": the default tools are the coding toolkit, but the prompt states operating norms as task-neutral rules and gives no coding identity. It does not compete on provider breadth, on polish with Claude Code, as a hosted product, or for non-Ruby developers — they get [ACP](ACP.md) or a subprocess. There is no permission model for tool execution: the tool trusts the model.

## The four tiers

Everything in the project is one of four things. Ask in order; the first "yes" wins.

1. **Core** — is it something an extension cannot do, *or* something every host needs in exactly the same form?
2. **Host** — is it about how one front-end drives the runtime? The terminal is one host; the headless printer, the ACP adapter and a Rails app are others.
3. **Bundled** — is it the coding toolkit (read, write, edit, bash), or a convention at least two of pi, OpenCode, Claude Code and Codex already share? Then it ships in the gem, is built only on the extension API, and you can disable or replace it.
4. **Third-party** — everything else: ordinary Ruby extensions people write and publish themselves.

| Tier        | Contents                                                                                                                                                                   |
| ----------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Core        | agent loop (riffer); registration seams for tools, commands, providers, prompt contributions and events; extension loader; host interface; settings mechanism and precedence; credentials store and recipe table; session save/resume; token tally and pricing; provider-native tools (off by default) |
| Host        | terminal REPL and UI; headless printer; ACP adapter; extension-directory discovery; provider onboarding prompts                                                                                                                            |
| Bundled     | read/write/edit/bash; Agent Skills; AGENTS.md; MCP client                                                                                                                                                                                  |
| Third-party | hooks, models.dev catalog, MCP server, git context, SQLite session store, any tool beyond the four                                                                                                                                         |

Three rules follow. **Provider-native tools are core and off by default**: they arrive through riffer's provider seam and are switched on in [settings](CONFIGURATION.md#toolsnative), so a provider change never silently changes what the agent can do. **Standards never touch core**: a new convention only asks whether the extension API is rich enough to express it, and if not, that is a seam to add. **Core lives in riffer-rig first**, and is extracted to riffer only when a second riffer agent needs the same thing.

## The layers

Hosts drive a Runtime; the [Loader](EMBEDDING.md#building-a-runtime-with-the-loader) builds one from the filesystem for the shipped hosts, and an embedding app may skip it and register objects directly.

- **Hosts** render events and own the TTY or the wire. Three ship: the terminal REPL ([`riffer`](GETTING_STARTED.md)), the headless printer ([`riffer -p`](HEADLESS.md)), and the ACP adapter ([`riffer acp`](ACP.md)); a Ruby app writes its own on the [Host interface](HOSTS.md).
- **The Loader** holds the filesystem conventions — `rig.rb`, `settings.json`, `auth.json`, trust, `AGENTS.md`, skills, the reload trigger, the session store — and builds a Runtime for a working directory the way the shipped hosts do.
- **The [Runtime](EMBEDDING.md)** assumes no TTY and reads no disk: it accepts registered objects only. It assembles the prompt, streams events, cancels turns, dispatches commands, and snapshots and rebuilds for hot reload. Extensions sit beside it in the runtime layer — the registrar and its [eight seams](EXTENSIONS.md), carrying the bundled read, write, edit, bash, skills, AGENTS.md and MCP client.

Two seams keep the boundary honest. Extension discovery — scanning the config and project directories — lives in the Loader; the Runtime only accepts registered objects. And global state allows several agents in one process: each Runtime builds its own agent and registrar, and provider credentials are one set per process. The runtime assumes no TTY, and no further embedding accommodation is made until a real host exists.

## Where to next

- [Getting started](GETTING_STARTED.md) — install, pick a model, first session
- [Configuration](CONFIGURATION.md) — the settings scopes and every core key
- [Extending](EXTENSIONS.md) — `rig.rb` and the eight seams
- [Embedding](EMBEDDING.md) — `Loader.runtime` and the Runtime from Ruby
- [Providers](PROVIDERS.md) — model strings and credentials