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

When skills exist, riffer follows it with a second system message of its own, the skills catalog. The Runtime does not touch it.

The Runtime re-renders the three parts at the start of every turn: section blocks run again and the date is read again, so nothing needs a reload to stay current. The base prompt is fixed at construction. The cwd is the `cwd:` keyword; the Runtime itself performs no disk scanning — a section that reads a file does so in its extension.

## Overrides

- `name:` (default `"riffer"`) swaps the name interpolated inside the default base.
- `instructions:` replaces the base wholesale.

Sections and the environment block are appended in both cases.
