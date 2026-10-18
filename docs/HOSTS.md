# Hosts

A host is a front end for a Runtime: the terminal, headless mode and the ACP adapter are hosts, and so is anything you build — a Rails controller, a Slack bot, a job. It has two parts:

- **a host object**, which the Runtime asks questions and gives notices to;
- **a loop**, which builds a Runtime, sends it prompts and renders its [events](EVENTS.md).

## A minimal host

```ruby
require 'riffer/rig'

class ConsoleHost
  include Riffer::Rig::Hosts::NonInteractive

  def capabilities = Set[:notify].freeze
  def notify(message = nil, level: :info) = warn("[#{level}] #{message}")
end

def render(event)
  case event
  when Riffer::StreamEvents::TextDelta then print event.content
  when Riffer::Rig::Events::CommandOutput then puts event.text
  when Riffer::Rig::Events::TurnEnd then puts "\n(#{event.stop_reason})"
  end
end

runtime = Riffer::Rig::Loader.runtime(cwd: Dir.pwd, host: ConsoleHost.new)
trap('INT') { Thread.new { runtime.cancel } }

while (line = $stdin.gets&.chomp)
  next if line.empty?

  if line.start_with?('/')
    name, args = line.delete_prefix('/').split(' ', 2)
    runtime.run_command(name, args.to_s) { |event| render(event) }
  else
    runtime.prompt(line) { |event| render(event) }
  end
end

runtime.close
```

`cancel` is called from a new thread because it takes a lock, which Ruby doesn't allow inside a signal handler. This host can't ask questions, so a missing model or credential raises a [`ConfigurationError`](EMBEDDING.md#building-a-runtime-with-the-loader) at startup, and an untrusted project `rig.rb` is skipped.

## The host object

A host object implements every method of the RBS interface `Riffer::Rig::Hosts::_Host`:

| Method                             | Called for                                                    |
| ---------------------------------- | ------------------------------------------------------------- |
| `ask(question, options:, secret:)` | free text, or a choice from `options`; `secret:` hides input   |
| `confirm(question)`                | yes or no: `true`, `false`, or `nil` when left unanswered      |
| `notify(message, level:)`          | a notice for the user (`:info`, `:warning`, `:error`); never shown to the model |
| `progress(label) { }`              | slow work, such as installing a gem; must run the block        |
| `capabilities`                     | the `Set` of the methods above the host really supports         |

Callers check `capabilities` before calling `ask` or `confirm`, so a host that can't ask is never asked and the caller carries on without an answer. Return `nil` from `confirm` when the user walks away rather than answering: a `nil` trust answer asks again next time, while `false` is remembered as a no.

`Riffer::Rig::Hosts::NonInteractive` supplies the declining versions — `ask` returns `nil`, `confirm` returns `false`, `progress` runs the block — for a host that leaves `:ask` and `:confirm` out of its capabilities. `Riffer::Rig::Hosts::Null` is the do-nothing host the Runtime uses by default.

`runtime.host` returns the host wrapped so that each `notify` also appears on the event stream; `runtime.host.host` is the object you passed.

## The loop

| Task                    | Use                                                                                          |
| ----------------------- | -------------------------------------------------------------------------------------------- |
| build                   | [`Loader.runtime`](EMBEDDING.md#building-a-runtime-with-the-loader), turning your flags into [`Loader::Options`](EMBEDDING.md#loader-options) |
| send a message          | `runtime.prompt(text) { |event| … }`                                                          |
| run a slash command     | `runtime.run_command(name, args) { |event| … }`; an unknown name is reported through `notify`, so you need no list of your own |
| stop a turn             | [`runtime.cancel`](EMBEDDING.md#cancelling-a-turn), from another thread                      |
| save as you go          | [`runtime.on_message`](EMBEDDING.md#observing-messages), or let the Loader's store do it      |
| follow background jobs  | [`on_job_exit`, `follow_up` and friends](EMBEDDING.md#background-jobs)                        |
| end the session         | `runtime.close`                                                                              |

A host that offers `/exit`, `/new`, `/resume` or `/help` implements them itself: they end, replace or describe the Runtime. A host that swaps one Runtime for another closes the old one and subscribes again on the new one.

Use only the public API of the Runtime, the Loader, the host classes and the events; anything else a host needs should become part of that API, so every embedder gets it.

## The shipped hosts

| Host     | Capabilities                     | `ask`                                    | `confirm`                         | `notify`                              |
| -------- | -------------------------------- | ---------------------------------------- | --------------------------------- | ------------------------------------- |
| terminal | all four                         | reads a line, without echo for a secret; numbered options | `[y/N]`                 | a line above the input, red for errors |
| headless | `notify`, `progress`             | declined                                 | declined                          | stderr                                |
| ACP      | `notify`, then `ask` and `confirm` once the session has started | [relayed to the client](ACP.md#questions) | relayed to the client | an `agent_message_chunk`          |
