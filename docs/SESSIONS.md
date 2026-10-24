# Sessions

Every session is saved as it runs, one file per session at `~/.riffer/sessions/<directory>/<session id>.jsonl`, one JSON object per line, so `cat` and `jq` work on it and a crash loses at most the last line.

## Resuming

| To…                                              | Run                     |
| ------------------------------------------------ | ----------------------- |
| continue the most recent session in this directory | `riffer -c`           |
| resume a session by id                           | `riffer -r <id>`        |
| pick from this directory's sessions              | `riffer -r`, or `/resume` in a session |
| pick from every directory's sessions             | `/resume --all`         |

A session resumes in the directory it was saved in, wherever you resume it from, so its tools, project settings, skills and `rig.rb` are that directory's. If that directory no longer exists, the session isn't resumed. When there is no session to continue, the terminal starts a fresh one; [headless](HEADLESS.md#flags) exits 2 instead.

A resumed session keeps its id and carries on in the same file. What comes back:

| Restored from the session                         | Taken from today                                       |
| ------------------------------------------------- | ------------------------------------------------------ |
| the conversation                                  | settings, credentials and extensions                   |
| a `/model` switch, if its provider still has credentials | the tools, and the system prompt                |
| a `/reasoning` switch                             |                                                        |
| the skills the model activated, if they still exist |                                                      |

Whether a flag or a restored switch wins is in [Configuration](CONFIGURATION.md#where-each-value-comes-from). If a crash cut off a turn mid-tool-call, the unfinished calls are marked as interrupted rather than run again.

## The picker

`/resume` lists sessions newest first, each with its first prompt and when it was last used.

| Input                    | Does                                                    |
| ------------------------ | ------------------------------------------------------- |
| text, then Enter         | filters to sessions whose title contains it; with one left, Enter resumes it |
| a row number, then Enter | resumes that session                                    |
| Ctrl-D, a row number, `y` | deletes that session                                   |
| Ctrl-C                   | closes the picker                                       |

Switching keeps the session you left saved, as does `/new`, which starts a fresh session in place.

## Tracing the last turn

`/trace` shows the last turn step by step from the saved session — including in a session you just resumed:

```text
02:00:01.000  prompt    Fix the failing test
02:00:02.250  preamble  I'll read both files.
02:00:02.250  dispatch  read {"path":"a.rb"}
02:00:02.250  dispatch  read {"path":"b.rb"}
              silent    6.8s
02:00:09.050  finish    read
02:00:09.051  finish    read (execution_error)
02:00:10.500  answer    Fixed.
```

| Step       | Shows                                                                          |
| ---------- | ------------------------------------------------------------------------------ |
| `prompt`   | the first line of your message                                                 |
| `preamble` | the first line of text the model sent along with tool calls                    |
| `dispatch` | a tool call: the tool and its arguments                                        |
| `finish`   | a tool result, with the error type when it failed                              |
| `answer`   | the first line of a reply that called no tool                                  |
| `notice`   | a [background job](TOOLS.md#background-jobs) exit that continued the turn      |
| `silent`   | a gap of 5 seconds or more, and its length                                     |

Times are UTC. The results of one batch of tool calls are saved together, so their `finish` lines share a time; [`--json`](HEADLESS.md#the-ndjson-stream---json) has each call's own timing.

## Opting out

| Setting                                  | Saves this session | Can resume saved sessions |
| ---------------------------------------- | :----------------: | :-----------------------: |
| `--no-save`                              | no                 | no                        |
| `"sessions": {"save": false}` in settings | no                | yes, without adding to them |

`/trace` needs a saved session, so it is not available when saving is off.

To keep sessions somewhere else — your app's database, say — see [Session stores](STORES.md).
