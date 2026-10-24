# Headless mode

`riffer -p "prompt"` runs one prompt with no terminal and exits with a code that says how it ended. It loads everything the terminal does — settings, credentials, extensions, skills, AGENTS.md — so CI jobs, cron jobs and other programs drive riffer-rig just as you would.

## The prompt

```bash
riffer -p "what does this repo do"
git diff | riffer -p "review this diff"   # stdin is added to the prompt as context
echo "explain this diff" | riffer -p      # stdin alone is the prompt
```

Slash commands are not run: the text goes to the model as typed.

With a prompt argument, riffer waits up to 3 seconds for stdin to send data or close. If it does neither, it warns on stderr and runs the argument alone; once data arrives, it reads stdin to the end. A program that spawns riffer with a stdin pipe it never closes (Node's `child_process.spawn`, Python's `subprocess.PIPE`) pays those 3 seconds on every run, and a shell loop that reads its own stdin loses the rest of its input to the first run. Redirect stdin from `/dev/null` in both cases:

```bash
while read -r p; do riffer -p --no-save "$p" </dev/null; done < prompts.txt
```

## Output

Only the assistant's reply goes to stdout, streamed as it arrives. Everything else goes to stderr: errors, warnings, notices from extensions, and `session <id>` when the session starts — the id `riffer -p -r <id> "follow-up"` resumes — and any [`--verbose`](CLI.md#flags) traces. Reasoning is not printed.

## Flags

Every terminal flag works here, plus `--json`, `--verbose` and `--job-idle-timeout` ([Command line](CLI.md#flags)).

`-c` and `-r <id>` continue a session across runs: `riffer -p -c "now run the tests"` carries on the most recent session in this directory. If there is no such session, headless exits 2 rather than starting a fresh one.

Headless never asks anything. A missing model, credential or [SDK gem](PROVIDERS.md#sdk-gems) prints what to set or install on stderr and exits 2, as does a settings or `auth.json` file that doesn't parse. A project `rig.rb` you haven't trusted in the terminal is skipped.

## Background jobs

When the model finishes with [background jobs](TOOLS.md#background-jobs) still running, headless prints `waiting for background jobs` on stderr and waits; the run exits once no job is left.

| While it waits                                              | Headless                                                                                     |
| ----------------------------------------------------------- | -------------------------------------------------------------------------------------------- |
| a job exits                                                 | gives the model a further turn to react, printed like the first                              |
| no job has exited for the [`--job-idle-timeout`](CLI.md#flags) | kills the rest and exits 3, so a dev server or file watcher can't hold a run open forever |
| a turn fails, is cancelled or doesn't complete              | kills its jobs and exits at once                                                             |

## Exit codes

| Exit  | Meaning                                                                                                                       |
| ----- | ----------------------------------------------------------------------------------------------------------------------------- |
| `0`   | the turn finished, and so did every background-job follow-up                                                                   |
| `1`   | runtime error: provider or network failure, an exception in a tool or extension                                               |
| `2`   | usage or configuration: unknown flag, no prompt, a bare model name, no credentials, a missing SDK gem, a file that doesn't parse, no session to resume |
| `3`   | the turn ended without completing — the step limit, the context window, an output length limit, a content filter, malformed output — or background jobs passed the idle timeout; the reason is on stderr |
| `130` | interrupted (SIGINT): the turn is cancelled, background jobs are killed, and the session is saved                              |

With follow-up turns, the code is the last turn's.

## The NDJSON stream (`--json`)

`--json` replaces the reply text on stdout with one JSON object per line, one for every event of the run. Each record is flat: the event's fields plus a `type`.

```json
{"type":"session_start","id":"0198…","reason":"new"}
{"role":"assistant","content":"Reading the failing test first.","type":"text_done"}
{"role":"assistant","item_id":"call_1","call_id":"call_1","name":"read","arguments":"{\"path\":\"x\"}","type":"tool_call_done"}
{"type":"before_tool_call","call_id":"call_1","tool":"read","args":{"path":"x"},"at":81234.513}
{"type":"after_tool_call","call_id":"call_1","tool":"read","args":{"path":"x"},"result":{"content":"1: …","error":null,"error_type":null},"at":81234.531,"duration":0.018}
{"stop_reason":"completed","usage":{"input_tokens":1423,"output_tokens":89},"type":"turn_end"}
```

| `type`                                  | When                                                                                  |
| --------------------------------------- | ------------------------------------------------------------------------------------- |
| `session_start`                         | first, once per run; carries the session `id`                                         |
| `text_delta`, `text_done`               | the reply as it streams, then complete                                                |
| `reasoning_delta`, `reasoning_done`     | the model's reasoning, when the provider sends it                                     |
| `tool_call_delta`, `tool_call_done`     | a tool call the model makes                                                           |
| `before_tool_call`, `after_tool_call`   | a tool starting and finishing ([fields](EVENTS.md#tool-call-events))                  |
| `token_usage_done`                      | each model call's token usage                                                         |
| `job_exit`                              | a background job's exit, as the model is told of it                                   |
| `notify`                                | a warning or notice that text mode prints on stderr                                   |
| `turn_end`                              | last record of every turn: `stop_reason`, and `usage` with `cost` when the model is priced |
| `error`                                 | a fatal error, as the final record: `{"type": "error", "message": "…"}`               |

Other riffer stream events — web search, guardrails, interrupts — appear the same way when they happen ([Events](EVENTS.md)). A consumer that only reads the last `turn_end` still knows how the turn ended and what it cost.

The stdin warning, `waiting for background jobs`, the exit-3 reason and `--verbose` traces stay on stderr.
