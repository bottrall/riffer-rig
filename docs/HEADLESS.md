# Headless mode

Run one prompt with no terminal: `riffer -p "prompt"` runs a single turn through everything the REPL loads, waits for any [background jobs](#background-jobs) the turn left running, and exits with a code that says how it ended. A pipe in, a pipe out — CI jobs, cron jobs, and other tools drive riffer-rig exactly as a human does, minus the TTY.

## The prompt

The prompt is the argument:

```bash
riffer -p "what does this repo do"
```

Piped stdin is appended to the argument as context, and with no argument stdin alone is the prompt. Bytes that are not valid UTF-8 are replaced. A TTY stdin is never read, so `riffer -p` in a terminal without an argument has nothing to run and exits 2.

```bash
git diff | riffer -p "review this diff"   # argument + stdin as context
echo "explain this diff" | riffer -p      # stdin is the prompt
```

The turn is one prompt: slash commands are not dispatched, and the session is saved like any other unless `--no-save` is given.

## Output

By default only the assistant's text is printed, streamed to stdout. Everything else goes to stderr: errors, configuration refusals, and the [notify](HOSTS.md) lines extensions and the Runtime emit. Reasoning is not printed. `--verbose` adds a one-line trace of each tool call to stderr.

## Flags

The REPL's flags all work here: `--model provider/name`, `--no-extensions`, `--no-skills`, `--no-agents-md`, `--tools a,b,c`, `--max-steps N`, `--no-save`, `-c`/`--continue` and `-r ID`/`--resume ID`, plus `--verbose` and `--job-idle-timeout SECONDS`. The same [resolution order](PROVIDERS.md#resolution-order) applies to the model: `--model`, then `RIFFER_MODEL`, then settings.

`-c` and `-r` are the multi-turn headless story: `riffer -p -c "now run the tests"` continues the most recent session in this directory, appending to the same [session file](SESSIONS.md#resuming). Unlike the REPL, a missing session is not a fresh start — headless prints `No saved session …` on stderr and exits 2 (`Sessions are off for this run (--no-save).` under [`--no-save`](SESSIONS.md#opting-out), and `Session … was saved in …, which no longer exists.` when the [directory the session runs in](SESSIONS.md#resuming) is gone).

Headless never prompts. A missing model, a missing credential, or a missing optional SDK is not an interactive setup flow — the reason is printed on stderr with the provider's recipe (its environment variables and key URL), or the exact `gem install` line, and the process exits 2. A `settings.json` or `auth.json` that does not parse exits 2 the same way, with the file named on stderr ([Configuration](CONFIGURATION.md)).

## Background jobs

A `bash` call with `run_in_background` starts a job that outlives the turn ([Tools](TOOLS.md#background-jobs)). When the model finishes its reply with a job still running, headless does not exit: it prints `waiting for background jobs` on stderr and waits for the next job to exit. Each exit gives the model a further turn, with no user text, in which it is told of the exit and replies; its output is printed like the first turn's, set off from the text before it by a blank line (in `--json` mode the records stay one per line). The run waits again while any job is still running, and exits once none is left, so a model that starts five jobs and replies that it is waiting hears of all five. A run that starts no background job exits as soon as its turn ends.

Only a turn that finished is followed this way. A turn that failed, was cancelled or did not complete (exit `1`, `130` or `3` below) ends the run at once, and the jobs it left running are killed.

The wait has an idle timeout: when no job has exited for `--job-idle-timeout` seconds, 600 by default, headless prints `no background job exited in 600s; killing the jobs still running` on stderr, kills them, and exits 3. It is what keeps a dev server or a file watcher from holding the run open forever. `--job-idle-timeout 0` removes the timeout, and the run waits for as long as any job runs. Each wait starts the timeout afresh, so it counts from the end of the most recent turn.

SIGINT while waiting kills the jobs and exits 130.

## Exit codes

| Exit | Meaning                                                                                                                                |
| ---- | -------------------------------------------------------------------------------------------------------------------------------------- |
| `0`  | the turn finished, and so did every [follow-up turn](#background-jobs)                                                                  |
| `1`  | runtime error: provider failure, network failure, an exception in a tool or handler                                                     |
| `2`  | usage or configuration: unknown flag, no prompt, a bare model name, no credentials, a missing optional SDK, a settings or auth file that does not parse |
| `3`  | the turn ended but did not complete: `max_steps`, `context_window`, `length`, `content_filter`, or `malformed_output`; the reason is on stderr. Also a run whose background jobs passed the [idle timeout](#background-jobs) |
| `130` | SIGINT: the turn is cancelled first — orphaned tool calls healed, the session closed — then exit. While waiting for background jobs, they are killed and the session closed |

With follow-up turns, the code is the last turn's. A script that only needs success or failure can therefore test the code alone; a caller that wants the reason reads stderr or waits for `--json` (below).

## The NDJSON stream (`--json`)

`--json` replaces the streamed text with one JSON object per line on stdout, one record for every event the Runtime yields: riffer's [StreamEvents](https://github.com/bottrall/riffer) plus the rig-level events (`session_start`, `notify`, `before_tool_call`, `after_tool_call`, `job_exit`, `turn_end`). The envelope is flat — the event's `to_h` fields, plus a `"type"` of the snake_case event class (`text_delta`, `tool_call_done`, `session_start`, `turn_end`, …). Nested riffer values (a `TokenUsage`, an assistant message, a tool response) serialize through their own `to_h`.

```json
{"type":"session_start","id":"0198…","reason":"new"}
{"message":"heads up","level":"warning","type":"notify"}
{"role":"assistant","content":"Reading the failing test first. ","type":"text_delta"}
{"role":"assistant","content":"Reading the failing test first.","type":"text_done"}
{"role":"assistant","item_id":"call_1","name":"read","arguments_delta":"{\"path\":\"x\"}","type":"tool_call_delta"}
{"role":"assistant","item_id":"call_1","call_id":"call_1","name":"read","arguments":"{\"path\":\"x\"}","type":"tool_call_done"}
{"role":"assistant","token_usage":{"input_tokens":1423,"output_tokens":89},"type":"token_usage_done"}
{"type":"before_tool_call","call_id":"call_1","tool":"read","args":{"path":"x"},"at":81234.513}
{"type":"after_tool_call","call_id":"call_1","tool":"read","args":{"path":"x"},"result":{"content":"1: …","error":null,"error_type":null},"at":81234.531,"duration":0.018}
{"stop_reason":"completed","usage":{"input_tokens":1423,"output_tokens":89},"type":"turn_end"}
```

`session_start` is the first record, carrying the session id. The remaining StreamEvents follow the turn in order — the ones a tool-using turn produces are shown above; reasoning (`reasoning_delta`, `reasoning_done`), web search (`web_search_status`, `web_search_done`), finish reasons, guardrails and interrupts serialize the same way whenever the provider emits them. `turn_end` is always the last record of a prompt: `stop_reason` is riffer's outcome vocabulary (`completed`, `length`, `max_steps`, `cancelled`, …), `usage` is the run's token totals, and `cost` (USD, present when the model is priced) rides on `usage`. A consumer that only reads the last line still knows how the turn ended and what it cost.

Each [follow-up turn](#background-jobs) streams its records the same way, after the previous turn's `turn_end`: one `job_exit` record per job the model is told of, then the turn's events, then its own `turn_end`, whose `usage` covers that turn alone. `session_start` is written once, at the start of the run. The `waiting for background jobs` note stays on stderr. When the idle timeout passes, the last record is a `notify` at level `warning` carrying the message text mode prints on stderr.

Each tool call is traced by two records, written as they happen; see [tool call events](EMBEDDING.md#tool-call-events). `tool_call_done` announces the call before it runs. `before_tool_call` is written as the tool starts, with the `args` it runs with; a call that does not run — an extension blocked it, or its arguments are not a JSON object — has no such record. `after_tool_call` is written once for every call, when it finishes. On both, `call_id` matches the `tool_call_done` record and `at` is a monotonic timestamp in seconds, comparable only within the run; `duration` is the seconds the tool itself ran, `0.0` for a call that did not run. `result` is an object of three fields: `content`, the text the model receives; `error`, the error message, `null` on success; and `error_type`, `null` on success and otherwise the kind of failure (`execution_error`, `validation_error`, `unknown_tool`, `timeout_error`, `unhandled_error`, or `blocked` for a call an extension blocked). Text mode prints nothing for either record.

Warnings and notify lines that headless prints on stderr in text mode ride the stream as `notify` records in `--json`; `progress` and the `--verbose` tool trace stay on stderr. The `before_prompt`, `before_request` and `after_response` events are extension-hook traffic, not Runtime output, so they never appear on the stream.

A fatal error — a failed configuration, no prompt, or an exception mid-turn — is a last `{"type": "error", "message": "…"}` record and the exit code above. Everything else on stderr stays on stderr: the exit-3 stop reason is printed there as in text mode and also rides on `turn_end`.
