# Headless mode

Run the agent with no terminal: one prompt on stdin, the event stream as NDJSON on stdout, exit code from how the turn ended. A pipe in, a pipe out — CI jobs, cron jobs, and other tools drive riffer-rig exactly as a human does, minus the TTY.

## The NDJSON shape

Every event riffer-rig emits is printed as one JSON object per line — riffer's `StreamEvents` plus the rig-level events from `Riffer::Rig::Events`, verbatim from each event's `to_h` (a `TokenUsage` value serializes through its own `to_h`, as riffer's own `token_usage_done` event does). Every record carries a `"type"` field: the snake_case event name (`text_delta`, `tool_call_done`, `session_start`, `turn_end`, …).

```json
{"id":"0198…","reason":"new","type":"session_start"}
{"role":"assistant","content":"Re","type":"text_delta"}
{"role":"assistant","content":"Reading the failing test first.","type":"text_done"}
{"role":"assistant","name":"read","type":"tool_call_done"}
{"role":"assistant","token_usage":{"input_tokens":1423,"output_tokens":89},"type":"token_usage_done"}
{"stop_reason":"completed","usage":{"input_tokens":1423,"output_tokens":89},"type":"turn_end"}
```

`turn_end` is always the last record of a prompt: `stop_reason` is riffer's outcome vocabulary (`completed`, `length`, `max_steps`, `interrupted`, …), `usage` is the run's token totals, and `cost` (USD, present when the model is priced) rides on `usage`. A consumer that only reads the last line still knows how the turn ended and what it cost.

Rig events beyond `session_start` and `turn_end` — `session_end`, `command_output`, `skill_activated`, `notify` — appear in the same stream, so one consumer sees everything the terminal sees. `notify` mirrors every `host.notify`, including extension errors.

## The flag

The `--headless`/`-p` flag that runs this mode is coming in a later ticket; the shape above is the contract it prints to. Embedders who want headless behaviour today drive `Riffer::Rig::Runtime.prompt` themselves and serialize each event with `JSON.generate(event.to_h)` — the same code path the flag will use.
