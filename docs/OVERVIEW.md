# Overview

riffer-rig is **a general-purpose agent for Ruby developers who want to own their harness**. It runs as a terminal agent, and because the runtime is separate from the terminal it also runs inside any Ruby process. You extend it in Ruby: tools, commands, providers and hooks are ordinary classes on [riffer](https://riffer.ai)'s primitives.

## Why it exists

Compared with pi, OpenCode, Claude Code and Codex:

1. **It runs in your Ruby process.** None of the four can be embedded from Ruby; they offer Ruby a subprocess speaking JSONL, HTTP or RPC.
2. **You extend it in Ruby.** pi has in-process extensions in TypeScript; nobody offers them in Ruby.

It is general purpose, not a coding agent: the default tools are a coding toolkit, but the prompt gives the agent no coding identity. It does not try to match Claude Code's polish or other agents' provider breadth, and it is not a hosted product. Developers outside Ruby can still drive it over [ACP](ACP.md) or as a [subprocess](HEADLESS.md).

There is no permission model: [tools run without asking](TOOLS.md#what-runs-without-asking).

## How it fits together

```text
 riffer          riffer -p        riffer acp       your Ruby app
 (terminal)      (headless)       (editors)        (Rails, a job, a script)
     │                │                │                  │
     └────────────────┴───────┬────────┴──────────────────┘
                              ▼
                           Loader   ◄── settings.json, auth.json, rig.rb,
                              │         AGENTS.md, skills, saved sessions
                              ▼
                           Runtime  ◄── extensions: the bundled toolkit + yours
                              │
                              ▼
                           riffer: the agent loop and the providers
```

- **Hosts** are the front ends. Three ship with the gem — the [terminal](TERMINAL.md), [headless](HEADLESS.md) and [ACP](ACP.md) — and an app can [write its own](HOSTS.md).
- **The Loader** knows riffer-rig's files on disk and builds a Runtime from them, the same way for every shipped host. An app can use it or skip it ([Embedding](EMBEDDING.md)).
- **The Runtime** runs the conversation. It reads no files and assumes no terminal; everything it does comes from the extensions it is given.
- **Extensions** register tools, commands, prompt sections, hooks, skills, MCP servers, settings and providers ([Extensions](EXTENSIONS.md)). The read, write, edit and bash tools, AGENTS.md, Agent Skills and the MCP client are themselves bundled extensions, so each can be disabled or replaced.

Provider-native tools such as web search are part of the core rather than an extension, and are [off by default](CONFIGURATION.md#toolsnative), so changing provider never silently changes what the agent can do.

## Glossary

| Term | Meaning |
| ---- | ------- |
| **session** | one conversation, with an id; saved as you go and [resumable](SESSIONS.md) |
| **turn** | one prompt and everything the agent does until it replies |
| **step** | one model call; a turn that uses tools takes several. `--max-steps` counts these |
| **run** | one pass of the agent loop. A turn is one run, unless a [background job's exit](TOOLS.md#background-jobs) continues it, which starts another |
| **Runtime** | the object that holds a session and runs its turns |
| **Loader** | builds a Runtime from the files on disk |
| **host** | a front end, and the object it gives the Runtime for asking questions and showing notices |
| **extension** | a named Ruby block that registers things with a Runtime |
| **seam** | one of the `rig.*` methods an extension registers through |
| **bundled extension** | an extension that ships with the gem and can be disabled or replaced |

## Where to next

- [Getting started](GETTING_STARTED.md) — install, pick a model, first session
- [Configuration](CONFIGURATION.md) — settings and where each value comes from
- [Extensions](EXTENSIONS.md) — your own tools, commands and hooks
- [Embedding](EMBEDDING.md) — the Runtime from Ruby
