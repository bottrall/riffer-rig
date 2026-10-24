# Terminal

`riffer` with no `-p` opens the interactive terminal. The input line stays at the bottom of the screen with the status line under it, and everything else — the banner, your messages, each turn's answer, command output — prints above. Set `NO_COLOR` to turn colour off. When there is no terminal to draw on, `riffer` reads plain lines instead ([below](#without-a-terminal)).

## The input line

The input line, marked `›`, is always there, including while a turn runs. Long input wraps, showing at most eight rows at a time.

| Key                                                      | Does                                                                                             |
| -------------------------------------------------------- | ------------------------------------------------------------------------------------------------ |
| Enter                                                    | sends the input, or [queues](#queueing-messages) it while a turn runs                            |
| Ctrl-J, Alt-Enter (Option-Enter)                         | starts a new row                                                                                 |
| Shift-Enter                                              | starts a new row, on terminals that support the Kitty keyboard protocol; elsewhere it sends     |
| Left, Right                                              | moves one character                                                                              |
| Ctrl-Left, Ctrl-Right, Alt-Left, Alt-Right, Alt-B, Alt-F | moves one word                                                                                   |
| Home, End                                                | moves to the start or end of the input                                                           |
| Backspace, Delete                                        | deletes the character before or under the cursor                                                 |
| Ctrl-W                                                   | cuts the word before the cursor                                                                  |
| Ctrl-U                                                   | cuts everything before the cursor                                                                |
| Ctrl-K                                                   | cuts everything after the cursor                                                                 |
| Ctrl-Y                                                   | pastes the last cut                                                                              |
| Up, Down                                                 | steps through the inputs sent since `riffer` started                                             |
| Ctrl-T                                                   | opens or closes the [peek](#peek) while a turn runs                                              |
| Ctrl-C, Ctrl-D                                           | see [Interrupting and exiting](#interrupting-and-exiting)                                        |

### The command palette

A `/` at the start of the line opens a palette listing the session's [commands](#commands) with their descriptions. Typing narrows it to commands whose names contain those letters in order.

| Key                             | Does                                                         |
| ------------------------------- | ------------------------------------------------------------ |
| Up, Down                        | moves the selection                                          |
| Tab, Right at the end of a line | fills in the selected command, ready for its arguments       |
| Enter                           | runs the selected command, so `/mo` runs `/model`            |
| Escape                          | closes the palette and keeps what you typed                  |

The palette closes once you type a space, so Enter then sends the command and its arguments as typed.

### Pasting

A paste arrives as text: its line breaks don't send the input. A paste of 1,000 characters or more shows as `[pasted 1.2k chars]` and edits as a single character, but the whole text is sent.

## Queueing messages

Enter works while a turn runs. The message waits, the input line shows `· 2 queued` at its right edge, and queued messages run one at a time, in order, once the turn ends. Slash commands queue the same way; a queued `/exit` ends the session when it reaches the front, dropping anything behind it.

## The status line

```text
⠹ step 3  high    00:12 ↑5.2k  ↓340 tok   ~$0.0215 2 jobs
```

| Slot       | While a turn runs                     | Between turns                     | On a narrow terminal |
| ---------- | ------------------------------------- | --------------------------------- | -------------------- |
| glyph      | a spinner                             | `·`                               | always shown         |
| state      | `step N`, the model calls so far      | `idle`                            | dropped 5th          |
| reasoning  | the level, or `default`               | the same                          | dropped 1st          |
| clock      | time since the turn started           | the time of day                   | dropped 2nd          |
| tokens     | this request's input and output so far | the session's total              | dropped 4th          |
| cost       | the turn's cost so far                | the session's total               | dropped 3rd          |
| jobs       | running [background jobs](#background-jobs) | the same                    | always shown         |

The slots stay at the same positions whether a turn is running or not, so nothing on screen shifts when one starts or ends. The cost reads `~$0.0000` until the model is [priced](CONFIGURATION.md#catalog_files). While a question waits for an answer, the line shows `answer above · Ctrl-C cancels` instead.

## Background jobs

When a [background job](TOOLS.md#background-jobs) exits between turns:

| While the terminal…                  | It                                                                                                   |
| ------------------------------------ | ---------------------------------------------------------------------------------------------------- |
| waits for your input                 | prints `1 background job exited` and starts a turn that tells the model, like one you sent; anything you were typing stays on the input line |
| has messages queued                  | runs them first, and they carry the news                                                             |
| has a question or the picker open    | waits until you answer it                                                                            |

## Peek

Ctrl-T while a turn runs opens a dim panel above the input line showing what the model is writing as it streams, or `⚙ <tool>` while a tool runs. It shows the last eight rows, and closes when the turn ends.

## The turn report

When a turn ends its answer is printed, rendered from Markdown, followed by a stat line:

```text
3 steps · 00:12 · ↑5.2k · ↓340 · cache_read:4k · ~$0.0215 · session 18.4k tok · ~$0.0731
```

The turn's model calls, time, input and output tokens, any cache counts and cost, then the session's total tokens and cost. Costs appear once the model is [priced](CONFIGURATION.md#catalog_files). Text the model sent along with tool calls is not printed; use [`/trace`](SESSIONS.md#tracing-the-last-turn) to see it.

## Interrupting and exiting

| When                                   | Ctrl-C                                                                 | Ctrl-D on an empty line                |
| -------------------------------------- | ---------------------------------------------------------------------- | -------------------------------------- |
| no turn running                        | shows `Press Ctrl-C again to exit.`; a second Ctrl-C exits, any other key cancels | ends the session            |
| a turn running                         | cancels it: a streaming reply stops at once, a running tool when it returns; the partial answer prints with `interrupted` | ends the session once the turn and the queue finish |
| a question is open                     | leaves it unanswered, and cancels the turn that asked, if any          | leaves it unanswered                   |
| a question before the session starts   | exits                                                                  | leaves it unanswered                   |

Cancelling a turn leaves messages you queued behind it to run. Background jobs keep running until the model stops them or you end the session (`/exit`, `/new` or `/resume`).

An unanswered question stores nothing: `/auth` and `/model` report the credential still missing, and a [trust question](EXTENSIONS.md#the-rigrb-files) asks again next time. `/exit` and `/quit` also end the session.

## Resuming

A resumed session — `riffer -c`, `riffer -r`, or a pick in [the picker](SESSIONS.md#the-picker) — replays its earlier turns under the banner: each prompt, its answer and its stat line.

## Commands

| Command                           | Does                                                                                       |
| --------------------------------- | ------------------------------------------------------------------------------------------ |
| `/help`                           | lists the session's commands                                                               |
| `/new`                            | starts a fresh session; the one you left stays saved                                       |
| `/resume [--all]`                 | opens [the picker](SESSIONS.md#the-picker) over this directory's sessions, or every directory's |
| `/model [provider/name] [--save]` | shows, switches or saves the model ([Configuration](CONFIGURATION.md#model))               |
| `/reasoning [level] [--save]`     | shows, switches or saves the reasoning level ([Configuration](CONFIGURATION.md#reasoning)) |
| `/auth`                           | lists, re-runs or removes provider credentials ([Providers](PROVIDERS.md#auth))            |
| `/reload`                         | reloads extensions and settings ([Reloading](RELOADING.md))                                |
| `/cost`                           | shows the session's token usage and cost, then each turn's                                 |
| `/trace`                          | shows the last turn step by step ([Sessions](SESSIONS.md#tracing-the-last-turn))           |
| `/skill:<name> [text]`            | runs a skill ([Skills](SKILLS.md))                                                         |
| `/exit`, `/quit`                  | ends the session                                                                           |

Any other `/name args` runs a command an [extension](EXTENSIONS.md#the-rigcommand-seam) registered. An unknown name is reported and nothing is sent to the model.

## Without a terminal

When input or output is piped — `riffer` without `-p` in a pipeline — it reads one line at a time and runs each as a turn, printing the answer and stat line when it ends. There is no status line, queue, peek or replay, and a background job's exit waits for the next line. Ctrl-C works as above. To run one prompt from a script, use [headless mode](HEADLESS.md).
