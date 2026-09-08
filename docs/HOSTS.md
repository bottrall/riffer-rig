# Hosts

A host receives questions and out-of-band messages from a `Riffer::Rig::Session`. It is duck-typed: any object with these methods is a host.

| Method                              | Purpose                                                        |
| ----------------------------------- | -------------------------------------------------------------- |
| `ask(question, options:, secret:)`  | free text or a choice from `options`; `secret:` hides input    |
| `confirm(question)`                 | yes or no                                                      |
| `notify(message, level:)`           | out-of-band message; never enters the model's context          |
| `progress(label) { }`               | wraps slow work                                                |
| `capabilities`                      | the `Set` of methods the host truly supports                   |

`capabilities` is checked before asking, so a host that declines a capability is never asked and the caller takes the declined path.

## The null host

`Riffer::Rig::Host` is the do-nothing host and the Session's default: every capability is declined (`ask` returns `nil`, `confirm` returns `false`, `notify` is a no-op, `progress` yields).
