# Skills

riffer-rig reads [Agent Skills](https://agentskills.io): a directory per skill holding a `SKILL.md`, whose YAML frontmatter names and describes the skill and whose body is the instructions. The model sees a catalog of the skills and activates one when a task matches it; you can also run one yourself with `/skill:<name>`.

## Directories

The bundled `skills` extension (`Riffer::Rig.bundled(:skills)`) reads skills from these directories, whichever exist:

1. `.agents/skills/` in each directory from `<cwd>` up to the repository root — the project's skills, where `<cwd>` is the Runtime's `cwd:` and the repository root is the nearest directory at or above it holding a `.git` directory or file. Outside a Git repository, only `<cwd>/.agents/skills/`.
2. `~/.agents/skills/` — your skills for every project, shared with other tools that read `.agents/skills`.

`.agents/skills/` is the location other coding agents such as Codex read too, so a repository's skills work across tools.

Each skill is a directory named after the skill, with a `SKILL.md` inside:

```
.agents/skills/
  review/
    SKILL.md
```

```markdown
---
name: review
description: Review a diff for bugs and style. Use when asked to review changes.
---
Read the diff, then…
```

The directory name must match `name`, which is lowercase letters, digits and single hyphens. When two directories hold a skill of the same name, the one closest to `<cwd>` wins, and any project skill wins over one in `~/.agents/skills/`. Frontmatter with `disable-model-invocation: true` keeps a skill out of the model's catalog; you can still run it with its command.

The directories are scanned when the Runtime is built and again on every rebuild, so a skill added mid-session appears after the next [rebuild](EMBEDDING.md#rebuilding-after-a-code-reload).

## `/skill:<name>`

Every skill in the catalog gets a runtime command, `skill:<name>`, listed in `runtime.commands` after `model` with the skill's description. It works in every host — the terminal, headless and over ACP — through `run_command`:

```ruby
runtime.run_command('skill:review', 'focus on lib/') { |event| … }
```

The command reads the skill's body, emits a `skill_activated` event carrying the name, and sends the body to the model as a user turn, followed by the command's arguments when there are any:

```
<skill_content name="review">
Read the diff, then…
</skill_content>

focus on lib/
```

The turn's events stream to the `run_command` block as a prompt's do. Running a skill yourself does not mark it activated for the model: it stays in the catalog, and running it again sends the body again.

A later extension that registers a command named `skill:<name>` replaces that skill's command.

## What the model sees

When at least one skill exists, riffer adds a second system message after rig's own: the catalog, listing each skill's name and description with an instruction to call the `skill_activate` tool when a request matches one. riffer adds that tool too. When the model activates a skill, the tool result carries the body in the same `<skill_content>` tags, riffer emits its `Riffer::StreamEvents::SkillActivation` event, and the skill is recorded as activated: a [snapshot](SESSIONS.md) saves the names, and a restore re-activates each one still in the catalog and drops the rest.

The extension also registers a `:skills` [prompt section](EXTENSIONS.md#the-rigprompt-seam) that renders nothing, reserved for anything rig adds about skills later. Register your own `:skills` section from a later extension to add text there without disabling the extension.

## Adding a source

An extension adds skills from anywhere with the [`rig.skills`](EXTENSIONS.md#the-rigskills-seam) seam, which takes a block returning a `Riffer::Skills::Backend`. Its skills join the catalog and get commands like the bundled ones.

## Disabling

To leave skills out, do not pass the extension to the Runtime — list `skills` in `extensions.disabled` ([Configuration](CONFIGURATION.md#extensions)), or pass `skills: false` to `Loader.runtime`: with no skills source there is no catalog, no `skill_activate` tool and no `skill:` commands.
