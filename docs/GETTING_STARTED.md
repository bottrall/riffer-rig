# Getting started

## Install

riffer-rig needs Ruby 4.0 or later.

```bash
gem install riffer-rig
```

This installs the `riffer` command.

## First run

Run `riffer` from the project you want to work on:

```bash
cd my-project
riffer
```

With no model configured, it asks for one:

```text
Which model should riffer use? Enter provider/name, with a provider from: amazon_bedrock, anthropic, azure_openai, gemini, openai, openrouter
› anthropic/claude-sonnet-4-6
```

The answer is saved to `~/.riffer/settings.json`, so later runs skip the question. [Configuration](CONFIGURATION.md#where-each-value-comes-from) lists the other places a model can come from.

If the provider's SDK gem is missing, it offers to install it ([SDK gems](PROVIDERS.md#sdk-gems)). Then it looks for the provider's API key in the environment and in `~/.riffer/auth.json`, and asks for it if it finds none:

```text
anthropic api_key
› (hidden)
```

The key is saved to `~/.riffer/auth.json` with permissions `600`. Leave the answer empty to stop and set the environment variable instead; [Providers](PROVIDERS.md) lists each provider's variables and where to create a key.

> **Tools run without asking.** The model can read and write files and run shell commands in this directory with no confirmation step. [What runs without asking](TOOLS.md#what-runs-without-asking) explains what you can restrict.

## The session

The banner shows the model, the reasoning level, the working directory and how many skills were found. Type a prompt and press Enter.

- While the turn runs, the status line under the input shows its progress, time, tokens and cost, and Ctrl-T [peeks](TERMINAL.md#peek) at what the model is writing.
- When it ends, the reply is printed, followed by a [stat line](TERMINAL.md#the-turn-report) for the turn and the session.
- You can keep typing while a turn runs: Enter [queues](TERMINAL.md#queueing-messages) the message for when the turn ends.
- Ctrl-C cancels a running turn. With no turn running, press it twice to exit, or type `/exit`.

`/help` lists the commands. [Terminal](TERMINAL.md) has every key and command, and [Command line](CLI.md) has every flag.

## What first run leaves behind

In `~/.riffer/`:

- `settings.json` — the model you picked ([Configuration](CONFIGURATION.md));
- `auth.json` — the key you pasted ([Providers](PROVIDERS.md));
- `sessions/` — one file per saved session ([Sessions](SESSIONS.md)).

Nothing is written to the project. A project `.riffer/` exists only if you add a `settings.json` or `rig.rb` to it.

## Where to next

- [Configuration](CONFIGURATION.md) — settings for every project or one
- [Tools](TOOLS.md) and [Skills](SKILLS.md) — what the agent can do out of the box
- [Extensions](EXTENSIONS.md) — your own tools, commands and prompts
- [Troubleshooting](TROUBLESHOOTING.md) — common errors and their fixes
