# Extensions

An extension is a named block of Ruby that registers things — tools, commands, prompt sections, hooks — with each session. The same extension works in the terminal, headless, over ACP and inside your app.

## A complete example

Put this in `.riffer/rig.rb` in a project, or `~/.riffer/rig.rb` for every project:

```ruby
require 'open3'

class GitLog < Riffer::Tool
  description 'Show the most recent commits in the working directory, newest first.'

  params do
    optional :count, Integer, default: 10, description: 'How many commits to show'
  end

  def call(context:, count: 10)
    output, status = Open3.capture2e('git', 'log', '--oneline', "-n#{count}", chdir: context&.[](:cwd) || Dir.pwd)
    status.success? ? text(output) : error(output, type: :execution_error)
  end
end

Riffer::Rig.extension('git') do |rig|
  rig.tool GitLog
  rig.command('log', description: 'Recent commits') { |ctx| ctx.say `git log --oneline -n 5` }
  rig.prompt(:branch) { "Current branch: #{`git branch --show-current`}" }
end
```

Start `riffer` and the extension is live:

- the model has a `git_log` tool, described by the `description` and `params` above, which it can call whenever it judges a request needs one;
- `/log` prints the last five commits, without involving the model;
- every turn's system message ends with the current branch.

Edit the file and the next turn picks up the change ([Reloading](RELOADING.md)). A tool is an ordinary riffer tool: riffer's [tools guide](https://riffer.ai/guides/tools/) covers parameters, nested params and responses.

## The `rig.rb` files

Two files are loaded, in this order:

1. `~/.riffer/rig.rb` — for every project; always trusted.
2. `<cwd>/.riffer/rig.rb` — for this project; asked about the first time it is seen.

They are plain Ruby: `require` gems, `require_relative` your own files, or call `Riffer::Rig.extension` inline. What they load is what runs; there is no manifest or list of extensions in settings.

The project file can run anything, so riffer-rig asks before loading it, and remembers the answer by path in `~/.riffer/trust.json`:

| Answer                                                    | Result                                                            |
| --------------------------------------------------------- | ----------------------------------------------------------------- |
| yes                                                       | stored; the file loads now and in every later session             |
| no                                                        | stored; the file is skipped until you remove its entry from `trust.json` |
| no answer (Ctrl-C or Ctrl-D)                              | skipped this time; asked again next time                          |
| nobody to ask (headless, ACP while starting, an app with the null host) | skipped; nothing stored, so the terminal can ask later |

A `rig.rb` that raises is reported, and none of its extensions load, while the other file's still do. A bad `require` stops startup.

## Gem extensions

To share an extension as a gem, name it `riffer-rig-<name>`, put its entry point at `lib/riffer/rig/<name>.rb`, and have that file call `Riffer::Rig.extension('<name>')`. Users load it with `require 'riffer/rig/<name>'` in a `rig.rb`.

A gem can also ship `lib/riffer/rig/extension.rb`, which loads automatically when a user sets `"extensions": {"autoload": true}` ([Configuration](CONFIGURATION.md#extensions)).

Gem extensions don't [reload](RELOADING.md): develop as a local file required from `rig.rb`, and package it once it settles.

## The seams

The `rig` object passed to the block has one method per kind of thing an extension can register:

| Seam                                  | Registers                                          |
| ------------------------------------- | -------------------------------------------------- |
| [`rig.tool`](#the-rigtool-seam)       | a tool the model can call                          |
| [`rig.prompt`](#the-rigprompt-seam)   | a section of the system message                    |
| [`rig.command`](#the-rigcommand-seam) | a slash command                                    |
| [`rig.on`](#the-rigon-seam)           | a hook on an event of the session                  |
| [`rig.skills`](#the-rigskills-seam)   | a source of Agent Skills                           |
| [`rig.mcp`](#the-rigmcp-seam)         | an MCP server                                      |
| [`rig.setting`](#the-rigsetting-seam) | a setting, with its default                        |
| [`rig.provider`](#the-rigprovider-seam) | a model provider                                 |

`Riffer::Rig.extension(name, requires: nil) { |rig| … }` records the block by name, so loading a file again replaces it rather than adding a duplicate. The block runs once for each Runtime, against that Runtime alone: keep per-session state in the block's local variables.

### The `rig.tool` seam

```ruby
rig.tool GitLog
```

Adds a `Riffer::Tool` class. Its identifier is its name everywhere, including [`--tools`](TOOLS.md#identifiers). A later tool with the same identifier [replaces](#bundled-extensions-and-replacement) it.

### The `rig.prompt` seam

```ruby
rig.prompt(:git_status) { |ctx| "Branch: #{`git -C #{ctx.cwd} branch --show-current`}" }
```

Adds a named section to the system message, after the base prompt and before the environment ([Instructions](INSTRUCTIONS.md)). The block runs at the start of every turn and returns the section's text as-is, so add your own heading if the model needs one. `nil` or an empty string leaves the section out of that turn. `ctx` is the Runtime: `ctx.cwd`, `ctx.settings`, `ctx.host`.

### The `rig.command` seam

```ruby
rig.command('log', description: 'Recent commits') { |ctx| ctx.say `git log -n #{ctx.args} --oneline` }
rig.command('review', description: 'Review the diff') { |ctx| ctx.prompt "Review this diff:\n#{`git diff`}" }
```

Adds a slash command, named without the slash. Commands work the same in every host. The block receives a `ctx`:

| Member                                       | Does                                                                                   |
| -------------------------------------------- | -------------------------------------------------------------------------------------- |
| `args`                                       | the text after the command name (`""` when there is none)                              |
| `say(text)`                                  | shows `text` as the command's output                                                   |
| `prompt(text)`                               | sends `text` to the model as your message, starting a turn                             |
| `ask(question, options: nil, secret: false)` | asks the user; `nil` when the host can't ask                                           |
| `confirm(question)`                          | asks yes or no; `false` when unanswered or the host can't ask                          |
| `settings`                                   | this extension's [settings](#the-rigsetting-seam), with defaults filled in              |
| `emit(event)`                                | sends a custom [event](EVENTS.md#custom-events) to whoever ran the command             |
| `runtime`, `host`                            | the Runtime, and its host                                                              |

A command that raises is reported, and the session carries on. Use `ctx.prompt` to start a turn: calling `ctx.runtime.prompt` from a command raises, because one is already running.

### The `rig.on` seam

```ruby
rig.on(:before_tool_call) { |e| next :block, 'no force pushes' if e.tool == 'bash' && e.args[:command] =~ /push --force/ }
rig.on(:before_prompt) { |e| "#{e.text}\n\nAnswer in one paragraph." }
rig.on(:turn_end) { |e| warn "turn cost $#{e.cost}" if e.cost }
```

Adds a hook for an event. Hooks for the same event run in load order. An unknown event name fails the extension.

| Event              | Kind        | Carries                                                    | Fires                                                       |
| ------------------ | ----------- | ---------------------------------------------------------- | ----------------------------------------------------------- |
| `session_start`    | lifecycle   | `id`, `reason` (`:new`, `:restore`, `:reload`)             | as the first turn starts, and after a reload swaps this extension in |
| `session_end`      | lifecycle   | `reason` (`:reload`, `:close`)                             | before a reload swaps this extension out, and when the session closes |
| `before_prompt`    | can change  | `text`                                                     | as each prompt starts                                       |
| `before_request`   | can change  | `messages`, the whole request                              | before every model call                                     |
| `before_tool_call` | can change  | `call_id`, `tool`, `args` (symbol keys), `at`              | before each tool runs                                       |
| `after_tool_call`  | observe     | `call_id`, `tool`, `args`, `result`, `at`, `duration`      | after every tool call, including ones that never ran        |
| `after_response`   | observe     | `message`, the assistant's reply                           | after each model response                                   |
| `turn_end`         | observe     | `stop_reason`, `usage`, `cost`                             | as each turn ends                                           |
| `stream`           | observe     | the riffer stream event                                    | for every riffer stream event                               |

Use lifecycle hooks to acquire and release anything process-wide. Observe hooks' return values are ignored. A hook that can change the event may return a replacement, which the next hook receives, or block:

| Event              | Return a replacement…                                              | Return `:block` or `[:block, reason]`…                                        |
| ------------------ | ------------------------------------------------------------------ | ----------------------------------------------------------------------------- |
| `before_prompt`    | a `String`: the text the model gets                                | the prompt never reaches the model; the user sees the reason; the turn ends `:guardrail_blocked` |
| `before_tool_call` | a `Hash`: the arguments the tool runs with                         | the tool doesn't run; the model gets a `blocked` tool error with the reason, and the turn carries on |
| `before_request`   | an `Array` of messages: the request, saved back to the session     | at the start of a turn it ends `:guardrail_blocked`; after tool results the turn is interrupted |

Any other return value, including `nil`, changes nothing. A hook that raises is reported and counts as no change. [Events](EVENTS.md#tool-call-events) covers what `after_tool_call` reports for calls that were blocked or never ran.

### The `rig.skills` seam

```ruby
rig.skills { |ctx| Riffer::Skills::FilesystemBackend.new(File.join(ctx.cwd, 'docs/skills')) }
```

Adds a source of [Agent Skills](SKILLS.md). The block returns a `Riffer::Skills::Backend` and runs when the session starts and on every reload. When two sources have a skill of the same name, the earlier source wins.

### The `rig.mcp` seam

```ruby
rig.mcp 'tracker', url: 'https://tracker.example.com/mcp', headers: { 'Authorization' => "Bearer #{ENV.fetch('TRACKER_TOKEN')}" }
```

Declares an HTTPS [MCP](MCP.md) server: `rig.mcp(name, url:, headers: {}, auth: {})`. `auth:` and `${field}` headers work as in [settings](MCP.md#secret-headers). A later declaration of the same name replaces the earlier one.

### The `rig.setting` seam

```ruby
Riffer::Rig.extension('git') do |rig|
  rig.setting :depth, default: 3
  rig.command('log', description: 'Recent commits') { |ctx| ctx.say `git log -n #{ctx.settings[:depth]} --oneline` }
end
```

Declares a key under the extension's namespace in [settings](CONFIGURATION.md#extension-namespaces) — here `"git": { "depth": 10 }` — with a default for when it is unset. Commands read it as `ctx.settings[:depth]` and prompt sections as `ctx.settings[:git][:depth]`; inside the block, `rig.settings` holds the values so far, so an extension can register according to them. An extension can't be named after a core settings key.

### The `rig.provider` seam

Registers a model provider under a new prefix. [Custom providers](CUSTOM_PROVIDERS.md) covers it.

## Bundled extensions and replacement

The built-in tools, AGENTS.md, skills and the MCP client are extensions too — `read`, `write`, `edit`, `bash`, `agents_md`, `skills` and `mcp` — built on the same seams. You can [disable](CONFIGURATION.md#extensions) any of them.

To replace one piece instead, register something with the same name from your own extension: a tool with the same identifier, a command, prompt section or MCP server with the same name. The later registration wins, takes the earlier one's place, and the session shows a notice such as `Extension sandbox replaces tool bash from bash`.

## Error isolation

An extension whose block raises, whose `requires:` doesn't match the installed riffer-rig, or that is named after a core settings key is skipped and [reported](TROUBLESHOOTING.md). The other extensions still load. Errors are shown to the user, never to the model.

## API versioning

`Riffer::Rig.extension` and the `rig.*` seams are riffer-rig's public API. While riffer-rig is 0.x, a breaking change ships in a minor release, with a deprecation release first where possible and a BREAKING CHANGES note in the [changelog](https://github.com/bottrall/riffer-rig/blob/main/CHANGELOG.md). Pin the versions an extension supports with `requires:`:

```ruby
Riffer::Rig.extension('git', requires: '~> 0.15') do |rig|
  # ...
end
```

On a riffer-rig outside the requirement, the extension is reported as failing to load rather than run.
