# Command line

```text
riffer [options]            open the terminal
riffer -p [prompt] [options] run one prompt headless and exit
riffer acp                  serve the agent over ACP on stdio
```

`riffer acp` takes no options; an editor configures it through the same [settings](CONFIGURATION.md) as the terminal ([ACP](ACP.md)).

## Flags

| Flag                         | Effect                                                                                               | Terminal | `-p` |
| ---------------------------- | ---------------------------------------------------------------------------------------------------- | :------: | :--: |
| `--model provider/name`      | the model for this run ([precedence](CONFIGURATION.md#where-each-value-comes-from))                  | ✓        | ✓    |
| `--reasoning LEVEL`          | the reasoning level for this run: `off` `low` `medium` `high` `xhigh` `max`                          | ✓        | ✓    |
| `--tools read,bash`          | only these tools, by identifier ([Tools](TOOLS.md#identifiers))                                      | ✓        | ✓    |
| `--max-steps N`              | stops a turn after `N` model calls                                                                   | ✓        | ✓    |
| `--no-extensions`            | skips the [`rig.rb` files](EXTENSIONS.md#the-rigrb-files) and gem autoload; bundled extensions still load | ✓   | ✓    |
| `--no-skills`                | leaves out [Agent Skills](SKILLS.md)                                                                 | ✓        | ✓    |
| `--no-agents-md`             | leaves out [AGENTS.md](INSTRUCTIONS.md#agentsmd)                                                     | ✓        | ✓    |
| `--no-save`                  | neither saves this session nor reads saved ones ([Sessions](SESSIONS.md#opting-out))                 | ✓        | ✓    |
| `-c`, `--continue`           | continues the most recent session in this directory ([Sessions](SESSIONS.md#resuming))               | ✓        | ✓    |
| `-r ID`, `--resume ID`       | resumes the session with that id                                                                     | ✓        | ✓    |
| `-r`, `--resume` (no id)     | opens the [session picker](SESSIONS.md#the-picker)                                                   | ✓        |      |
| `-p`, `--print`              | runs one prompt with no terminal ([Headless](HEADLESS.md))                                           |          | ✓    |
| `--json`                     | streams every event as [NDJSON](HEADLESS.md#the-ndjson-stream---json) instead of the reply text      |          | ✓    |
| `--verbose`                  | adds a one-line trace of each tool call to stderr                                                    |          | ✓    |
| `--job-idle-timeout SECONDS` | how long to wait for a [background job](HEADLESS.md#background-jobs) to exit (default 600, `0` for no limit) |  | ✓    |
| `-h`, `--help`               | prints the usage                                                                                     | ✓        | ✓    |
| `-v`, `--version`            | prints the version                                                                                   | ✓        | ✓    |

## Environment variables

| Variable           | Effect                                                                                 |
| ------------------ | -------------------------------------------------------------------------------------- |
| `RIFFER_MODEL`     | the model, below `--model` ([precedence](CONFIGURATION.md#where-each-value-comes-from)) |
| `RIFFER_REASONING` | the reasoning level, below `--reasoning`                                                |
| `NO_COLOR`         | turns colour off in the terminal                                                        |

Each provider's credential variables are listed in [Providers](PROVIDERS.md).

## Exit codes

Headless runs exit with a code that says how the turn ended; [Headless](HEADLESS.md#exit-codes) has the table.
