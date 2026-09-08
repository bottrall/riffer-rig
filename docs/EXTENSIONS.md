# Extensions

An extension is a named registrar block. Requiring a file records it; `Session.new` runs it against a fresh per-Session registrar.

## The unit: a named registrar block

```ruby
Riffer::Rig.extension('git', requires: '>= 0.3') do |rig|
  rig.tool GitLog
end
```

`Riffer::Rig.extension(name, requires: nil) { |rig| }` records the block in a process-level registry keyed by name and returns the extension object. Re-executing the same file (a reload) replaces the block rather than appending a duplicate. `requires:` is a `Gem::Requirement` string checked against the riffer-rig version when the block is recorded; a mismatch raises `Riffer::ArgumentError`.

`Session.new(extensions: [...])` runs each block, in order, against a fresh registrar for that Session. Two Sessions never share tools; per-Session state lives in the block's locals, per-process state lives outside the block. Same process, no sandbox.

## The `rig.tool` seam

```ruby
rig.tool klass
```

Adds a `Riffer::Tool` to the Session; its identifier is its name everywhere. When the extension block runs, the registrar collects the tool classes and the Session passes them to its agent. `tools:` on `Session.new` is an allowlist of tool identifiers over what extensions registered — `nil` (the default) means every registered tool.

## Error isolation

The Session wraps each registrar block. A failure skips that extension; the rest load. Errors go to the host only, never into the model's context.
