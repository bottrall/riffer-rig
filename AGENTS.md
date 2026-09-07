# riffer-rig

Terminal coding agent built on the riffer framework.

## Quick Reference

- **Ruby**: 4.0.5 (CI: 4.0)
- **Lint + Test + Typecheck**: `bin/ci`
- **Autoloading**: Zeitwerk (file paths must match module/class names)
- **Namespace**: `Riffer::Rig`, compact style (`module Riffer::Rig::Tools::Read`); `version.rb` is the one exception — it must nest because the gemspec loads it before riffer
- **Types**: rbs-inline annotations in `lib/` generate `sig/generated`; run `bin/rbs` after any `lib/` change and commit the result
- **Tests**: Minitest, single assertion per test, `test/riffer/rig/` mirrors `lib/riffer/rig/`
- **PR titles**: [Conventional Commits](https://www.conventionalcommits.org/) — `feat:` bumps the minor, `fix:` the patch; titles are linted in CI and become the squash commit on `main`
- **Releases**: release-please keeps a release PR open; merging it publishes the gem. The `riffer` dependency is pinned to one minor (`~> 0.45.0`) — retitle Dependabot's riffer bump `feat(deps):` or `fix(deps):` so it releases

## Commands

All wrappers delegate to the Rakefile under the hood.

| Command         | Description                                                                                   |
|-----------------|-----------------------------------------------------------------------------------------------|
| `bin/setup`     | Install dependencies on a fresh checkout                                                      |
| `bin/test`      | Run tests. Pass files and/or Minitest flags: `bin/test test/foo_test.rb -n /pattern/`         |
| `bin/lint`      | Check code style (pass `-a` to auto-fix)                                                      |
| `bin/typecheck` | Check `sig/generated` is current, then type-check with Steep                                  |
| `bin/rbs`       | Regenerate `sig/generated` from the inline annotations in `lib/`                              |
| `bin/ci`        | Run everything CI runs, serially. Use before pushing                                          |
| `bin/build`     | Build the gem into `pkg/`                                                                     |
| `bin/plans`     | Serve the building plans in `plans/` at http://localhost:8001                                 |

`bin/rake <task>` is the escape hatch for any rake task without a named wrapper.
