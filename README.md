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

This provides a `riffer` executable. No provider SDK is installed with it: `gemini/…` models work out of the box, and every other provider's SDK gem is either installed on its first use — `riffer-rig` asks, then installs it in-process — or added to a Gemfile ahead of time:

```ruby
gem 'anthropic', '~> 1.69'
```

[Providers](docs/PROVIDERS.md#sdk-gems) lists each provider's gem and how the install offer works.

## Usage

Run the agent from any project directory:

```bash
riffer
```

The first run asks which model to use, as `provider/name` (for example `anthropic/claude-sonnet-4-6`), and saves the answer as `model` in `~/.riffer/settings.json`; it then asks for any missing credential ([Authentication](#authentication)). After that, `riffer` opens straight into the prompt. [Getting started](docs/GETTING_STARTED.md) walks through a first session.

The model is the first of these that is set: `--model`, `RIFFER_MODEL`, `model` in `<cwd>/.riffer/settings.json`, then in `~/.riffer/settings.json` ([Configuration](docs/CONFIGURATION.md#model)).

### Flags

| Flag                    | Effect                                                                     |
| ----------------------- | -------------------------------------------------------------------------- |
| `--model provider/name` | the model for this session, over `RIFFER_MODEL` and the settings            |
| `--no-extensions`       | skips the [`rig.rb` files](docs/EXTENSIONS.md#the-rigrb-files) and gem autoload; the bundle still loads |
| `--no-skills`           | leaves out [Agent Skills](docs/SKILLS.md)                                   |
| `--no-agents-md`        | leaves out the [AGENTS.md](docs/INSTRUCTIONS.md#agentsmd) instructions      |
| `--tools read,bash`     | only these tools, by identifier ([Tools](docs/TOOLS.md))                    |
| `--max-steps N`         | stops a turn after `N` model calls                                          |
| `-h`, `--help`          | prints the usage                                                            |

`riffer -p` (one prompt, no terminal) and `riffer acp` (an editor's agent over stdio) are reserved: for now each prints the usage and exits with status 2.

### In the session

Type a prompt and press Enter; the reply streams in, with each tool call and the first line of its result, and every turn ends with a token line (`↑in · ↓out · session N tok`, plus the session cost when the model is [priced](docs/CONFIGURATION.md#models)).

- Ctrl-C during a turn cancels it and returns to the prompt. Ctrl-C at the prompt asks for a second one, which exits.
- `/exit` or `/quit` ends the session, as does Ctrl-D.
- `/model provider/name` switches the model ([below](#switching-the-model)), and `/skill:<name> [text]` runs a skill ([Skills](docs/SKILLS.md)).
- Any other `/name args` runs the Runtime command of that name, such as one an extension registers ([Extensions](docs/EXTENSIONS.md)); an unknown name is reported and nothing is sent to the model.

### Authentication

`riffer-rig` talks to the provider named by the model's prefix — `anthropic/claude-sonnet-4-6` means Anthropic. Provide that provider's credentials in either of two ways:

- Set the provider's environment variables, or
- Run `riffer` and paste each missing value when prompted on first launch. Secrets are saved to `~/.riffer/auth.json` (file permissions `600`); plain values such as an endpoint or region are saved to the `providers` block in `~/.riffer/settings.json`.

Each value resolves on its own: environment variable first, then the stored value, then a provider-specific fallback (the AWS shared config for the Bedrock region), then the prompt. Optional values are never prompted for.

| Provider         | Environment variables                                                     | Guide                                              |
| ---------------- | ------------------------------------------------------------------------- | -------------------------------------------------- |
| `anthropic`      | `ANTHROPIC_API_KEY`                                                       | [Anthropic](docs/PROVIDERS.md#anthropic)           |
| `openai`         | `OPENAI_API_KEY`; optional `OPENAI_BASE_URL`                              | [OpenAI](docs/PROVIDERS.md#openai)                 |
| `gemini`         | `GEMINI_API_KEY`                                                          | [Gemini](docs/PROVIDERS.md#gemini)                 |
| `openrouter`     | `OPENROUTER_API_KEY`                                                      | [OpenRouter](docs/PROVIDERS.md#openrouter)         |
| `azure_openai`   | `AZURE_OPENAI_ENDPOINT`, `AZURE_OPENAI_API_KEY`                           | [Azure OpenAI](docs/PROVIDERS.md#azure-openai)     |
| `amazon_bedrock` | `AWS_REGION` or `AWS_DEFAULT_REGION`; optional `AWS_BEARER_TOKEN_BEDROCK` | [Amazon Bedrock](docs/PROVIDERS.md#amazon-bedrock) |

`auth.json` holds one typed entry per provider, and a stored secret may be a literal, a `$ENV_VAR` reference or a `!shell command` whose stdout is the secret:

```json
{
  "anthropic": { "type": "api_key", "api_key": "sk-ant-…" },
  "openai": { "type": "api_key", "api_key": "!security find-generic-password -s openai -w" }
}
```

The flat `{"anthropic": "sk-…"}` shape earlier versions wrote is no longer read; paste the key again when prompted. [Providers](docs/PROVIDERS.md) has the full format.

Inside a session, `/auth` lists every provider with where its secret comes from — `env`, `stored`, `chain` (the SDK's own credential chain, for Bedrock) or `missing`. `/auth <provider>` re-runs that provider's setup, which is how you rotate a key, and applies the new values to the current session, so the next request uses them. `/auth remove <provider>` deletes the provider's `auth.json` entry and its `providers` block in settings.

### Switching the model

`/model provider/name` switches the model for the current session only, keeping the conversation so far — `/model openai/gpt-5`, say. The provider prefix is required: a bare name such as `/model sonnet` is rejected with the list of providers. `/model` alone shows the model in use. The switch is refused when the session has no credentials for the new provider, and it never changes `settings.json`; set `model` there to change the model new sessions start with ([Configuration](docs/CONFIGURATION.md#model)).

### Configuration

- `AGENTS.md` — `~/.riffer/AGENTS.md` and an `AGENTS.md` in the current working directory or any directory above it, whichever exist, are re-read every turn as instructions that take precedence over the default norms ([Instructions](docs/INSTRUCTIONS.md#agentsmd)).
- Skills — Agent Skills in `.agents/skills/` from the current working directory up to the repository root, and in `~/.agents/skills/`, are offered to the model, and each can be run with `/skill:<name>` ([Skills](docs/SKILLS.md)).
- `RIFFER_MODEL` — the model for this run as `provider/name`, winning over the `model` setting. A bare name such as `sonnet` is rejected with the list of providers.
- `~/.riffer/settings.json` — optional user settings, and `<cwd>/.riffer/settings.json` for one project, merged key by key with the project winning. Every key is optional:

  ```json
  {
    "model": "anthropic/claude-sonnet-4-6",
    "reasoning": "low",
    "models": {
      "anthropic/claude-sonnet-4-6": {
        "input": 3.0,
        "output": 15.0,
        "cache_write": 3.75,
        "cache_read": 0.3
      }
    }
  }
  ```

  `model` is the model new sessions start with; a host built on the [Loader](docs/EMBEDDING.md#building-a-runtime-with-the-loader) asks for one when none is set and writes the answer here. `extensions.disabled` (for example `["mcp"]`) leaves bundled extensions out. `models` prices each model in USD per million tokens; [Configuration](docs/CONFIGURATION.md) has every key. `reasoning` is translated to the provider's own parameter — Anthropic accepts `low`, `medium`, `high`, `xhigh` and `max`; OpenAI and OpenRouter accept `low`, `medium`, `high` and `xhigh`. Omitting it, or supplying an unrecognised value, leaves the model's default reasoning behaviour unchanged.

## Development

Every project chore is a script in `bin/`. The Rakefile behind them is an implementation detail; you never need to call rake directly.

| Script          | What it does                                                                                   |
| --------------- | ---------------------------------------------------------------------------------------------- |
| `bin/setup`     | Install dependencies on a fresh checkout (gems + rbs collection)                               |
| `bin/test`      | Run the test suite. Pass files and/or Minitest flags: `bin/test test/foo_test.rb -n /pattern/` |
| `bin/lint`      | Run RuboCop. Arguments are forwarded, e.g. `bin/lint -a`                                       |
| `bin/typecheck` | Check the rbs collection lockfile and `sig/generated` are current, then type-check with Steep  |
| `bin/rbs`       | Regenerate `sig/generated` from the inline annotations in `lib/`                               |
| `bin/rbs-watch` | Regenerate `sig/generated` whenever `lib/` changes                                             |
| `bin/ci`        | Run everything CI runs, serially. Use before pushing                                           |
| `bin/build`     | Build the gem into `pkg/`; the publish workflow runs this before `gem push`                    |
| `bin/docs`      | Build the docs site and API reference into `_site/`; `bin/docs serve` serves it at http://localhost:8000 |
| `bin/plans`     | Serve the building plans in `plans/` at http://localhost:8001                                  |

## Releasing

PR titles are [conventional commits](https://www.conventionalcommits.org/) and are linted in CI: `feat:` bumps the minor version, `fix:` bumps the patch, and `feat!:` marks a breaking change (also a minor bump while we are on 0.x). `chore:`, `docs:`, `ci:`, `refactor:` and `test:` never release. Squash-merging makes the title the commit on `main`.

[release-please](https://github.com/googleapis/release-please) keeps a release PR open that bumps `lib/riffer/rig/version.rb` and writes `CHANGELOG.md`. Merging that PR tags `vX.Y.Z`, creates the GitHub Release and publishes the gem to RubyGems.org through Trusted Publishing; nothing is pushed by hand.

riffer is pinned to one minor (`~> 0.49.0`) because its 0.x minors may break. When Dependabot opens the riffer bump, retitle it `feat(deps):` or `fix(deps):` before merging so it releases and appears in the changelog.

## Contributing

1. Fork the repository and create your branch: `git checkout -b feature/foo`
2. Run the tests and linters locally.
3. Submit a pull request with a clear description of the change.

Please follow the [Code of Conduct](CODE_OF_CONDUCT.md).

## License

Licensed under the MIT License. See [`LICENSE.txt`](LICENSE.txt) for details.

## Maintainer

- Jake Bottrall - https://github.com/bottrall
