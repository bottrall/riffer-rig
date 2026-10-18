# Terminal

`riffer` with no `-p` opens the interactive terminal. It keeps the input at the bottom of the screen — as many rows as it wraps to, and a status line under them — and prints everything else above, a blank row clear of the input: the banner, each message as it starts, each turn's answer and stat line, and command output. While the session is still starting, the rows are replaced by a single dim line that animates while it waits — a braille spinner rolling through riff-themed quips like `⠹ warming the amp…`; the input line and the banner take their place together, once the banner's content is known. When there is no terminal to draw on, it reads plain lines instead ([Without a terminal](#without-a-terminal)).

Colour is on when the output is a terminal; set `NO_COLOR` to turn it off.

## The input line

The input line, marked `›`, is always there, including while a turn runs. It can be more than one row: text wraps at the edge of the screen and each row that follows lines up under the prompt, spaces show as you typed them, and Ctrl-J or Alt-Enter starts a new row at the cursor. An input that wraps past the screen shows a window of at most eight rows, scrolled to keep the cursor's row in view. Enter sends the input; an input that is empty or only spaces is not sent.

| Key                                                      | Does                                                                                                                                                 |
| -------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------- |
| Enter                                                    | sends the input ([Queueing](#queueing-messages))                                                                                                     |
| Ctrl-J, Alt-Enter (Option-Enter)                         | starts a new row at the cursor instead of sending                                                                                                    |
| Shift-Enter                                              | starts a new row at the cursor instead of sending, on terminals that report it                                                                       |
| Left, Right                                              | moves one character                                                                                                                                  |
| Ctrl-Left, Ctrl-Right, Alt-Left, Alt-Right, Alt-B, Alt-F | moves one word, a run of letters and digits                                                                                                          |
| Home, End                                                | moves to the start or the end of the input                                                                                                           |
| Backspace, Delete                                        | deletes the character before or under the cursor                                                                                                     |
| Ctrl-W                                                   | cuts back to the start of the word before the cursor, a run of anything but spaces                                                                   |
| Ctrl-U                                                   | cuts everything before the cursor                                                                                                                    |
| Ctrl-K                                                   | cuts everything from the cursor to the end                                                                                                           |
| Ctrl-Y                                                   | inserts the last cut at the cursor, even one from an earlier line                                                                                    |
| Up, Down                                                 | steps through the inputs sent since `riffer` started; Down past the newest brings back the input you were typing                                     |
| Ctrl-T                                                   | opens or closes the [peek](#peek) while a turn runs                                                                                                  |
| Ctrl-C                                                   | cancels the running turn or an open question; with neither, asks for a second Ctrl-C to exit ([Interrupting and exiting](#interrupting-and-exiting)) |
| Ctrl-D                                                   | on an empty line, ends the session once the queued messages have run                                                                                 |

Shift-Enter is reported only by terminals that implement the Kitty keyboard protocol: `riffer` enables its disambiguate escape codes when the session starts and pops them when it ends, and a terminal without the protocol ignores both and sends Shift-Enter as plain Enter, which sends the input.

While the [command palette](#the-command-palette) is open, Up and Down move through it instead of the history, and Enter, Tab, Escape and Right at the end of the line act on it. Every other key does nothing.

### The command palette

A `/` at the start of the line opens a palette above the input line listing the session's [commands](#commands) — `/help`, `/new`, `/resume`, `/exit`, `/quit`, `/model`, `/auth`, `/reload`, `/cost`, `/trace`, each skill's and each [extension](EXTENSIONS.md)'s — with their descriptions. Typing after the `/` narrows it to the commands whose names hold those letters in order, ignoring case, with a name that is exactly what you typed first, then the names that start with it. It shows eight commands at a time, fewer on a short terminal, and scrolls to keep the selected one in view. The selected command is marked `▸`; when its name starts with what you typed and the cursor is at the end of the line, the rest of the name shows dimmed after the cursor.

| Key                             | Does                                                                                                              |
| ------------------------------- | ----------------------------------------------------------------------------------------------------------------- |
| Up, Down                        | moves the selection, wrapping round at either end                                                                 |
| Tab, Right at the end of a line | replaces the line with the selected command and a space, ready for its arguments                                  |
| Escape                          | closes the palette and keeps the line; it stays closed while the line starts with `/`                             |
| Enter                           | sends the selected command, so `/mo` runs `/model`; a `/` on its own is sent as typed and asks for a command name |

The palette closes once the line has a space in it, so Enter sends a command with arguments as you typed it. It stays closed on a line recalled with Up, so Up and Down keep stepping through the history. It lists the commands as they are at each key you press, so it follows a `/reload`, `/new` or `/resume`.

### Pasting

A paste arrives as text, not as keystrokes: a line break in it does not send the input, and shows as a line break, as if typed (a tab as `␉`). A paste of 1,000 characters or more shows as `[pasted 1.2k chars]`, and Backspace, Delete and the arrows treat it as a single character; the whole text is sent. Once sent, it is printed above with its line breaks and indentation kept, a tab as four spaces. Bytes that are not valid UTF-8 are dropped.

## Queueing messages

Enter takes the line even while a turn runs. A message sent then waits its turn, and the input line shows how many are waiting, as `· 2 queued` at the right edge of the line, so a message queued while you type moves nothing you have already written. Queued messages run one at a time, in the order you sent them, each as a turn of its own once the one before has ended; each is printed above as `› message` when it starts. Slash commands queue the same way, and `/exit` or `/quit` ends the session when it reaches the front, dropping anything queued behind it.

## The status line

The row under the input line is a row of fixed slots — the same columns at the same character positions while a turn runs and between turns, so starting or ending a turn moves nothing on screen. From the left:

- a glyph: a dim `·` between turns, a spinner while a turn runs;
- the state, as `idle` between turns and `turn N` — N the model's requests so far — while a turn runs;
- the clock: the time of day, as `14:32`, between turns, and the time since the turn started, as `mm:ss`, while one runs;
- the tokens, as `↑in ↓out tok` (`k` and `M` for thousands and millions): the session's total between turns, the request's running count while a turn runs;
- the cost, as `~$1.4000`: the session's total between turns, the turn's running cost while it runs; `~$0.0000` until the model is [priced](CONFIGURATION.md#catalog_files);
- the background jobs, as `2 jobs`, always shown, even as `0 jobs`.

Every figure sits inside its slot's fixed width, so `18.2k` and `132k` occupy the same box. While a turn runs the row is redrawn about eight times a second, the spinner and the cost in green and the jobs count in amber; the output tokens and the cost count text still streaming, at an estimated four characters per token, until the provider reports the request's usage, which the input tokens show in place of an opening `↑0`. Between turns the whole row is dim, and the clock keeps current while the terminal waits.

On a narrow terminal the slots leave whole from the left — the clock first, then the cost, then the tokens, then the state — so the jobs count at the right edge survives longest.

While a question waits for your answer — a credential prompt from `/auth`, say, or [the picker](SESSIONS.md#the-picker) — the status line shows `answer above · Ctrl-C cancels` in place of the row, which comes back untouched once the question closes.

### Background jobs

The last slot of the status line always counts background `bash` jobs ([Tools](TOOLS.md#background-jobs)) — `2 jobs` between turns as well as during them, `0 jobs` when none runs. On a narrow terminal it is the last slot to leave.

When a job exits while the terminal waits for input, it starts a turn by itself: `1 background job exited` is printed above the input line (`2 background jobs exited` for exits that arrive together, which share one turn), and the model receives the exit and acts on it. The turn runs like one you sent — the status line, Ctrl-C and the turn report work the same — and anything you were typing stays on the input line. Messages you have queued run first, and the first prompt among them carries the exit to the model instead. A job that exits during a turn is reported in that turn instead ([Tools](TOOLS.md#background-jobs)), and one that exits while a question or [the picker](SESSIONS.md#the-picker) is open waits until you answer it. After `/new` or `/resume`, exits from the session you left start nothing.

## Peek

Ctrl-T while a turn runs opens a dim panel above the input line with what the model is writing as it streams: the reply so far, or, while it waits on tools, the first line of the text it sent with them, and `⚙ <tool>` while a tool runs. It shows the most recent eight rows, and fewer on a short terminal. Ctrl-T again closes it, and it closes by itself when the turn ends. Between turns, Ctrl-T does nothing.

## The turn report

When a turn ends, its answer is printed above the input line, rendered from Markdown: headings, emphasis, inline code and code blocks, lists, quotes, tables, rules and links. Text the model sent along with tool calls is not printed. A turn the model replied to more than once — one continued for a [background job](TOOLS.md#background-jobs) that exited as the model finished its reply — prints each reply in order, a blank line apart. Under the answer comes a stat line:

```text
3 steps · 00:12 · ↑5200 · ↓340 · cache_read:4096 · ~$0.0215 · session 18400 tok · ~$0.0731
```

That is the turn's model calls, its time, its input and output tokens, each cache count above zero, and its cost, then the session's total tokens and cost; the costs appear once the model is [priced](CONFIGURATION.md#catalog_files). A cancelled turn prints the answer it had reached and `interrupted` in place of the stat line. Command output, such as `/cost`'s, is printed as it arrives.

## Interrupting and exiting

- Ctrl-C during a turn cancels it: the status line shows `stopping…`, a reply in flight stops at once and a running tool call when it returns ([Cancelling a turn](EMBEDDING.md#cancelling-a-turn)). Messages queued behind it still run. Background jobs keep running; ask the model to stop one, or end the session — quitting, `/new` or `/resume` — to stop them all.
- Ctrl-C at a question — a missing credential that `/auth`, `/model` or a [reload](RELOADING.md) asks for, a confirmation such as trusting a project `rig.rb`, a command's own question — leaves it unanswered and, if a turn asked it, then cancels that turn as above. What asked carries on without an answer: nothing is stored, `/auth` and `/model` report the credential still missing and `/model` keeps the current model, and a trust question skips the project `rig.rb` for now and asks again at the next load. The line typed next goes to the input line, never to the question. At a question asked before the session starts, Ctrl-C exits, and at one asked while `/new` or `/resume` starts the next session, the current session carries on. Ctrl-D also leaves a question unanswered, without cancelling a turn.
- Ctrl-C with no turn running shows `Press Ctrl-C again to exit.` on the status line, and a second Ctrl-C exits. Any other key in between cancels the exit.
- `/exit` and `/quit` end the session, as does Ctrl-D on an empty line, which lets the messages already queued run first.

## Resuming

When a session is resumed — `riffer -c`, `riffer -r`, or a pick in [the picker](SESSIONS.md#the-picker) — its earlier turns are replayed above the input line, under the banner: each prompt as `› prompt`, then the turn's answer and its stat line, without the session total. A turn a [background job's exit](#background-jobs) started replays the same way, under its `1 background job exited` line instead of a prompt; one saved by an earlier version replays as part of the turn before it. A cancelled turn replays with a stat line too. Turns saved by a version that recorded no times, or damaged on disk, are left out with one line saying so.

## Commands

A line starting with `/` runs a command. Besides `/exit` and `/quit`:

| Command                           | Does                                                                                                                       |
| --------------------------------- | -------------------------------------------------------------------------------------------------------------------------- |
| `/help`                           | lists the session's commands by name, with their descriptions                                                              |
| `/new`                            | starts a fresh session in place; the one you left stays on disk ([Sessions](SESSIONS.md#the-picker))                       |
| `/resume [--all]`                 | opens [the picker](SESSIONS.md#the-picker) over this directory's sessions, or every directory's                            |
| `/model [provider/name] [--save]` | shows or switches the model ([Configuration](CONFIGURATION.md#model))                                                      |
| `/reasoning [level] [--save]`     | shows or switches the reasoning level ([Configuration](CONFIGURATION.md#reasoning))                                        |
| `/auth`                           | lists, re-runs or removes provider credentials ([Providers](PROVIDERS.md#auth))                                            |
| `/reload`                         | reloads the extensions and settings ([Reloading](RELOADING.md))                                                            |
| `/cost`                           | shows the session's token usage and cost, then each turn's ([Embedding](EMBEDDING.md#token-tally-and-cost) has the format) |
| `/trace`                          | replays the last turn from the saved session, step by step with times ([Sessions](SESSIONS.md#tracing-the-last-turn))      |
| `/skill:<name> [text]`            | runs a skill ([Skills](SKILLS.md))                                                                                         |

Any other `/name args` runs the command of that name, such as one an [extension](EXTENSIONS.md) registers; an unknown name, or a `/` with none, is reported and nothing is sent to the model.

## Without a terminal

When the input or the output is not a terminal — piped into or out of `riffer` without `-p` — or the terminal reports no width, `riffer` reads one line at a time instead. There is no status line, queue, peek or replay, and a background job's exit waits for the next line rather than starting a turn: each line runs as a turn once the one before has ended, nothing is printed while a turn runs, and its answer and stat line print when it ends. Ctrl-C cancels a running turn, and with none running prints `Press Ctrl-C again to exit.`; a second Ctrl-C, or the end of the input, ends the session. To run one prompt from a script, use [headless](HEADLESS.md) mode, `riffer -p`.
