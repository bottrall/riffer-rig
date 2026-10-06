# Headless mode

Run one prompt with no terminal: `riffer -p "prompt"` runs a single turn through everything the REPL loads and exits with a code that says how it ended. A pipe in, a pipe out — CI jobs, cron jobs, and other tools drive riffer-rig exactly as a human does, minus the TTY.

## The prompt

The prompt is the argument:

```bash
riffer -p "what does this repo do"
```

Piped stdin is appended to the argument as context, and with no argument stdin alone is the prompt. A TTY stdin is never read, so `riffer -p` in a terminal without an argument has nothing to run and exits 2.

```bash
git diff | riffer -p "review this diff"   # argument + stdin as context
echo "explain this diff" | riffer -p      # stdin is the prompt
```

The turn is one prompt: slash commands are not dispatched, and the session is saved like any other unless `--no-save` is given.

## Output

By default only the assistant's text is printed, streamed to stdout. Everything else goes to stderr: errors, configuration refusals, and the [notify](HOSTS.md) lines extensions and the Runtime emit. Reasoning is not printed. `--verbose` adds a one-line trace of each tool call to stderr.

## Flags

The REPL's flags all work here: `--model provider/name`, `--no-extensions`, `--no-skills`, `--no-agents-md`, `--tools a,b,c`, `--max-steps N`, `--no-save`, `-c`/`--continue` and `-r ID`/`--resume ID`, plus `--verbose`. The same [resolution order](PROVIDERS.md#resolution-order) applies to the model: `--model`, then `RIFFER_MODEL`, then settings.

`-c` and `-r` are the multi-turn headless story: `riffer -p -c "now run the tests"` continues the most recent session in this directory, appending to the same [session file](SESSIONS.md#resuming). Unlike the REPL, a missing session is not a fresh start — headless prints `No saved session …` on stderr and exits 2.

Headless never prompts. A missing model, a missing credential, or a missing optional SDK is not an interactive setup flow — the reason is printed on stderr with the provider's recipe (its environment variables and key URL), or the exact `gem install` line, and the process exits 2.

## Exit codes

| Exit | Meaning                                                                                                                                |
| ---- | -------------------------------------------------------------------------------------------------------------------------------------- |
| `0`  | the turn finished                                                                                                                       |
| `1`  | runtime error: provider failure, network failure, an exception in a tool or handler                                                     |
| `2`  | usage or configuration: unknown flag, no prompt, a bare model name, no credentials, a missing optional SDK                              |
| `3`  | the turn ended but did not complete: `max_steps`, `context_window`, `length`, `content_filter`, or `malformed_output`; the reason is on stderr |
| `130` | SIGINT: the turn is cancelled first — orphaned tool calls healed, the session closed — then exit                                        |

A script that only needs success or failure can therefore test the code alone; a caller that wants the reason reads stderr or waits for `--json` (below).

## The NDJSON stream (`--json`)

`--json` replaces the streamed text with one JSON object per line on stdout, one record for every event the Runtime yields: riffer's [StreamEvents](https://github.com/bottrall/riffer) plus the rig-level events (`session_start`, `notify`, `turn_end`). The envelope is flat — the event's `to_h` fields, plus a `"type"` of the snake_case event class (`text_delta`, `tool_call_done`, `session_start`, `turn_end`, …). Nested riffer values (a `TokenUsage`, an assistant message, a tool response) serialize through their own `to_h`.

```json
{"type":"session_start","id":"0198…","reason":"new"}
{"message":"heads up","level":"warning","type":"notify"}
{"role":"assistant","content":"Reading the failing test first. ","type":"text_delta"}
{"role":"assistant","content":"Reading the failing test first.","type":"text_done"}
{"role":"assistant","item_id":"call_1","name":"read","arguments_delta":"{\"path\":\"x\"}","type":"tool_call_delta"}
{"role":"assistant","item_id":"call_1","call_id":"call_1","name":"read","arguments":"{\"path\":\"x\"}","type":"tool_call_done"}
{"role":"assistant","token_usage":{"input_tokens":1423,"output_tokens":89},"type":"token_usage_done"}
{"stop_reason":"completed","usage":{"input_tokens":1423,"output_tokens":89},"type":"turn_end"}
```

`session_start` is the first record, carrying the session id. The remaining StreamEvents follow the turn in order — the ones a tool-using turn produces are shown above; reasoning (`reasoning_delta`, `reasoning_done`), web search (`web_search_status`, `web_search_done`), finish reasons, guardrails and interrupts serialize the same way whenever the provider emits them. `turn_end` is always the last record of a prompt: `stop_reason` is riffer's outcome vocabulary (`completed`, `length`, `max_steps`, `cancelled`, …), `usage` is the run's token totals, and `cost` (USD, present when the model is priced) rides on `usage`. A consumer that only reads the last line still knows how the turn ended and what it cost.

Warnings and notify lines that headless prints on stderr in text mode ride the stream as `notify` records in `--json`; `progress` and the `--verbose` tool trace stay on stderr. The `before_prompt`, `before_tool_call`, `before_request`, `after_response` and `after_tool_call` events are extension-hook traffic, not Runtime output, so they never appear on the stream.

A fatal error — a failed configuration, no prompt, or an exception mid-turn — is a last `{"type": "error", "message": "…"}` record and the exit code above. Everything else on stderr stays on stderr: the exit-3 stop reason is printed there as in text mode and also rides on `turn_end`.
