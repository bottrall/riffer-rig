# Skills

riffer-rig reads [Agent Skills](https://agentskills.io): a directory per skill holding a `SKILL.md`, whose frontmatter names and describes the skill and whose body is the instructions. The model sees a catalog of skills and activates one when a task matches; you can also run one yourself with `/skill:<name>`.

## Directories

The bundled `skills` extension reads skills from these directories, whichever exist:

1. `.agents/skills/` in each directory from the working directory up to the repository root — the project's skills. Outside a Git repository, only the working directory's.
2. `~/.agents/skills/` — your skills for every project.

`.agents/skills/` is where other agents such as Codex look too, so a repository's skills work across tools.

```text
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

The directory name must match `name`: lowercase letters, digits and single hyphens. When two directories hold a skill of the same name, the one closest to the working directory wins, and a project skill wins over one in `~/.agents/skills/`. `disable-model-invocation: true` in the frontmatter keeps a skill out of the model's catalog, while `/skill:<name>` still runs it.

The directories are scanned when the session starts and on every [reload](RELOADING.md), so a skill added mid-session appears after the next one.

## `/skill:<name>`

Every skill gets a command, `/skill:<name> [text]`, in every host — the terminal, headless and ACP. It sends the skill's body to the model as your message, followed by any text you give:

```text
<skill_content name="review">
Read the diff, then…
</skill_content>

focus on lib/
```

Running a skill yourself doesn't mark it as activated for the model; running it again sends the body again.

## What the model sees

When at least one skill exists, the model gets a second system message listing each skill's name and description, and a `skill_activate` tool to call when a request matches one. Activating a skill returns its body in the same `<skill_content>` tags. The skills the model activated are saved with the session and re-activated when you resume it, if they still exist.

## Adding a source

An extension can add skills from anywhere with the [`rig.skills`](EXTENSIONS.md#the-rigskills-seam) seam.

## Disabling

Run with `--no-skills`, or disable `skills` in [settings](CONFIGURATION.md#extensions). There is then no catalog, no `skill_activate` tool and no `/skill:` commands.
