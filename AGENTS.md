# riffer-rig

Terminal coding agent built on the riffer framework.

## Quick Reference

- **Ruby**: 4.0.6 (CI: 4.0)
- **Lint + Test + Typecheck**: `bin/ci`
- **Autoloading**: Zeitwerk (file paths must match module/class names)
- **Namespace**: `Riffer::Rig`, compact style (`module Riffer::Rig::Tools::Read`); `version.rb` is the one exception — it must nest because the gemspec loads it before riffer
- **Types**: strict Steep over rbs-inline annotations — every method in `lib/` carries `@rbs` annotations; `sig/generated` is committed; run `bin/rbs` after any `lib/` change
- **Third-party RBS**: managed by `rbs collection` (`rbs_collection.yaml` + committed lockfile; `.gem_rbs_collection/` is gitignored); `bin/setup` installs it, `bin/typecheck` fails if the lockfile is stale; bump the pinned collection revision deliberately, via `rbs collection update` run through `bundle exec`
- **Tests**: Minitest (Spec style: `describe`/`it`, `assert_*` assertions), one assertion per `it`, `test/riffer/rig/` mirrors `lib/riffer/rig/`
- **PR titles**: [Conventional Commits](https://www.conventionalcommits.org/) — `feat:` bumps the minor, `fix:` the patch; titles are linted in CI and become the squash commit on `main`
- **Releases**: release-please keeps a release PR open; merging it publishes the gem. The `riffer` dependency is pinned to one minor (`~> 0.45.0`) — retitle Dependabot's riffer bump `feat(deps):` or `fix(deps):` so it releases

## Commands

All wrappers delegate to the Rakefile under the hood.

| Command         | Description                                                                           |
| --------------- | ------------------------------------------------------------------------------------- |
| `bin/setup`     | Install dependencies on a fresh checkout (gems + rbs collection)                      |
| `bin/test`      | Run tests. Pass files and/or Minitest flags: `bin/test test/foo_test.rb -n /pattern/` |
| `bin/lint`      | Check code style (pass `-a` to auto-fix)                                              |
| `bin/typecheck` | Check the rbs collection lockfile and `sig/generated` are current, then type-check with Steep |
| `bin/rbs`       | Regenerate `sig/generated` from the inline annotations in `lib/`                      |
| `bin/ci`        | Run everything CI runs, serially. Use before pushing                                  |
| `bin/build`     | Build the gem into `pkg/`                                                             |
| `bin/plans`     | Serve the building plans in `plans/` at http://localhost:8001                         |

`bin/rake <task>` is the escape hatch for any rake task without a named wrapper.

# Comments and documentation

**The default is no comment.** Names, types, and structure carry the meaning; when they don't, fix them rather than explain them. Delete the comment and read the code cold: if the intent is still recoverable, it stays deleted. Keep only a _why_ the code can't show — a non-local constraint, an external quirk, a deliberate tradeoff, a safety invariant — and put it at the line it explains, not in a header.

Never: a restatement of the code (appending "so that…" doesn't rescue it), types the type system already states, or history ("was X, now Y").

Documentation lives in the guides, not in comments. What a signature can't express — what a method raises, ordering guarantees, what an implementer must honour — is documented there.

# Typing policy

Steep runs `D::Ruby.all_error`: every diagnostic Steep can emit is an error, including the hints and informations that editors surface via the language server — there are no advisory severities. No method body may fall back to `untyped` for lack of an annotation. The bar applies to every change, not just new code.

- **Syntax**: the [rbs-inline Syntax guide](https://github.com/soutaro/rbs-inline/wiki/Syntax-guide) is the source of truth — defer to it over anything written here (it documents the latest release; we pin `~> 0.14`, so check what 0.14 actually supports before reaching for a newer wiki feature). Our preferences within that syntax: doc style only — per-param `# @rbs name: Type` lines plus `# @rbs return: Type`, never the one-line method-type or `#:` forms; and a trailing `#: Type` on the same line for constants and `attr_reader`s (0.14 honours those only there — an annotation on a preceding line is silently ignored).
- **Coverage**: every method in `lib/` is annotated, plus every constant/ivar rbs-inline can't infer (`MY_STRING = "a string"` needs nothing).
- **Structured data**: value objects are hand-written frozen POROs, never `Data.define`/`Struct.new` (`Settings::Pricing` is the template). rbs-inline can type `Data` *members* via trailing `#: Type` comments, but Steep can't see any method you define on the generated class — a literal `class Foo` reopen binds `self` to the enclosing module (no members), and a `define_method` block body hides them too — so anything beyond the bare members forces string `class_eval` and a hand-written `sig/manual/` file. Write the PORO instead: plain `attr_reader`s with `#: Type`, an `initialize` that assigns and freezes, plus `to_h`/`==`/`hash` when the object is compared or serialized.
- **Accessors**: an `attr_reader`/`attr_writer` on a class with declared members needs a `# @dynamic name1, name2` line directly above it — Steep only counts `def` nodes as implementations, so without it every accessor reports `MethodDefinitionMissing`.
- **Noise policy**: when Steep surfaces a diagnostic, fix the annotation or the code. Diagnostics are never disabled in the Steepfile; the only escape is a targeted inline suppression with a `why` comment.
- **Hand-written sigs**: `sig/manual/` mirrors `lib/` for signatures rbs-inline can't generate at all (e.g. `extend self` re-declarations, Zeitwerk-autovivified namespace modules). `sig/_private/` holds dependency-gem stubs (named by gem: `zeitwerk.rbs`, `open3.rbs`, `riffer/tool.rbs`) — RBS skips `_`-prefixed directories in library mode, so they never infect projects that install riffer-rig. `rbs:lint_manual` (part of `bin/typecheck`) fails if a manual/_private file outlives the module it documents.
- **Stub policy**: reach for a gem's own shipped RBS or gem_rbs_collection first (both load automatically via the collection lockfile); write a `sig/_private/` stub only for a gem with no RBS anywhere (zeitwerk) or a stdlib signature gap (open3's missing `popen2e`). Re-check the collection when updating such a gem, and delete the stub as soon as real signatures exist.
