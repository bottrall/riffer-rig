# Instructions

At a session's first turn, riffer-rig builds the model's system message from three parts, joined by blank lines:

1. **The base prompt** — a short, task-neutral text: it names the agent, says it is general purpose and works through whatever tools it has, and states three operating norms. It names no tools and no conventions, so a session without them says nothing untrue.
2. **Prompt sections** — the text each extension adds with [`rig.prompt`](EXTENSIONS.md#the-rigprompt-seam), in load order. AGENTS.md (below) is one of these.
3. **The environment** — always last.

The base prompt is plain text. Each section and the environment comes in a `<section>` element named as its extension registered it; the environment is `environment`:

```text
<section name="environment">
Current date: <today>
Current working directory: <cwd>
</section>
```

When skills exist, a second system message follows with the [skills catalog](SKILLS.md#what-the-model-sees).

## Changes during a session

The system message stays as the first turn built it for the whole session, through a [reload](RELOADING.md) or a [resume](SESSIONS.md#resuming). Sections and the environment are still re-read at the start of every turn, and when one differs from what the model last saw, a context update joins the conversation just ahead of that turn's prompt. It gives the full new text of each section that changed, in the same element as the system message, and marks each one that no longer applies; earlier messages are never rewritten, so the model keeps its earlier reasoning and the provider's prompt cache stays valid.

```text
<context-update>
Your context changed since you last saw it. Each section below replaces its earlier version in full; a section marked removed no longer applies.

<section name="environment">
Current date: <today>
Current working directory: <cwd>
</section>

</context-update>
```

A turn where nothing changed adds no update.

## AGENTS.md

The bundled `agents_md` extension adds these files, whichever exist, in this order:

1. `~/.riffer/AGENTS.md` — your instructions for every project.
2. An `AGENTS.md` in every directory from the filesystem root down to the working directory, outermost first. A monorepo can keep shared instructions at its root and a package's own in the package, and a session in the package reads both.

The section tells the model these are instructions you wrote, which take precedence over the base prompt's norms, and that a file closer to the working directory wins over one further out. Each file appears as its own block, tagged with its path:

```text
<project_instructions path="/home/you/project/AGENTS.md">
…the file's contents…
</project_instructions>
```

With no file present the section is empty, and the system message doesn't mention AGENTS.md. Relative paths inside a file are left as written; the model resolves them with its tools. A file added, edited or deleted mid-session reaches the model on the next turn as a [context update](#changes-during-a-session).

To leave AGENTS.md out, run with `--no-agents-md` or disable `agents_md` in [settings](CONFIGURATION.md#extensions). To change what it adds, register your own `:agents_md` section from an extension, which [replaces](EXTENSIONS.md#bundled-extensions-and-replacement) the bundled one.

## Changing the base prompt

When [embedding](EMBEDDING.md#constructing-a-runtime), `name:` changes the agent's name inside the base prompt (default `"riffer"`), and `instructions:` replaces the base prompt entirely. Prompt sections and the environment are added either way.
