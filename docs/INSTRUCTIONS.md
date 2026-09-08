# Instructions

A `Riffer::Rig::Session` builds one system message for its agent. The default base prompt is a short, task-neutral text owned by the Session: it names the agent, says it is general purpose and works through whatever tools it has, and states three norms. It lists no tools and names no conventions — each arrives through the prompt seam and introduces itself when present, so a Session with no extensions says nothing untrue.

The base prompt is a heredoc in the Session's agent definition ([permalink](https://github.com/bottrall/riffer-rig/blob/main/lib/riffer/rig/session.rb)); this guide deliberately does not restate its text.

## Overrides

- `name:` (default `"riffer"`) swaps the name interpolated inside the default base.
- `instructions:` replaces the base wholesale — the environment block is still appended.

In both cases the environment block is appended to the result:

```
Current date: <today>
Current working directory: <cwd>
```

The date and cwd come from the Session's construction time and `cwd:` keyword; the Session performs no other disk scanning.
