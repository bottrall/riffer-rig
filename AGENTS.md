# riffer-rig

Terminal coding agent built on the riffer framework.

## Quick Reference

- **Ruby**: 4.0.9 (CI: 4.0)
- **Lint + Test + Typecheck**: `bin/ci`
- **Autoloading**: Zeitwerk (file paths must match module/class names)
- **Namespace**: `Riffer::Rig`, compact style (`module Riffer::Rig::Tools::Read`); `version.rb` is the one exception — it must nest because the gemspec loads it before riffer
- **Types**: strict Steep over rbs-inline annotations — every method in `lib/` carries `@rbs` annotations; `sig/generated` is committed; run `bin/rbs` after any `lib/` change
- **Third-party RBS**: managed by `rbs collection` (`rbs_collection.yaml` + committed lockfile; `.gem_rbs_collection/` is gitignored); `bin/setup` installs it, `bin/typecheck` fails if the lockfile is stale; bump the pinned collection revision deliberately, via `rbs collection update` run through `bundle exec`
- **Tests**: Minitest (Spec style: `describe`/`it`, `assert_*` assertions), one assertion per `it`, `test/riffer/rig/` mirrors `lib/riffer/rig/`
- **PR titles**: [Conventional Commits](https://www.conventionalcommits.org/) — `feat:` bumps the minor, `fix:` the patch; titles are linted in CI and become the squash commit on `main`; a PR whose code nothing in the live path reaches yet (fixes included) is `refactor:`, and the PR that wires it in carries the `feat:`/`fix:` — correct a merged title with a `BEGIN_COMMIT_OVERRIDE` … `END_COMMIT_OVERRIDE` block in the PR body
- **Releases**: release-please keeps a release PR open; merging it publishes the gem

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
| `bin/docs`      | Build the docs site and API reference into `_site/`; `bin/docs serve` serves it at http://localhost:8000 |

`bin/rake <task>` is the escape hatch for any rake task without a named wrapper.

# Testing

- Every module of behaviour gets a test file, even if it's only a smoke test. A unit with no behaviour — pure constants, data definitions — needs no test file.
- Only test what can change. Static code — generated files, constants, trivial accessors — gets at most a smoke test. Generated code is pinned at its generator: test the generator, not each generated output.
- A test file tests only the concerns of the unit it's mapped to. If testing X requires driving Y's entry point, either the behaviour belongs in X's own file with collaborators injected, or Y's file is covering for a missing X test. A behaviour belongs to the unit whose contract it is, even when observing it means calling through an object that unit returns. A composer's tests assert the composer's outcomes only — never a collaborator's branches, which are pinned in the collaborator's own file.
- Order tests the way the code is ordered: they follow the source's structure, and within a routine they follow execution order (validation behaviour first).
- Test all branches in reason: every early return, conditional, and error path gets a test — unless the branch is dead or a programmer-error tripwire.

# Comments and documentation

**The default is no comment.** Names, types, and structure carry the meaning; when they don't, fix them rather than explain them. Delete the comment and read the code cold: if the intent is still recoverable, it stays deleted. Keep only a _why_ the code can't show — a non-local constraint, an external quirk, a deliberate tradeoff, a safety invariant — and put it at the line it explains, not in a header.

Never: a restatement of the code (appending "so that…" doesn't rescue it), types the type system already states, or history ("was X, now Y").

Documentation lives in the guides, not in comments. What a signature can't express — what a method raises, ordering guarantees, what an implementer must honour — is documented there.

The guides in `docs/` are written for consumers: people running `riffer`, embedding rig, or writing a host, provider, or extension. A guide documents only what a consumer can use or observe. Internal modules, implementation limits, and behaviour nothing public reaches yet are not documented anywhere — tests and names carry them. If a change has no consumer-visible effect, it changes no guide.

How much to say, and where:

- **One home per fact.** Each fact is explained in one guide; every other guide links to it and never restates it. The shared homes: precedence and merge rules → `CONFIGURATION.md`; flags → `CLI.md`; background jobs → `TOOLS.md` (the model's side) and `EMBEDDING.md` (the API); events → `EVENTS.md`; error messages → `TROUBLESHOOTING.md`.
- **Document an edge case only if a reader would act on it.** The tests pin the rest.
- **A paragraph that lists conditions and outcomes is a table.** A paragraph over ~120 words needs a reason. Draw diagrams as ` ```text ` blocks, which render on GitHub and the site alike.
- **No source paths, test references or internal mechanics** in a guide — no `lib/` paths, no "a test enforces", no how a mixin builds its methods.
- **History goes in `CHANGELOG.md`.** A guide describes current behaviour only: no "earlier versions", no "replaces the old X". A breaking change's upgrade steps go in the changelog entry.
- **The README is the front door**: pitch, install, quickstart, one example each of extending and embedding, and links. It never restates a guide. `docs:check` validates its links along with the site's.

# Where code goes

Everything in the project is one of four tiers. Ask in order; the first "yes" wins.

1. **Core** — something an extension cannot do, or something every host needs in exactly the same form?
2. **Host** — about how one front end drives the Runtime? The terminal, headless printer and ACP adapter are hosts.
3. **Bundled** — the coding toolkit (read, write, edit, bash), or a convention at least two of pi, OpenCode, Claude Code and Codex already share? It ships in the gem, is built only on the extension API, and can be disabled or replaced.
4. **Third-party** — everything else: extensions people write and publish themselves.

Three rules follow. Provider-native tools are core and off by default, so a provider change never silently changes what the agent can do. Standards never touch core: a new convention only asks whether the extension API can express it, and if not, that is a seam to add. Core lives in riffer-rig first, and moves to riffer only when a second riffer agent needs the same thing.

# Typing policy

Steep runs `D::Ruby.all_error`: every diagnostic Steep can emit is an error, including the hints and informations that editors surface via the language server — there are no advisory severities. No method body may fall back to `untyped` for lack of an annotation. The bar applies to every change, not just new code.

- **Syntax**: the [rbs-inline Syntax guide](https://github.com/soutaro/rbs-inline/wiki/Syntax-guide) is the source of truth — defer to it over anything written here (it documents the latest release; we pin `~> 0.14`, so check what 0.14 actually supports before reaching for a newer wiki feature). Our preferences within that syntax: doc style only — per-param `# @rbs name: Type` lines plus `# @rbs return: Type`, never the one-line method-type or `#:` forms; and a trailing `#: Type` on the same line for constants and `attr_reader`s (0.14 honours those only there — an annotation on a preceding line is silently ignored).
- **Declarations**: hand-written RBS declarations — interfaces and type aliases — live in `sig/manual/`. `lib/` annotations (per-method, attribute, ivar, constant, `@dynamic`, `module-self`) may reference those interfaces but never declare them: no `# @rbs!` blocks (the `Rig/NoInlineRbsDeclarations` cop in `rubocop/` enforces it).
- **Interfaces**: declare an interface only when different objects satisfy it — two or more implementers, or a contract a consumer implements — or when a boundary forbids naming the one class (`Terminal::_Sessions`, under the terminal's host-API allow-list). When only one class is ever passed, annotate that class (`singleton(Time)` for a clock that defaults to `Time`); a test fake is not a second implementer.
- **Coverage**: every method in `lib/` is annotated, plus every constant/ivar rbs-inline can't infer (`MY_STRING = "a string"` needs nothing).
- **Structured data**: value objects are hand-written frozen POROs, never `Data.define`/`Struct.new`, and never fixed-key hashes passed between methods (an RBS record type such as `{ url: String, headers: Hash[String, String] }`, inline or aliased, is the tell; parsed JSON and settings stay `Hash` until the boundary turns them into objects). `Mcp::Declaration` is the template: `attr_reader`s with `#: Type`, an `initialize` that assigns and freezes, plus `to_h`/`==`/`hash` when the object is compared or serialized. rbs-inline only types a bare `Data.define` nested in a module — no compact constant path, no `initialize` override, no methods in its block — and `Struct` is mutable.
- **Accessors**: an `attr_reader`/`attr_writer` on a class with declared members needs a `# @dynamic name1, name2` line directly above it — Steep only counts `def` nodes as implementations, so without it every accessor reports `MethodDefinitionMissing`.
- **Noise policy**: when Steep surfaces a diagnostic, fix the annotation or the code. Diagnostics are never disabled in the Steepfile; the only escape is a targeted inline suppression with a `why` comment.
- **Hand-written sigs**: `sig/manual/` mirrors `lib/` for signatures rbs-inline can't generate at all (e.g. interfaces such as `Hosts::_Host` and `Events::_Event`, type aliases, `extend self` re-declarations, Zeitwerk-autovivified namespace modules). `sig/_private/` holds stubs for signature gaps in dependencies and the stdlib (named by gem or library: `open3.rbs`, `thread.rbs`) — RBS skips `_`-prefixed directories in library mode, so they never infect projects that install riffer-rig. `rbs:lint_manual` (part of `bin/typecheck`) fails if a manual/_private file outlives the module it documents.
- **Stub policy**: reach for a gem's own shipped RBS or gem_rbs_collection first (both load automatically via the collection lockfile); write a `sig/_private/` stub only for a gem with no RBS anywhere or a stdlib signature gap (open3's missing `popen2e`). Re-check the collection when updating such a gem, and delete the stub as soon as real signatures exist.

# Inheritance policy

Contracts are RBS interfaces in `sig/manual/`, never abstract base classes. Rig defines no class for another class to inherit from: share code through a mixin (`Support::Equatable`) or a collaborator. In `lib/`, the only superclasses allowed are framework-mandated riffer parents (`Riffer::Tool`, `Riffer::Agent`, `Riffer::Guardrail`, `Riffer::Messages::User`, `Riffer::Skills::Backend`, `Riffer::Tools::Runtime`), `StandardError` subclasses, and `Exception` itself for a signal that must escape a `rescue StandardError`; tooling outside `lib/` may subclass the parent its framework mandates (e.g. `RuboCop::Cop::Base`).
