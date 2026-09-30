# Getting started

## Install

riffer-rig needs Ruby 4.0 or later.

```bash
gem install riffer-rig
```

This installs the `riffer` executable.

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

The answer is saved as `model` in `~/.riffer/settings.json`, so later runs skip the question. A model already set by `--model`, `RIFFER_MODEL` or either settings file is used without asking ([Configuration](CONFIGURATION.md#model)).

Next it looks for the provider's credentials in the environment and in `~/.riffer/auth.json`. When one is missing it asks for it, reading a key without echo:

```text
anthropic api_key
› (hidden)
```

A pasted key is saved to `~/.riffer/auth.json` (permissions `600`) and reused from then on. Leaving the answer empty stops with a message naming the environment variable to set instead. [Providers](PROVIDERS.md) lists each provider's variables and where to create a key.

## The session

The banner shows the model, the working directory, how many skills were found and the version. Type a prompt and press Enter:

- the reply streams in, with each tool call (`⚙ read(path: "lib/app.rb")`) and the first line of its result;
- each turn ends with a token line, and the session cost once the model is priced ([Configuration](CONFIGURATION.md#models));
- Ctrl-C cancels a running turn; at the prompt, a second Ctrl-C exits, as do `/exit`, `/quit` and Ctrl-D.

The [README](../README.md#usage) lists the flags and slash commands.
