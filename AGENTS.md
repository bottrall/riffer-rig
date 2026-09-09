# riffer-rig

Terminal coding agent built on the riffer framework.

## Quick Reference

- **Ruby**: 4.0.5 (CI: 4.0)
- **Lint + Test + Typecheck**: `bin/ci`
- **Autoloading**: Zeitwerk (file paths must match module/class names)
- **Namespace**: `Riffer::Rig`, compact style (`module Riffer::Rig::Tools::Read`); `version.rb` is the one exception — it must nest because the gemspec loads it before riffer
- **Types**: rbs-inline annotations in `lib/` generate `sig/generated`; run `bin/rbs` after any `lib/` change and commit the result
- **Tests**: Minitest (Spec style: `describe`/`it`, `assert_*` assertions), one assertion per `it`, `test/riffer/rig/` mirrors `lib/riffer/rig/`
- **PR titles**: [Conventional Commits](https://www.conventionalcommits.org/) — `feat:` bumps the minor, `fix:` the patch; titles are linted in CI and become the squash commit on `main`
- **Releases**: release-please keeps a release PR open; merging it publishes the gem. The `riffer` dependency is pinned to one minor (`~> 0.45.0`) — retitle Dependabot's riffer bump `feat(deps):` or `fix(deps):` so it releases

## Commands

All wrappers delegate to the Rakefile under the hood.

| Command         | Description                                                                           |
| --------------- | ------------------------------------------------------------------------------------- |
| `bin/setup`     | Install dependencies on a fresh checkout                                              |
| `bin/test`      | Run tests. Pass files and/or Minitest flags: `bin/test test/foo_test.rb -n /pattern/` |
| `bin/lint`      | Check code style (pass `-a` to auto-fix)                                              |
| `bin/typecheck` | Check `sig/generated` is current, then type-check with Steep                          |
| `bin/rbs`       | Regenerate `sig/generated` from the inline annotations in `lib/`                      |
| `bin/ci`        | Run everything CI runs, serially. Use before pushing                                  |
| `bin/build`     | Build the gem into `pkg/`                                                             |
| `bin/plans`     | Serve the building plans in `plans/` at http://localhost:8001                         |

`bin/rake <task>` is the escape hatch for any rake task without a named wrapper.

# Comments and documentation

**The default is no comment.** Names, types, and control flow carry the meaning; a comment is the exception, not the norm. The burden is on the comment to justify the space it occupies and the drift it will accrue — not on the reader to tolerate it. When a comment earns its place, it does so only by explaining a **why** the code itself can't — never a **how**, and never a restatement of what the code already says. Types are not prose's job: parameter, return, and field types live in the type system (RBS), never in a comment that duplicates them.

**The deletion test.** Before writing or keeping any comment, delete it and read the code cold. If a competent reader can still recover the intent from names, types, and structure, it stays deleted. A comment survives _only_ when its removal genuinely loses something the code cannot show: a non-local constraint, an external-system quirk, a deliberate non-obvious tradeoff, or a safety invariant not visible locally. Most comments fail this test — that is expected.

- **A causal clause doesn't launder a restatement.** Appending "so that…" / "because…" to a paraphrase of the code does not turn a _what_ into a _why_. Keep only the fragment a reader couldn't derive; if nothing survives, cut the whole line — don't keep the restatement for the sake of the clause.
- **No header paraphrase.** A one-line summary above a function, component, or hook that re-states what it does — however elegantly — is a _what_. The symbol's name is its summary. Comment a specific non-obvious decision _inside_ it, or comment nothing. If most new symbols in a change are getting a header, that's the tell you're commenting by habit, not by need.
- **Internal code** — self-documenting via strong types and clear names. This is almost everything we write, and almost all of it ships with no comments at all.
- **Published surface** — the _only_ place a per-symbol description is expected, and only for the public API of something we actually distribute for others to consume (an API client, CLI, or MCP server). Internal app code — components, hooks, pages, routes, test helpers — is not a published surface, even when its symbols are `export`ed. Where it does apply: every exported symbol gets a one-line, verb-first description (`Serializes the definition to JSON.`); a second sentence only for a non-obvious _why_, never more _how_. Exempt: a constant whose name and value already say it (`VERSION = "0.3.0"`), and a placeholder namespace whose members are documented individually.
- **Inline comments** meet the same bar. `TODO` / `FIXME` / `HACK` are tracked work and stay; `NOTE` / `REVIEW` are held to the why-rule.
- **No history.** Describe the present, never how the code got here — no "was X, now Y", no "previously Z". State a still-true constraint in the present tense ("the API returns null for empty results — guard"), not the story of what revealed it.
