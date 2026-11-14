# riffer-rig

Terminal coding agent built on the riffer framework.

## Commands

Everything runs through its `bin/` script, never a tool directly (`rake`, `rubocop`, `steep`, `vitest`, `oxlint`, `tsc`, `vite`, `playwright`).

| Script                        | What it does                                                                  |
| ----------------------------- | ----------------------------------------------------------------------------- |
| `bin/setup`                   | Install dependencies on a fresh checkout                                      |
| `bin/test [paths]`            | Run the tests; pass files to run only those                                   |
| `bin/lint [--fix] [paths]`    | Check lint and formatting; `--fix` fixes what it can                          |
| `bin/typecheck`               | Type-check the code                                                           |
| `bin/generate [--watch]`      | Regenerate the generated files; `--watch` keeps them current                  |
| `bin/build`                   | Build what the repo ships                                                     |
| `bin/docs [--serve\|--check]` | Build the docs; `--serve` serves them, `--check` checks them                  |
| `bin/check`                   | `bin/lint --fix`, `bin/typecheck`, `bin/test`: run before calling a change done |
| `bin/ci`                      | Run exactly what CI runs, without fixes: run before pushing                   |

## Quick reference

- **Ruby**: 4.0.9 (CI: 4.0)
- **Autoloading**: Zeitwerk (file paths must match module/class names)
- **Namespace**: `Riffer::Rig`, compact style (`module Riffer::Rig::Tools::Read`); `version.rb` is the one exception — it must nest because the gemspec loads it before riffer
- **Third-party RBS**: managed by `rbs collection` (`rbs_collection.yaml` + committed lockfile; `.gem_rbs_collection/` is gitignored); `bin/setup` installs it, `bin/typecheck` fails if the lockfile is stale; bump the pinned collection revision deliberately, via `rbs collection update` run through `bundle exec`
- **Tests**: Minitest (Spec style: `describe`/`it`, `assert_*` assertions), `test/riffer/rig/` mirrors `lib/riffer/rig/`
- **Build**: `bin/build` fails before building if the gemspec depends on a provider SDK (`anthropic`, `openai`, `aws-sdk-bedrockruntime`) at runtime
- **Docs**: `bin/docs` builds the docs site and API reference into `_site/`; `bin/docs --serve` serves the site at http://localhost:8000; `bin/docs --check` builds both and validates every internal link and anchor
- **PR titles**: [Conventional Commits](https://www.conventionalcommits.org/) — `feat:` bumps the minor, `fix:` the patch; titles are linted in CI and become the squash commit on `main`; a PR whose code nothing in the live path reaches yet (fixes included) is `refactor:`, and the PR that wires it in carries the `feat:`/`fix:` — correct a merged title with a `BEGIN_COMMIT_OVERRIDE` … `END_COMMIT_OVERRIDE` block in the PR body
- **Releases**: release-please keeps a release PR open; merging it publishes the gem

## Where code goes

Everything in the project is one of four tiers. Ask in order; the first "yes" wins.

1. **Core** — something an extension cannot do, or something every host needs in exactly the same form?
2. **Host** — about how one front end drives the Runtime? The terminal, headless printer and ACP adapter are hosts.
3. **Bundled** — the coding toolkit (read, write, edit, bash), or a convention at least two of pi, OpenCode, Claude Code and Codex already share? It ships in the gem, is built only on the extension API, and can be disabled or replaced.
4. **Third-party** — everything else: extensions people write and publish themselves.

Three rules follow. Provider-native tools are core and off by default, so a provider change never silently changes what the agent can do. Standards never touch core: a new convention only asks whether the extension API can express it, and if not, that is a seam to add. Core lives in riffer-rig first, and moves to riffer only when a second riffer agent needs the same thing.

## Inheritance policy

Contracts are RBS interfaces in `sig/manual/`, never abstract base classes. Rig defines no class for another class to inherit from: share code through a mixin (`Support::Equatable`) or a collaborator. In `lib/`, the only superclasses allowed are framework-mandated riffer parents (`Riffer::Tool`, `Riffer::Agent`, `Riffer::Guardrail`, `Riffer::Messages::User`, `Riffer::Skills::Backend`, `Riffer::Tools::Runtime`), `StandardError` subclasses, and `Exception` itself for a signal that must escape a `rescue StandardError`; tooling outside `lib/` may subclass the parent its framework mandates (e.g. `RuboCop::Cop::Base`).

## Code style

- Prefer functional style: enumerable / array methods (`map`, `filter`, `reduce`) over manual loops.
- Favor immutability — return new values rather than mutating arguments.
- Write pure functions where possible; isolate side effects (I/O, DB, network) behind clear boundaries.
- Use a class only when an instance has identity, lifecycle, or mutable state. Otherwise use a module of pure functions. A class whose methods are all static (`self.foo`) is a module wearing pants.
- Default to composition — pass collaborators ("has-a") rather than inheriting from a parent ("is-a"). For shared _shape_, use an interface, structural type, or duck typing. Reserve inheritance for genuine "is-a" with shared _implementation_, or framework-mandated parents (`ApplicationRecord`, `Sidekiq::Worker`, custom `Error` subclasses).
- Don't use thrown exceptions for control flow — return an explicit result type, or follow the pattern this repo already uses. Reserve `throw` / `raise` for truly exceptional circumstances: programmer errors, unrecoverable state, framework-level boundaries.

### Dependency injection

Don't construct or reach for collaborators inside a function or class — accept them as constructor or function parameters, typed as the **smallest interface** that captures what the function actually uses (`Emailer` with a `send` method, not `SendgridEmailService` with its 40-method API). Wire concrete implementations at the **application edge** — `main`, the entry point, a composition root.

**Smell:** a function or class taking 8+ dependencies is doing too much — split it.

**Exempt:** framework globals that ship first-class test seams — Rails `ActiveRecord` (`User.find`, `user.save`), `ActionMailer` (`UserMailer.welcome(user).deliver_later`), `ActiveJob`. The test database, `ActionMailer::TestHelper`, and `perform_enqueued_jobs` already provide the seam DI exists to create, so calling them in place costs none of the testability or swappability the rule protects. The rule still binds collaborators that lack such a seam: third-party clients (`Stripe::Client`, an HTTP or S3 SDK) and this repo's own service objects — inject those.

## Testing

- Every module of behaviour gets a test file, even if it's only a smoke test. A unit with no behaviour — pure constants, data definitions, types — needs no test file.
- Only test what can change. Static code — generated files, constants, trivial accessors — gets at most a smoke test. Generated code is pinned at its generator: test the generator, not each generated output.
- A test file tests only the concerns of the unit it's mapped to. If testing X requires driving Y's entry point, either the behaviour belongs in X's own file with collaborators injected, or Y's file is covering for a missing X test. A behaviour belongs to the unit whose contract it is, even when observing it means calling through an object that unit returns. A composer's tests assert the composer's outcomes only — never a collaborator's branches, which are pinned in the collaborator's own file.
- Order tests the way the code is ordered: they follow the source's structure, and within a routine they follow execution order (validation behaviour first).
- Test all branches in reason: every early return, conditional, and error path gets a test — unless the branch is dead or a programmer-error tripwire.
- One assertion per test: each `it` makes exactly one `assert_*` or `expect`. A test that wants two is two tests.
- Never mock code you own. Don't patch a module, method or import to change what it does (`vi.mock`, `vi.spyOn`, `Minitest::Mock`, `stub`); pass the unit a fake through the parameters it already takes its collaborators by.

## Ruby typing

- Steep runs `D::Ruby.all_error`: every diagnostic is an error. Fix the annotation or the code; never disable a diagnostic in the Steepfile. The only escape is a targeted inline suppression with a comment saying why.
- Annotate every method in `lib/` with rbs-inline doc style: one `# @rbs name: Type` per param plus `# @rbs return: Type`, never the one-line method-type or `#:` method form. Constants and `attr_reader`s rbs-inline can't infer take a trailing `#: Type` on the same line; one on the line above is ignored.
- An `attr_reader`/`attr_writer` needs a `# @dynamic name` line directly above it, or Steep reports `MethodDefinitionMissing`.
- Declare an interface only when different objects satisfy it — two or more implementers, or a contract a consumer implements — or when a boundary forbids naming the one class. When only one class is ever passed, annotate that class; a test fake is not a second implementer.
- `sig/generated/` is written by `bin/generate` from the inline annotations: never hand-edit it, and commit it with the `lib/` change that moved it.
- `sig/manual/` mirrors `lib/` for hand-written signatures rbs-inline can't generate: interfaces, and the `extend self` re-declaration every `extend self` module needs (rbs-inline drops `extend self`). A type alias may instead be declared inline with `# @rbs!` beside the code that uses it.
- `sig/_private/` holds stubs for gaps in stdlib and third-party signatures, one file per gem or library (`open3.rbs`). Check the gem's own RBS and gem_rbs_collection before writing one, and delete the stub once real signatures exist. RBS skips `_`-prefixed directories in library mode, so the stubs never reach projects that install this one.

### Typing in this repo

- Every diagnostic Steep can emit is an error, including the hints and informations editors surface through the language server, and no method body may fall back to `untyped` for lack of an annotation. The bar applies to every change, not just new code.
- **Syntax**: the [rbs-inline Syntax guide](https://github.com/soutaro/rbs-inline/wiki/Syntax-guide) is the source of truth — defer to it over anything written here (it documents the latest release; we pin `~> 0.14`, so check what 0.14 actually supports before reaching for a newer wiki feature).
- **Coverage**: besides every method, annotate every constant and ivar rbs-inline can't infer (`MY_STRING = "a string"` needs nothing).
- **Interfaces**: `Terminal::_Sessions` is the boundary case, under the terminal's host-API allow-list. For a clock that defaults to `Time`, annotate `singleton(Time)` rather than declaring an interface.
- **Structured data**: a pure data object (fields, no behaviour) may be a `Data.define` or `Struct`; as soon as it needs any logic it becomes a hand-written frozen PORO. Never pass fixed-key hashes between methods (an RBS record type such as `{ url: String, headers: Hash[String, String] }`, inline or aliased, is the tell; parsed JSON and settings stay `Hash` until the boundary turns them into objects). rbs-inline only types a bare `Data.define` assigned to a constant nested in a module — no compact constant path, no `initialize` override, no methods in its block — so declare one nested inside its compact-style owner. For a PORO, `Mcp::Declaration` is the template: `attr_reader`s with `#: Type`, an `initialize` that assigns and freezes, plus `to_h`/`==`/`hash` when the object is compared or serialized.
- **Hand-written sigs**: `sig/manual/` also holds `Hosts::_Host`, `Events::_Event` and Zeitwerk-autovivified namespace modules; `sig/_private/` stubs are named by gem or library (`open3.rbs`, `thread.rbs`). `rbs:lint_manual` (part of `bin/typecheck`) fails if a manual/_private file outlives the module it documents.
- **Stubs**: reach for a gem's own shipped RBS or gem_rbs_collection first (both load automatically through the collection lockfile); a `sig/_private/` stub is only for a gem with no RBS anywhere or a stdlib gap (open3's missing `popen2e`). Re-check the collection when updating such a gem.

## Comments and documentation

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
- **The README is the front door**: pitch, install, quickstart, one example each of extending and embedding, and links. It never restates a guide. `bin/docs --check` validates its links along with the site's.
