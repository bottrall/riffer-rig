# riffer-rig

**riffer, in your terminal and in your process.**

`riffer-rig` is a general-purpose agent for Ruby developers who want to own their harness. It runs in your terminal, and because the runtime is separate from the terminal it also runs inside any Ruby process: a Rails app, a script, a job. You extend it in Ruby — tools, commands, providers and hooks are ordinary classes on [riffer](https://riffer.ai)'s primitives, and the same objects work in the terminal and in your app.

It ships with a coding toolkit (read, write, edit, bash) because a shell and file access get almost any task done, but nothing in its prompt makes it a coding agent. Tools run without asking for permission; see [what runs without asking](docs/TOOLS.md#what-runs-without-asking).

## Install

Requires Ruby 4.0 or later.

```bash
gem install riffer-rig
```

## Quickstart

```bash
cd my-project
riffer
```

The first run asks for a model as `provider/name` — for example `anthropic/claude-sonnet-4-6` — and then for that provider's API key, and saves both under `~/.riffer/`. `gemini/…` models work straight away; other providers' SDK gems are [offered for install](docs/PROVIDERS.md#sdk-gems) on first use.

Type a prompt and press Enter. `/help` lists the commands, and [Getting started](docs/GETTING_STARTED.md) walks through a first session.

To run one prompt from a script or CI job:

```bash
git diff | riffer -p "review this diff"
```

[Headless](docs/HEADLESS.md) covers exit codes and the NDJSON stream; editors connect over [ACP](docs/ACP.md) with `riffer acp`.

## Extend it

An extension is a Ruby block in `~/.riffer/rig.rb` (every project) or `.riffer/rig.rb` (one project):

```ruby
Riffer::Rig.extension('git') do |rig|
  rig.command('log', description: 'Recent commits') { |ctx| ctx.say `git log --oneline -n 10` }
  rig.prompt(:branch) { "Current branch: #{`git branch --show-current`}" }
end
```

That adds a `/log` command and puts the current branch in the system prompt on every turn. Extensions can also add tools, hooks, skills, MCP servers, settings and providers — [Extensions](docs/EXTENSIONS.md) starts with a complete tool.

## Embed it

```ruby
runtime = Riffer::Rig::Loader.runtime(cwd: Dir.pwd, host: Riffer::Rig::Hosts::Null.new)
puts runtime.ask('why is this test failing?').content
```

This builds the same agent the terminal does, from the same settings, credentials and extensions. [Embedding](docs/EMBEDDING.md) covers streaming, cancelling, snapshots and reloading.

## Documentation

The guides are at **<https://riffer.bottrall.dev>**, and their sources are in [`docs/`](docs/). Good places to start:

- [Overview](docs/OVERVIEW.md) — what riffer-rig is and how it fits together
- [Configuration](docs/CONFIGURATION.md) — settings and where each value comes from
- [Command line](docs/CLI.md) — every flag
- [Extensions](docs/EXTENSIONS.md) — your own tools, commands and hooks

## Development

```bash
bin/setup   # install gems and RBS signatures
bin/ci      # lint, test, type-check and build the docs, as CI does
```

`AGENTS.md` lists every script and the project's conventions. PR titles follow [Conventional Commits](https://www.conventionalcommits.org/); [release-please](https://github.com/googleapis/release-please) turns them into releases.

## Contributing

Fork the repository, make your change on a branch, run `bin/ci`, and open a pull request with a clear description. Please follow the [Code of Conduct](CODE_OF_CONDUCT.md).

## License

MIT — see [`LICENSE.txt`](LICENSE.txt). Maintained by [Jake Bottrall](https://github.com/bottrall).
