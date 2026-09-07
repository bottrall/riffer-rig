# riffer-rig

A dead-simple terminal coding agent built on [riffer](https://github.com/janeapp/riffer).

`riffer-rig` is an interactive terminal coding agent with read, write, edit, and bash tools — point it at your project and chat with it from the command line.

## Requirements

- Ruby >= 4.0

## Installation

Install the gem:

```bash
gem install riffer-rig
```

This provides a `riffer` executable.

## Usage

Run the agent from any project directory:

```bash
riffer
```

### Authentication

`riffer-rig` talks to Anthropic. Provide your API key in either of two ways:

- Set the `ANTHROPIC_API_KEY` environment variable, or
- Run `riffer` and paste your key when prompted on first launch. It is saved to `~/.riffer/auth.json` (file permissions `600`) for subsequent runs.

Create a key at https://console.anthropic.com/settings/keys.

### Configuration

- `RIFFER_MODEL` — override the default model.
- `AGENTS.md` — if present, an `AGENTS.md` in the current working directory and/or a global `~/.riffer/AGENTS.md` is loaded as additional context.

## Development

Every project chore is a script in `bin/`. The Rakefile behind them is an implementation detail; you never need to call rake directly.

| Script          | What it does                                                                                   |
| --------------- | ---------------------------------------------------------------------------------------------- |
| `bin/setup`     | Install dependencies on a fresh checkout                                                       |
| `bin/test`      | Run the test suite. Pass files and/or Minitest flags: `bin/test test/foo_test.rb -n /pattern/` |
| `bin/lint`      | Run RuboCop. Arguments are forwarded, e.g. `bin/lint -a`                                       |
| `bin/typecheck` | Check `sig/generated` is current, then type-check with Steep                                   |
| `bin/rbs`       | Regenerate `sig/generated` from the inline annotations in `lib/`                               |
| `bin/rbs-watch` | Regenerate `sig/generated` whenever `lib/` changes                                             |
| `bin/ci`        | Run everything CI runs, serially. Use before pushing                                           |
| `bin/build`     | Build the gem into `pkg/`; the publish workflow runs this before `gem push`                    |
| `bin/plans`     | Serve the building plans in `plans/` at http://localhost:8001                                  |

## Releasing

PR titles are [conventional commits](https://www.conventionalcommits.org/) and are linted in CI: `feat:` bumps the minor version, `fix:` bumps the patch, and `feat!:` marks a breaking change (also a minor bump while we are on 0.x). `chore:`, `docs:`, `ci:`, `refactor:` and `test:` never release. Squash-merging makes the title the commit on `main`.

[release-please](https://github.com/googleapis/release-please) keeps a release PR open that bumps `lib/riffer/rig/version.rb` and writes `CHANGELOG.md`. Merging that PR tags `vX.Y.Z`, creates the GitHub Release and publishes the gem to RubyGems.org through Trusted Publishing nothing is pushed by hand.

riffer is pinned to one minor (`~> 0.45.0`) because its 0.x minors may break. When Dependabot opens the riffer bump, retitle it `feat(deps):` or `fix(deps):` before merging so it releases and appears in the changelog.

## Contributing

1. Fork the repository and create your branch: `git checkout -b feature/foo`
2. Run the tests and linters locally.
3. Submit a pull request with a clear description of the change.

Please follow the [Code of Conduct](CODE_OF_CONDUCT.md).

## License

Licensed under the MIT License. See [`LICENSE.txt`](LICENSE.txt) for details.

## Maintainer

- Jake Bottrall - https://github.com/bottrall
