# Hosts

A host receives questions and out-of-band messages from a `Riffer::Rig::Runtime`. `Riffer::Rig::Hosts::Base` is the contract: a host is a subclass that implements every method below.

| Method                             | Purpose                                                     |
| ---------------------------------- | ----------------------------------------------------------- |
| `ask(question, options:, secret:)` | free text or a choice from `options`; `secret:` hides input |
| `confirm(question)`                | yes or no                                                   |
| `notify(message, level:)`          | out-of-band message; never enters the model's context       |
| `progress(label) { }`              | wraps slow work                                             |
| `capabilities`                     | the `Set` of methods the host truly supports                |

`Hosts::Base` is abstract: each of its methods raises `NotImplementedError`, so a host implements all five, including the ones it declines. `capabilities` is checked before asking, so a host that declines a capability is never asked and the caller takes the declined path.

```ruby
class MyHost < Riffer::Rig::Hosts::Base
  def capabilities = Set[:notify].freeze
  def ask(question = nil, options: nil, secret: false) = nil
  def confirm(question = nil) = false
  def notify(message = nil, level: :info) = warn("[#{level}] #{message}")
  def progress(label = nil, &block) = block&.call
end
```

## The null host

`Riffer::Rig::Hosts::Null` is the do-nothing host and the Runtime's default: every capability is declined (`ask` returns `nil`, `confirm` returns `false`, `notify` is a no-op, `progress` yields).

## The mirror

The Runtime wraps the host it is given in a `Riffer::Rig::Hosts::Mirror`, which is what `runtime.host` returns. The mirror forwards every call to the wrapped host and queues a `notify` event for each `notify`, so a consumer of the event stream sees what the host saw.
