# Extensions

An extension is a named registrar block. Requiring a file records it; `Runtime.new` runs it against a fresh per-Runtime registrar.

## The unit: a named registrar block

```ruby
Riffer::Rig.extension('git', requires: '>= 0.3') do |rig|
  rig.tool GitLog
end
```

`Riffer::Rig.extension(name, requires: nil) { |rig| }` records the block in a process-level registry keyed by name and returns the extension object. Re-executing the same file (a reload) replaces the block rather than appending a duplicate. `requires:` is a `Gem::Requirement` string checked against the riffer-rig version when the block is recorded; a mismatch raises `Riffer::ArgumentError`.

`Runtime.new(extensions: [...])` runs each block, in order, against a fresh registrar for that Runtime. Two Runtimes never share tools; per-Runtime state lives in the block's locals, per-process state lives outside the block. Same process, no sandbox.

## The `rig.tool` seam

```ruby
rig.tool klass
```

Adds a `Riffer::Tool` to the Runtime; its identifier is its name everywhere. When the extension block runs, the registrar collects the tool classes and the Runtime passes them to its agent. `tools:` on `Runtime.new` is an allowlist of tool identifiers over what extensions registered — `nil` (the default) means every registered tool.

## The `rig.prompt` seam

```ruby
rig.prompt(:git_status) { |ctx| "Branch: #{`git branch --show-current`}" }
```

Adds a named section to the system message. Sections render after the base prompt, in load order, and before the environment block; [Instructions](INSTRUCTIONS.md) shows the whole assembly.

- The block is evaluated at the start of every turn — each `prompt` or `ask` — so its content is always current without a reload. It receives the Runtime as `ctx` (`ctx.cwd`, `ctx.settings`, `ctx.host`) and returns the section's text.
- A later registration of the same name replaces the earlier block and keeps the earlier one's place in the order, so a user can swap a section an extension owns without disabling that extension.
- The text is appended as-is. A section that needs framing — a heading, a sentence saying whose instructions these are — writes that framing itself; the base prompt names no contributor. A section that returns `nil` or an empty string is left out of that turn's message.

## Error isolation

The Runtime wraps each registrar block. A failure skips that extension; the rest load. Errors go to the host only, never into the model's context.
