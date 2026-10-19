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

# Typing policy

Steep runs `D::Ruby.all_error`: every diagnostic Steep can emit is an error, including the hints and informations that editors surface via the language server — there are no advisory severities. No method body may fall back to `untyped` for lack of an annotation. The bar applies to every change, not just new code.

- **Syntax**: the [rbs-inline Syntax guide](https://github.com/soutaro/rbs-inline/wiki/Syntax-guide) is the source of truth — defer to it over anything written here (it documents the latest release; we pin `~> 0.14`, so check what 0.14 actually supports before reaching for a newer wiki feature). Our preferences within that syntax: doc style only — per-param `# @rbs name: Type` lines plus `# @rbs return: Type`, never the one-line method-type or `#:` forms; and a trailing `#: Type` on the same line for constants and `attr_reader`s (0.14 honours those only there — an annotation on a preceding line is silently ignored).
- **Declarations**: hand-written RBS declarations — interfaces and type aliases — live in `sig/manual/`. `lib/` annotations (per-method, attribute, ivar, constant, `@dynamic`, `module-self`) may reference those interfaces but never declare them: no `# @rbs!` blocks (the `Rig/NoInlineRbsDeclarations` cop in `rubocop/` enforces it).
- **Interfaces**: declare an interface only when different objects satisfy it — two or more implementers, or a contract a consumer implements — or when a boundary forbids naming the one class (`Terminal::_Sessions`, under the terminal's host-API allow-list). When only one class is ever passed, annotate that class (`singleton(Time)` for a clock that defaults to `Time`); a test fake is not a second implementer.
- **Coverage**: every method in `lib/` is annotated, plus every constant/ivar rbs-inline can't infer (`MY_STRING = "a string"` needs nothing).
- **Structured data**: value objects are hand-written frozen POROs, never `Data.define`/`Struct.new`, and never fixed-key hashes passed between methods (an RBS record type such as `{ url: String, headers: Hash[String, String] }`, inline or aliased, is the tell; parsed JSON and settings stay `Hash` until the boundary turns them into objects). `Mcp::Declaration` is the template. rbs-inline types a `Data.define` whose members carry trailing `#: Type` comments, and a later `class Foo` reopen can add methods that see them, but only in the barest shape: a compact constant path (`Riffer::Rig::Events::Foo = Data.define(...)`) generates no signature at all; a bare constant nested under a class makes Steep demand every method of that class in the file (`MethodDefinitionMissing`); an `initialize` override for defaults, validation, or copy-and-freeze can't be typed, because the generated `self.new` still requires every member and `super` into `Data#initialize` is rejected; and methods in a `Data.define` block are dropped. `Struct.new` adds mutable accessors, and its `keyword_init:` signature marks every member optional while the readers stay non-nil. Write the PORO instead: plain `attr_reader`s with `#: Type`, an `initialize` that assigns and freezes, plus `to_h`/`==`/`hash` when the object is compared or serialized.
- **Accessors**: an `attr_reader`/`attr_writer` on a class with declared members needs a `# @dynamic name1, name2` line directly above it — Steep only counts `def` nodes as implementations, so without it every accessor reports `MethodDefinitionMissing`.
- **Noise policy**: when Steep surfaces a diagnostic, fix the annotation or the code. Diagnostics are never disabled in the Steepfile; the only escape is a targeted inline suppression with a `why` comment.
- **Hand-written sigs**: `sig/manual/` mirrors `lib/` for signatures rbs-inline can't generate at all (e.g. interfaces such as `Hosts::_Host` and `Events::_Event`, type aliases, `extend self` re-declarations, Zeitwerk-autovivified namespace modules). `sig/_private/` holds stubs for signature gaps in dependencies and the stdlib (named by gem or library: `open3.rbs`, `thread.rbs`) — RBS skips `_`-prefixed directories in library mode, so they never infect projects that install riffer-rig. `rbs:lint_manual` (part of `bin/typecheck`) fails if a manual/_private file outlives the module it documents.
- **Stub policy**: reach for a gem's own shipped RBS or gem_rbs_collection first (both load automatically via the collection lockfile); write a `sig/_private/` stub only for a gem with no RBS anywhere or a stdlib signature gap (open3's missing `popen2e`). Re-check the collection when updating such a gem, and delete the stub as soon as real signatures exist.

# Inheritance policy

Contracts are RBS interfaces in `sig/manual/`, never abstract base classes. Rig defines no class for another class to inherit from: share code through a mixin (`Support::Equatable`) or a collaborator. In `lib/`, the only superclasses allowed are framework-mandated riffer parents (`Riffer::Tool`, `Riffer::Agent`, `Riffer::Guardrail`, `Riffer::Messages::User`, `Riffer::Skills::Backend`, `Riffer::Tools::Runtime`), `StandardError` subclasses, and `Exception` itself for a signal that must escape a `rescue StandardError`; tooling outside `lib/` may subclass the parent its framework mandates (e.g. `RuboCop::Cop::Base`).
