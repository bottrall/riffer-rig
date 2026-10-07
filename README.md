# riffer-rig

**riffer, in your terminal and in your process.**

`riffer-rig` is a general-purpose agent for Ruby developers who want to own their harness. It runs as a terminal agent and, because the runtime is separate from the terminal, it also runs inside any Ruby process: a Rails app, a script, a job. You extend it in Ruby: tools, commands, providers and hooks are ordinary Ruby classes on [riffer](https://github.com/janeapp/riffer)'s primitives, and the same objects work whether the host is the terminal or your app. It ships with a coding toolkit (read, write, edit, bash) as the default bundle, because a shell and file access are the most efficient way to get almost any task done — but the prompt gives it no coding identity. [Overview](docs/OVERVIEW.md) has the full thesis.

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
| `--no-save`             | does not save this session to the [store](docs/SESSIONS.md)                 |
| `-c`, `--continue`      | continues the most recent session in this directory ([Sessions](docs/SESSIONS.md#resuming)) |
| `-r ID`, `--resume ID`  | resumes the session with id `ID`; bare `-r` opens the [picker](docs/SESSIONS.md#the-picker) ([Sessions](docs/SESSIONS.md#resuming)) |
| `-h`, `--help`          | prints the usage                                                            |

An editor registers the agent as `riffer acp`, the same Runtimes over the [Agent Client Protocol](https://agentclientprotocol.com) on stdio ([ACP](docs/ACP.md)).

### Headless

Run one prompt with no terminal ([Headless](docs/HEADLESS.md)):

```bash
riffer -p "what does this repo do"
git diff | riffer -p "review this diff"   # piped stdin appended as context
echo "explain this diff" | riffer -p      # piped stdin alone is the prompt
```

Everything loads exactly as the REPL does, the shared flags work the same — `-c` and `-r` included: `riffer -p -c "now run the tests"` continues the most recent session in this directory, and a missing session exits 2 ([Headless](docs/HEADLESS.md)). The session is saved like any other unless `--no-save`. Only the assistant's text is printed, streamed to stdout; errors and warnings go to stderr, and `--verbose` adds a one-line trace of each tool call there. With `--json`, stdout is instead one JSON object per line for every Runtime event — the NDJSON stream ([Headless](docs/HEADLESS.md#the-ndjson-stream---json)). Headless never prompts: a missing model, credential, or SDK prints the reason on stderr and exits 2.

The exit code says how the turn ended: `0` finished, `1` runtime error, `2` usage or configuration, `3` the turn ended without completing (`--max-steps`, a full context window, a provider content filter), `130` SIGINT (the turn is cancelled first).

### In the session

Type a prompt and press Enter; the reply streams in, with each tool call and the first line of its result, and every turn ends with a token line (`↑in · ↓out · session N tok`, plus the session cost when the model is [priced](docs/CONFIGURATION.md#models)).

- Ctrl-C during a turn cancels it and returns to the prompt. Ctrl-C at the prompt asks for a second one, which exits.
- `/exit` or `/quit` ends the session, as does Ctrl-D.
- `/resume [--all]` opens the [session picker](docs/SESSIONS.md#the-picker): type to filter, switch with Enter on a single match or a row number, and delete with Ctrl-D and a confirm. `/new` starts a fresh session in place; the one you left stays on disk. Both replace the session the terminal drives and re-render the banner.
- `/model provider/name` switches the model ([below](#switching-the-model)), and `/skill:<name> [text]` runs a skill ([Skills](docs/SKILLS.md)).
- Any other `/name args` runs the Runtime command of that name, such as one an extension registers ([Extensions](docs/EXTENSIONS.md)); an unknown name is reported and nothing is sent to the model.

### Switching the model

`/model provider/name` switches the model for the current session only, keeping the conversation so far — `/model openai/gpt-5`, say. The provider prefix is required: a bare name such as `/model sonnet` is rejected with the list of providers. `/model` alone shows the model in use. Switching runs the same setup for the new provider as startup does: its SDK gem is offered for install (or refused with the exact Gemfile line), and missing credentials are resolved — you are prompted for them when the host can ask, and the values apply to the running session immediately. The switch is refused with one error when the host cannot supply what is missing, and the model is left unchanged. `/model --save` writes the model in effect to the home `settings.json`, so new sessions start with it; `/model provider/name --save` switches and saves in one step, and a refused switch saves nothing ([Configuration](docs/CONFIGURATION.md#model)).

## Authentication

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

## Configuration

Settings live in two scopes, both optional: `~/.riffer/settings.json` for every project, and `<cwd>/.riffer/settings.json` for one project, merged key by key with the project winning ([Configuration](docs/CONFIGURATION.md)). Every core key is optional:

| Key          | What it sets                                                                     |
| ------------ | -------------------------------------------------------------------------------- |
| `model`      | the model new sessions start with, as `provider/name`                            |
| `reasoning`  | the reasoning effort, translated to the provider's own parameter                 |
| `models`     | prices each model in USD per million tokens                                      |
| `providers`  | non-secret provider fields such as an endpoint or region (home file only)        |
| `extensions` | `disabled` — bundled extensions to leave out; `autoload` — gem extension autoload |
| `reload`     | `"auto"` (default) or `"manual"` — the hot-reload trigger                        |
| `sessions`   | `save: false` stops saving sessions to the store                                 |
| `tools`      | the provider-native tool switches (`native`), off by default                     |

- `RIFFER_MODEL` — the model for this run as `provider/name`, winning over the `model` setting. A bare name such as `sonnet` is rejected with the list of providers.
- `AGENTS.md` — `~/.riffer/AGENTS.md` and an `AGENTS.md` in the current working directory or any directory above it are re-read every turn as instructions that take precedence over the default norms ([Instructions](docs/INSTRUCTIONS.md#agentsmd)).
- Skills — Agent Skills in `.agents/skills/` from the working directory up to the repository root, and in `~/.agents/skills/`, are offered to the model, and `/skill:<name> [text]` runs one ([Skills](docs/SKILLS.md)).
- MCP servers — declared under the `mcp` key in either settings file and registered with the Runtime ([MCP](docs/MCP.md)).

## Extending

An extension is a named registrar block in a `rig.rb` file — `~/.riffer/rig.rb` runs in every project, `<project>/.riffer/rig.rb` in one, and the first run of a project file asks you to trust it:

```ruby
Riffer::Rig.extension('git') do |rig|
  # A tool the model can call
  rig.tool GitLog

  # A /log command in the session
  rig.command('log', description: 'Recent commits') do |ctx|
    ctx.say `git log --oneline -n #{ctx.args}`
  end

  # A section appended to the system message, re-read every turn
  rig.prompt(:branch) { |ctx| "Branch: #{`git branch --show-current`}" }
end
```

Tools, commands, prompt sections, event handlers, skills, MCP servers and providers register the same way, and the same objects work whether the host is the terminal or your app. [Extensions](docs/EXTENSIONS.md) has all eight seams, error isolation, and packaging an extension as a gem.

## Embedding

The runtime is separate from the terminal, so the same agent runs inside any Ruby process:

```ruby
runtime = Riffer::Rig::Loader.runtime(cwd: Dir.pwd, host: Riffer::Rig::Hosts::Null.new)
response = runtime.ask('why is this test failing?')
puts response.content
```

`Loader.runtime` applies the same filesystem conventions as the terminal — settings, credentials, `rig.rb`, skills. [Embedding](docs/EMBEDDING.md) has the streaming `prompt`, snapshots, and rebuilding after a code reload.

## Documentation

The guides, in reading order:

Start here:

- [Overview](https://riffer.bottrall.dev/guides/overview/) — What riffer-rig is, the four tiers, the runtime and host layers
- [Getting started](https://riffer.bottrall.dev/guides/getting-started/) — Install, pick a model, first session

Using the terminal:

- [Configuration](https://riffer.bottrall.dev/guides/configuration/) — Settings scopes and every core key
- [Instructions](https://riffer.bottrall.dev/guides/instructions/) — How the system message is built; AGENTS.md
- [Tools](https://riffer.bottrall.dev/guides/tools/) — The bundled toolkit and provider-native tools
- [Skills](https://riffer.bottrall.dev/guides/skills/) — Agent Skills directories and activation
- [MCP](https://riffer.bottrall.dev/guides/mcp/) — Declaring MCP servers
- [Sessions](https://riffer.bottrall.dev/guides/sessions/) — Saving, resuming, the picker, the JSONL store
- [Reloading](https://riffer.bottrall.dev/guides/reloading/) — The /reload command, what reloads and what does not
- [Headless](https://riffer.bottrall.dev/guides/headless/) — riffer -p, NDJSON, exit codes
- [ACP](https://riffer.bottrall.dev/guides/acp/) — riffer acp, the ACP agent over stdio

Extending and embedding:

- [Extensions](https://riffer.bottrall.dev/guides/extensions/) — rig.rb, the registrar, the eight seams, commands, handlers, gems
- [Embedding](https://riffer.bottrall.dev/guides/embedding/) — Runtime and Loader from Ruby; snapshots; rebuild
- [Hosts](https://riffer.bottrall.dev/guides/hosts/) — The Host interface and writing a host

Providers:

- [Providers](https://riffer.bottrall.dev/guides/providers/overview/) — Model strings, precedence, credentials, /auth
- [Custom providers](https://riffer.bottrall.dev/guides/providers/custom/) — Registering a provider from an extension; the setup, credentials, listings

The guide sources are in `docs/`. To preview the site locally, run `bin/docs serve` and open <http://localhost:8000>.

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