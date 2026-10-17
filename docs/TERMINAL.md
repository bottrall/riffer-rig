# Terminal

`riffer` with no `-p` opens the interactive terminal. It keeps two rows at the bottom of the screen — the input line, and a status line under it — and prints everything else above them: the banner, each message as it starts, each turn's answer and stat line, and command output. When there is no terminal to draw on, it reads plain lines instead ([Without a terminal](#without-a-terminal)).

Colour is on when the output is a terminal; set `NO_COLOR` to turn it off.

## The input line

The input line, marked `›`, is always there, including while a turn runs. Enter sends the line; a line that is empty or only spaces is not sent.

| Key                                                      | Does                                                                                                                                                 |
| -------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------- |
| Enter                                                    | sends the line ([Queueing](#queueing-messages))                                                                                                      |
| Left, Right                                              | moves one character                                                                                                                                  |
| Ctrl-Left, Ctrl-Right, Alt-Left, Alt-Right, Alt-B, Alt-F | moves one word, a run of letters and digits                                                                                                          |
| Home, End                                                | moves to the start or the end of the line                                                                                                            |
| Backspace, Delete                                        | deletes the character before or under the cursor                                                                                                     |
| Ctrl-W                                                   | cuts back to the start of the word before the cursor, a run of anything but spaces                                                                   |
| Ctrl-U                                                   | cuts everything before the cursor                                                                                                                    |
| Ctrl-K                                                   | cuts everything from the cursor to the end                                                                                                           |
| Ctrl-Y                                                   | inserts the last cut at the cursor, even one from an earlier line                                                                                    |
| Up, Down                                                 | steps through the lines sent since `riffer` started; Down past the newest brings back the line you were typing                                       |
| Ctrl-T                                                   | opens or closes the [peek](#peek) while a turn runs                                                                                                  |
| Ctrl-C                                                   | cancels the running turn or an open question; with neither, asks for a second Ctrl-C to exit ([Interrupting and exiting](#interrupting-and-exiting)) |
| Ctrl-D                                                   | on an empty line, ends the session once the queued messages have run                                                                                 |

While the [command palette](#the-command-palette) is open, Up and Down move through it instead of the history, and Enter, Tab, Escape and Right at the end of the line act on it. Every other key does nothing.

### The command palette

A `/` at the start of the line opens a palette above the input line listing the session's [commands](#commands) — `/new`, `/resume`, `/exit`, `/quit`, `/model`, `/auth`, `/reload`, `/cost`, `/trace`, each skill's and each [extension](EXTENSIONS.md)'s — with their descriptions. Typing after the `/` narrows it to the commands whose names hold those letters in order, ignoring case, with a name that is exactly what you typed first, then the names that start with it. It shows eight commands at a time, fewer on a short terminal, and scrolls to keep the selected one in view. The selected command is marked `▸`; when its name starts with what you typed and the cursor is at the end of the line, the rest of the name shows dimmed after the cursor.

| Key                             | Does                                                                                                              |
| ------------------------------- | ----------------------------------------------------------------------------------------------------------------- |
| Up, Down                        | moves the selection, wrapping round at either end                                                                 |
| Tab, Right at the end of a line | replaces the line with the selected command and a space, ready for its arguments                                  |
| Escape                          | closes the palette and keeps the line; it stays closed while the line starts with `/`                             |
| Enter                           | sends the selected command, so `/mo` runs `/model`; a `/` on its own is sent as typed and asks for a command name |

The palette closes once the line has a space in it, so Enter sends a command with arguments as you typed it. It stays closed on a line recalled with Up, so Up and Down keep stepping through the history. It lists the commands as they are at each key you press, so it follows a `/reload`, `/new` or `/resume`.

### Pasting

A paste arrives as text, not as keystrokes: a line break in it does not send the line, and shows as `␊` (a tab as `␉`). A paste of 1,000 characters or more shows as `[pasted 1.2k chars]`, and Backspace, Delete and the arrows treat it as a single character; the whole text is sent. Once sent, it is printed above with its line breaks and indentation kept, a tab as four spaces. Bytes that are not valid UTF-8 are dropped.

## Queueing messages

Enter takes the line even while a turn runs. A message sent then waits its turn, and the input line shows how many are waiting, as `· 2 queued` after what you are typing. Queued messages run one at a time, in the order you sent them, each as a turn of its own once the one before has ended; each is printed above as `› message` when it starts. Slash commands queue the same way, and `/exit` or `/quit` ends the session when it reaches the front, dropping anything queued behind it.

## The status line

While a turn runs, the row under the input line shows its progress, redrawn about eight times a second. From the left:

- an animated equalizer;
- the time since the turn started, as `mm:ss`;
- `step N`, the model calls so far;
- `N tools`, the tool calls the model has made;
- the tokens, as `↑in ↓out tok` (`k` and `M` for thousands and millions);
- the cost so far, as `$0.012`, when the model is [priced](CONFIGURATION.md#models);
- a label: `riffing…`, a rotating phrase while the model is reasoning, or `✦ skill: <name>` for a moment after a skill activates.

The output tokens and the cost count text still streaming, at an estimated four characters per token, until the provider reports the request's usage; the input tokens appear once it has. On a narrow terminal the line drops whole figures from the right rather than show one cut short. The line clears when the turn ends.

While a question waits for your answer — a credential prompt from `/auth`, say, or [the picker](SESSIONS.md#the-picker) — the status line shows `answer above · Ctrl-C cancels` in place of the turn's figures, which come back once the question closes.

### Background jobs

While background `bash` jobs are running ([Tools](TOOLS.md#background-jobs)), the status line ends with their count — `1 job running`, `2 jobs running` — between turns as well as during them. When the line is too narrow for both, the turn's figures are cut to keep the count whole.

When a job exits while the terminal waits for input, it starts a turn by itself: `1 background job exited` is printed above the input line (`2 background jobs exited` for exits that arrive together, which share one turn), and the model receives the exit and acts on it. The turn runs like one you sent — the status line, Ctrl-C and the turn report work the same — and anything you were typing stays on the input line. Messages you have queued run first, and the first prompt among them carries the exit to the model instead. A job that exits during a turn is reported in that turn instead ([Tools](TOOLS.md#background-jobs)), and one that exits while a question or [the picker](SESSIONS.md#the-picker) is open waits until you answer it. After `/new` or `/resume`, exits from the session you left start nothing.

## Peek

Ctrl-T while a turn runs opens a dim panel above the input line with what the model is writing as it streams: the reply so far, or, while it waits on tools, the first line of the text it sent with them, and `⚙ <tool>` while a tool runs. It shows the most recent eight rows, and fewer on a short terminal. Ctrl-T again closes it, and it closes by itself when the turn ends. Between turns, Ctrl-T does nothing.

## The turn report

When a turn ends, its answer is printed above the input line, rendered from Markdown: headings, emphasis, inline code and code blocks, lists, quotes, tables, rules and links. Text the model sent along with tool calls is not printed. Under the answer comes a stat line:

```text
3 steps · 00:12 · ↑5200 · ↓340 · cache_read:4096 · ~$0.0215 · session 18400 tok · ~$0.0731
```

That is the turn's model calls, its time, its input and output tokens, each cache count above zero, and its cost, then the session's total tokens and cost; the costs appear once the model is [priced](CONFIGURATION.md#models). A cancelled turn prints the answer it had reached and `interrupted` in place of the stat line. Command output, such as `/cost`'s, is printed as it arrives.

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
| `/new`                            | starts a fresh session in place; the one you left stays on disk ([Sessions](SESSIONS.md#the-picker))                       |
| `/resume [--all]`                 | opens [the picker](SESSIONS.md#the-picker) over this directory's sessions, or every directory's                            |
| `/model [provider/name] [--save]` | shows or switches the model ([Configuration](CONFIGURATION.md#model))                                                      |
| `/auth`                           | lists, re-runs or removes provider credentials ([Providers](PROVIDERS.md#auth))                                            |
| `/reload`                         | reloads the extensions and settings ([Reloading](RELOADING.md))                                                            |
| `/cost`                           | shows the session's token usage and cost, then each turn's ([Embedding](EMBEDDING.md#token-tally-and-cost) has the format) |
| `/trace`                          | replays the last turn from the saved session, step by step with times ([Sessions](SESSIONS.md#tracing-the-last-turn))      |
| `/skill:<name> [text]`            | runs a skill ([Skills](SKILLS.md))                                                                                         |

Any other `/name args` runs the command of that name, such as one an [extension](EXTENSIONS.md) registers; an unknown name, or a `/` with none, is reported and nothing is sent to the model.

## Without a terminal

When the input or the output is not a terminal — piped into or out of `riffer` without `-p` — or the terminal reports no width, `riffer` reads one line at a time instead. There is no status line, queue, peek or replay, and a background job's exit waits for the next line rather than starting a turn: each line runs as a turn once the one before has ended, nothing is printed while a turn runs, and its answer and stat line print when it ends. Ctrl-C cancels a running turn, and with none running prints `Press Ctrl-C again to exit.`; a second Ctrl-C, or the end of the input, ends the session. To run one prompt from a script, use [headless](HEADLESS.md) mode, `riffer -p`.
