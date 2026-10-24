# Events

A turn streams events: riffer's [stream events](https://riffer.ai/guides/stream-events/) unchanged — text and reasoning deltas, tool calls, token usage — plus riffer-rig's own events below. `Runtime#prompt` yields them, [`--json`](HEADLESS.md#the-ndjson-stream---json) prints them, and a [host](HOSTS.md) renders them. Match on the events you know and ignore the rest; new events can be added in a minor release.

Every rig event has `type`, its snake_case name, and `to_h`, its fields with the type included, so each one prints as a JSON record as-is.

## Rig events

| Event              | Carries                                                                  | When                                                                                  |
| ------------------ | ------------------------------------------------------------------------ | ------------------------------------------------------------------------------------- |
| `session_start`    | `id`, `reason` (`:new`, `:restore`, `:reload`)                           | opens the first prompt of a new or [restored](EMBEDDING.md#snapshots) session, and the first after a [rebuild](EMBEDDING.md#rebuilding-after-a-code-reload) |
| `session_end`      | `reason` (`:reload`, `:close`)                                           | opens the first prompt after a rebuild, just before its `session_start`; `:close` reaches only [hooks](EXTENSIONS.md#the-rigon-seam), as nothing streams after `close` |
| `command_output`   | `command`, `text`                                                        | a command called `ctx.say`                                                            |
| `skill_activated`  | `name`                                                                   | a skill was run with `/skill:<name>`                                                  |
| `notify`           | `message`, `level`                                                       | every notice the host was given, such as an extension failing to load                 |
| `before_tool_call` | `call_id`, `tool`, `args` (symbol keys), `at`                            | a tool is about to run ([below](#tool-call-events))                                   |
| `after_tool_call`  | `call_id`, `tool`, `args`, `result`, `at`, `duration`                    | a tool call has finished ([below](#tool-call-events))                                 |
| `job_exit`         | `job_id`, `command`, `exit_status`, `signal`, `duration`, `output_path`  | the model is told a [background job](EMBEDDING.md#background-jobs) exited, one per job |
| `turn_end`         | `stop_reason`, `usage`, `cost`                                           | always the last event of a prompt                                                     |

`turn_end`'s `stop_reason` is riffer's outcome (`:completed`, `:length`, `:max_steps`, `:guardrail_blocked`, …) or `:cancelled` after a [cancel](EMBEDDING.md#cancelling-a-turn). `usage` is the turn's riffer `TokenUsage`, and `cost` its price in USD, or `nil` when the model is not [priced](CONFIGURATION.md#catalog_files). A consumer never needs `ask` to learn how a streamed turn ended.

## Tool call events

When the model asks for tools, riffer first announces every call of the response with `ToolCallDone`. The tools then run one at a time, each between a `before_tool_call` and an `after_tool_call`:

```text
model response
  ├─ ToolCallDone        call 1
  ├─ ToolCallDone        call 2
  ├─ before_tool_call    call 1 ─┐
  │                              │ tool 1 runs   (duration)
  ├─ after_tool_call     call 1 ─┘
  ├─ before_tool_call    call 2 ─┐
  │                              │ tool 2 runs
  └─ after_tool_call     call 2 ─┘
next model response
```

Every call gets exactly one `after_tool_call`, whatever happened to it:

| The call…                                 | `before_tool_call`                               | `after_tool_call`'s `result`                     |
| ----------------------------------------- | ------------------------------------------------ | ------------------------------------------------ |
| ran                                       | yes, with the arguments it ran with              | the tool's response; `error_type` set if it failed |
| named a tool that doesn't exist           | yes                                              | an `:unknown_tool` error                          |
| was blocked by a [hook](EXTENSIONS.md#the-rigon-seam) | no                                   | a `:blocked` error, with the arguments the model sent |
| had arguments that aren't a JSON object   | no                                               | a `:validation_error`, with empty `args`          |

`result` is a `Riffer::Tools::Response`: `result.error?` says whether the call failed. `call_id` matches the call's `ToolCallDone`. `at` is a monotonic timestamp in seconds, comparable only within one process, and `duration` is how long the tool itself ran, leaving out time spent in hooks; a call that never ran has `0.0`. The timestamps come from the Runtime's `clock:`, which a test can replace.

These are the same event objects the `before_tool_call` and `after_tool_call` hooks receive.

## Custom events

A command can send its own events to whoever ran it with `ctx.emit(event)`. Any object with `type` and `to_h` qualifies (the RBS interface `Riffer::Rig::Events::_Event`).
