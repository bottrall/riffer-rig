# Tools

riffer-rig ships six tools: `read`, `write`, `edit`, `bash`, and `bash`'s two background-job companions, `bash_output` and `bash_kill`. Each comes from a bundled extension, so you can leave any of them out or replace it.

## The six tools

| Tool          | Does                                                                                         | Guidance in its description                                                                          |
| ------------- | -------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------- |
| `read`        | returns a file with line numbers; `offset` and `limit` (default 2,000 lines) read a slice     | "Read a file before editing it, and read rather than guess what a file contains."                   |
| `write`       | creates or overwrites a file, making parent directories                                       | "Use this for new files or full rewrites; prefer edit for changes to an existing file."             |
| `edit`        | replaces an exact string, which must be unique unless `replace_all` is set                     | "Prefer this over write for existing files; pass enough surrounding text to make old_string unique." |
| `bash`        | runs a shell command in the working directory and returns its combined output ([limits](#bash-limits)) | "Use this for exploring and running things: ls, rg or grep, find, tests, git, package managers."    |
| `bash_output` | returns what a [background job](#background-jobs) has written since the last read             | "Use this to check on a server, watcher or long-running job before it finishes."                    |
| `bash_kill`   | stops a background job and everything it started                                              | "Use this to stop a job that is no longer needed rather than leaving it running."                   |

The guidance sentence is the only coding advice the model gets. The base prompt names no tools, so the advice disappears with the tool when you leave it out.

A bad argument, a missing file or a failing command never crashes a turn: it comes back to the model as a tool error it can read and act on. Relative paths resolve against the session's working directory.

### `bash` limits

| Limit            | Value                                                                                  |
| ---------------- | -------------------------------------------------------------------------------------- |
| timeout          | `timeout_ms`, default 120,000 ms per call                                              |
| output           | truncated at 30,000 bytes                                                              |
| non-zero exit    | a tool error                                                                           |
| returns          | when the command exits, without waiting for anything it left running in the background |
| on cancel        | the command and everything it started are killed, and the call returns `[cancelled]`   |

## What runs without asking

riffer-rig has no permission prompts for tool calls. Every call the model makes — to these six tools, to [MCP](MCP.md) tools and to tools from extensions — runs as soon as the model makes it, with your user's access to the files and shell.

riffer-rig asks only before:

- loading a project's `.riffer/rig.rb` for the first time ([trust](EXTENSIONS.md#the-rigrb-files));
- installing a provider's [SDK gem](PROVIDERS.md#sdk-gems);
- storing a credential you type.

To narrow what the model can do:

| To…                                  | Use                                                                                              |
| ------------------------------------ | ------------------------------------------------------------------------------------------------ |
| allow only some tools for one run    | `--tools read,edit` ([Identifiers](#identifiers))                                                |
| never load some tools                | `"extensions": {"disabled": ["bash", "write"]}` in [settings](CONFIGURATION.md#extensions)       |
| refuse certain calls                 | a [`before_tool_call` hook](EXTENSIONS.md#the-rigon-seam) that returns `:block`                  |
| run commands somewhere safer         | [replace `bash`](#replacing-a-tool) with your own                                                |

## Background jobs

`bash` with `run_in_background` starts the command as a job and returns a job id and an output file path at once. The job keeps running after the call, and after the turn. Its stdin is `/dev/null`, and everything it writes goes to the output file, which keeps the most recent output once it passes 10 MB.

The model never has to poll for the exit: riffer-rig tells it, with a notice holding the command, the exit status (or the signal that killed it), the duration, the output path and the last 2,000 bytes of output:

```text
<background-job id="a1b2c3d4" status="completed" exit-code="0" duration="12.3s">
<command>make build</command>
<output-path>/tmp/jobs/a1b2c3d4</output-path>
<output-tail>
compiled
done
</output-tail>
</background-job>
```

When the model hears depends on what the session is doing when the job exits:

```text
  a turn running                    idle               the next turn
 |=============================|   |----------------|  |============
          ^                    ^          ^
          1                    2          3
```

| The job exits…             | The model hears…                                                     |
| -------------------------- | -------------------------------------------------------------------- |
| 1. during a turn           | in the next tool result it reads                                     |
| 2. as the reply finishes   | at once: the turn continues with the notice, up to 5 times per prompt |
| 3. between turns           | at the next prompt, or in a turn the host starts for it              |

What the host does at 3:

| Host                      | When a job exits between turns                                                                |
| ------------------------- | --------------------------------------------------------------------------------------------- |
| [terminal](TERMINAL.md#background-jobs) | starts a turn by itself, if it is waiting for your input                        |
| [headless](HEADLESS.md#background-jobs) | waits for running jobs before exiting, giving the model a turn for each exit    |
| [ACP](ACP.md)             | shows the exit to the client at once; the model hears at the next prompt                      |
| your app                  | decides for itself ([Embedding](EMBEDDING.md#background-jobs))                                |

Cancelling a turn does not stop its jobs. `bash_kill` stops one; ending the session stops them all and deletes their output files. Once the model has been told of an exit, `bash_output` and `bash_kill` no longer know the job, and the rest of its output is in the file named in the notice.

## Identifiers

A tool's name everywhere — `--tools`, the `tools:` allowlist when [embedding](EMBEDDING.md), a replacement — is its riffer identifier: `read`, `write`, `edit`, `bash`, `bash_output`, `bash_kill`, or the identifier an extension tool declares.

The allowlist names tools, not extensions: `--tools bash` gives the model `bash` without `bash_output` and `bash_kill`, so it can start background jobs but not follow or stop them. A name that matches no tool is reported as `Unknown tool in allowlist: NAME`, so a typo doesn't silently drop a tool. The allowlist does not apply to [MCP](MCP.md#tool-names) tools.

## Provider-native tools

Web search runs inside the provider's own request, so it is part of the core rather than an extension. [`tools.native`](CONFIGURATION.md#toolsnative) switches it on. `anthropic`, `openai` and `azure_openai` support it, and a `/model` switch turns the tool on or off to match the new provider.

## Replacing a tool

Register a tool with the same identifier from a later extension:

```ruby
class SandboxedBash < Riffer::Tool
  identifier 'bash'
  description 'Run a shell command inside the sandbox.'

  params do
    required :command, String, description: 'The command to run'
  end

  def call(context:, command:)
    output, status = Sandbox.run(command)
    status.success? ? text(output) : error(output, type: :execution_error)
  end
end

Riffer::Rig.extension('sandbox') { |rig| rig.tool SandboxedBash }
```

The later registration [takes the earlier tool's place](EXTENSIONS.md#bundled-extensions-and-replacement). Replacement is per identifier: a replaced `bash` leaves `bash_output` and `bash_kill` registered, acting only on jobs the bundled `bash` started.
