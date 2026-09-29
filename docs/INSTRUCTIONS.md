# Instructions

A `Riffer::Rig::Runtime` builds one system message for its agent. The default base prompt is a short, task-neutral text owned by the Runtime: it names the agent, says it is general purpose and works through whatever tools it has, and states three norms. It lists no tools and names no conventions — each arrives through the prompt seam and introduces itself when present, so a Runtime with no extensions says nothing untrue.

The base prompt is a heredoc in the Runtime's agent definition ([permalink](https://github.com/bottrall/riffer-rig/blob/main/lib/riffer/rig/runtime.rb)); this guide deliberately does not restate its text.

## Assembly

The system message is three parts joined by blank lines:

1. **Base prompt** — the default text above, or the `instructions:` replacement.
2. **Prompt sections** — every `rig.prompt(:name) { |ctx| }` block the Runtime's extensions registered, in load order, a later registration of a name replacing the earlier one. See [Extensions](EXTENSIONS.md).
3. **Environment block** — always appended by the Runtime:

   ```
   Current date: <today>
   Current working directory: <cwd>
   ```

When skills exist, riffer follows it with a second system message of its own, the skills catalog ([Skills](SKILLS.md#what-the-model-sees)). The Runtime does not touch it.

The Runtime re-renders the three parts at the start of every turn: section blocks run again and the date is read again, so nothing needs a reload to stay current. The base prompt is fixed at construction. The cwd is the `cwd:` keyword; the Runtime itself performs no disk scanning — a section that reads a file does so in its extension.

## AGENTS.md

The bundled `agents_md` extension (`Riffer::Rig.bundled(:agents_md)`) registers one prompt section, `:agents_md`. It reads these files, whichever exist, in this order:

1. `~/.riffer/AGENTS.md` — your instructions for every project.
2. An `AGENTS.md` in every directory from the filesystem root down to `<cwd>`, outermost first, where `<cwd>` is the Runtime's `cwd:`. A monorepo can keep shared instructions at its root and a package's own in the package, and a run from inside the package reads both.

A file is read once even when it sits on both paths, as `~/.riffer/AGENTS.md` does when `<cwd>` is `~/.riffer`.

The section opens with one sentence framing what follows as instructions the user wrote, which take precedence over the base prompt's norms where they conflict, and among themselves the later file (the one closer to `<cwd>`) wins. Each file follows as its own block, tagged with its absolute path:

```
<project_instructions path="/home/you/project/AGENTS.md">
…the file's contents…
</project_instructions>
```

With no file present the section renders nothing, so the system message does not mention AGENTS.md at all.

The files are read at the start of every turn, so an edit takes effect on the next turn with no reload or rebuild.

Relative paths written inside an AGENTS.md are left as written; the extension does not resolve them. Reading what they point to is the model's business, with its tools, from the working directory.

To leave AGENTS.md out, do not pass the extension to the Runtime. To change what it says, register your own `:agents_md` section from a later extension; the later registration replaces the bundled one ([Extensions](EXTENSIONS.md#bundled-extensions-and-replacement)).

## Overrides

- `name:` (default `"riffer"`) swaps the name interpolated inside the default base.
- `instructions:` replaces the base wholesale.

Sections and the environment block are appended in both cases.
