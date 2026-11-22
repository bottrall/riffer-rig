# Public API

riffer-rig's public API is exactly what this page lists: each constant below, and the methods shown under it. Anything not listed is internal, even when Ruby lets you call it or a signature here names it, and may change or disappear in any release.

While riffer-rig is 0.x, a change to anything listed ships in:

| Change          | Release                                                                                                                                                                      |
| --------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Breaking change | A minor release, where possible after a release that deprecates it, with its upgrade steps in the [changelog](https://github.com/bottrall/riffer-rig/blob/main/CHANGELOG.md) |
| New feature     | A minor release                                                                                                                                                              |
| Bug fix         | A patch release                                                                                                                                                              |

The signatures are [RBS](https://github.com/ruby/rbs).

## `Riffer::Rig`

```rbs
module Riffer::Rig
  def self.extension: (String name, ?requires: String?) { (::Riffer::Rig::Registrar) -> void } -> ::Riffer::Rig::Extension

  def self.credentials: (String | Symbol identifier) -> Hash[Symbol, String]?

  def self.bundled: (?Symbol? name) -> (::Riffer::Rig::Extension | Array[::Riffer::Rig::Extension])
end
```

## `Riffer::Rig::ACP`

```rbs
class Riffer::Rig::ACP
  def self.for: (input: IO, output: IO, env: ::Riffer::Rig::Env | ::Riffer::Rig::Env::Invalid, home: String, cwd: String, ?build: (^(String, ::Riffer::Rig::Hosts::_Host, Hash[String, ::Riffer::Rig::Mcp::Declaration]) -> ::Riffer::Rig::Runtime)?, ?adopt: (^(String) -> ::Riffer::Rig::Runtime?)?) -> ::Riffer::Rig::ACP

  def self.build_runtime: (String cwd, ::Riffer::Rig::Hosts::_Host host, Hash[String, ::Riffer::Rig::Mcp::Declaration] servers, env: ::Riffer::Rig::Env | ::Riffer::Rig::Env::Invalid, home: String) -> ::Riffer::Rig::Runtime

  def run: () ?{ (::ACP::AgentConnection) -> void } -> Integer
end
```

## `Riffer::Rig::Command`

```rbs
class Riffer::Rig::Command
  attr_reader name: String

  attr_reader description: String
end
```

## `Riffer::Rig::Command::Context`

```rbs
class Riffer::Rig::Command::Context
  attr_reader args: String

  attr_reader runtime: ::Riffer::Rig::Runtime

  attr_reader host: ::Riffer::Rig::Hosts::_Host

  attr_reader settings: Hash[Symbol, untyped]

  def say: (String text) -> nil

  def emit: (::Riffer::Rig::Events::_Event event) -> nil

  def prompt: (String text) -> nil

  def ask: (?String? question, ?options: Array[String]?, ?secret: bool) -> String?

  def confirm: (?String? question) -> bool
end
```

## `Riffer::Rig::Command::INVOCATION`

```rbs
Riffer::Rig::Command::INVOCATION: Regexp
```

## `Riffer::Rig::Credentials`

```rbs
module Riffer::Rig::Credentials
  extend ::Riffer::Rig::Credentials

  def install: (String | Symbol identifier, host: ::Riffer::Rig::Hosts::_Host, ?setup: ::Riffer::Rig::ProviderSetup, ?env: ::Riffer::Rig::Env, ?config: Riffer::Config?, ?auth_path: String, ?settings_path: String, ?known: Hash[Symbol, String]) -> (::Riffer::Rig::Credentials::Resolution | String)

  def apply: (String | Symbol identifier, Hash[Symbol, String] values, ?config: Riffer::Config) -> void

  def store: (String | Symbol identifier, Hash[Symbol, String] values, ?setup: ::Riffer::Rig::ProviderSetup, ?auth_path: String, ?settings_path: String) -> String?

  def remove: (String | Symbol identifier, ?auth_path: String, ?settings_path: String) -> String?

  def status: (String | Symbol identifier, ?setup: ::Riffer::Rig::ProviderSetup, ?env: ::Riffer::Rig::Env, ?auth_path: String) -> (:env | :stored | :chain | :missing | String)
end
```

## `Riffer::Rig::Credentials::Resolution`

```rbs
class Riffer::Rig::Credentials::Resolution
  attr_reader values: Hash[Symbol, String]

  attr_reader missing: Array[Symbol]
end
```

## `Riffer::Rig::Env`

```rbs
class Riffer::Rig::Env
  def self.load: (?Hash[String, String] source) -> (::Riffer::Rig::Env | ::Riffer::Rig::Env::Invalid)

  def initialize: (?Hash[String, String] source) -> void
end
```

## `Riffer::Rig::Env::Invalid`

```rbs
class Riffer::Rig::Env::Invalid < Data
end
```

## `Riffer::Rig::Events::AfterResponse`

```rbs
class Riffer::Rig::Events::AfterResponse
  attr_reader message: ::Riffer::Messages::Assistant

  def type: () -> Symbol

  def to_h: () -> Hash[Symbol, untyped]
end
```

## `Riffer::Rig::Events::AfterToolCall`

```rbs
class Riffer::Rig::Events::AfterToolCall
  attr_reader call_id: String

  attr_reader tool: String

  attr_reader args: Hash[Symbol, untyped]

  attr_reader result: ::Riffer::Tools::Response

  attr_reader at: Float

  attr_reader duration: Float

  def type: () -> Symbol

  def to_h: () -> Hash[Symbol, untyped]
end
```

## `Riffer::Rig::Events::BeforePrompt`

```rbs
class Riffer::Rig::Events::BeforePrompt
  attr_reader text: String

  def type: () -> Symbol

  def to_h: () -> Hash[Symbol, untyped]
end
```

## `Riffer::Rig::Events::BeforeRequest`

```rbs
class Riffer::Rig::Events::BeforeRequest
  attr_reader messages: Array[::Riffer::Messages::Base]

  def type: () -> Symbol

  def to_h: () -> Hash[Symbol, untyped]
end
```

## `Riffer::Rig::Events::BeforeToolCall`

```rbs
class Riffer::Rig::Events::BeforeToolCall
  attr_reader call_id: String

  attr_reader tool: String

  attr_reader args: Hash[Symbol, untyped]

  attr_reader at: Float

  def type: () -> Symbol

  def to_h: () -> Hash[Symbol, untyped]
end
```

## `Riffer::Rig::Events::CommandOutput`

```rbs
class Riffer::Rig::Events::CommandOutput
  attr_reader command: String

  attr_reader text: String

  def type: () -> Symbol

  def to_h: () -> Hash[Symbol, untyped]
end
```

## `Riffer::Rig::Events::JobExit`

```rbs
class Riffer::Rig::Events::JobExit
  attr_reader job_id: String

  attr_reader command: String

  attr_reader exit_status: Integer?

  attr_reader signal: String?

  attr_reader duration: Float

  attr_reader output_path: String

  def type: () -> Symbol

  def to_h: () -> Hash[Symbol, untyped]
end
```

## `Riffer::Rig::Events::Notify`

```rbs
class Riffer::Rig::Events::Notify
  attr_reader message: String?

  attr_reader level: Symbol

  def type: () -> Symbol

  def to_h: () -> Hash[Symbol, untyped]
end
```

## `Riffer::Rig::Events::SessionEnd`

```rbs
class Riffer::Rig::Events::SessionEnd
  attr_reader reason: Symbol

  def type: () -> Symbol

  def to_h: () -> Hash[Symbol, untyped]
end
```

## `Riffer::Rig::Events::SessionStart`

```rbs
class Riffer::Rig::Events::SessionStart
  attr_reader id: String

  attr_reader reason: Symbol

  def type: () -> Symbol

  def to_h: () -> Hash[Symbol, untyped]
end
```

## `Riffer::Rig::Events::SkillActivated`

```rbs
class Riffer::Rig::Events::SkillActivated
  attr_reader name: String

  def type: () -> Symbol

  def to_h: () -> Hash[Symbol, untyped]
end
```

## `Riffer::Rig::Events::TurnEnd`

```rbs
class Riffer::Rig::Events::TurnEnd
  attr_reader stop_reason: Symbol

  attr_reader usage: ::Riffer::Providers::TokenUsage?

  def cost: () -> Float?

  def type: () -> Symbol

  def to_h: () -> Hash[Symbol, untyped]
end
```

## `Riffer::Rig::Events::_Event`

```rbs
interface Riffer::Rig::Events::_Event
  def class: () -> ::Class

  def type: () -> Symbol

  def to_h: () -> Hash[Symbol, untyped]
end
```

## `Riffer::Rig::Extension`

```rbs
class Riffer::Rig::Extension
  attr_reader name: String
end
```

## `Riffer::Rig::Extension::Failure`

```rbs
class Riffer::Rig::Extension::Failure < Data
  attr_reader extension(): ::Riffer::Rig::Extension

  attr_reader error(): StandardError

  def self.new: (::Riffer::Rig::Extension extension, StandardError error) -> instance
              | (extension: ::Riffer::Rig::Extension, error: StandardError) -> instance

  def self.members: () -> [ :extension, :error ]

  def members: () -> [ :extension, :error ]
end
```

## `Riffer::Rig::Hosts::Mirror`

```rbs
class Riffer::Rig::Hosts::Mirror
  attr_reader host: ::Riffer::Rig::Hosts::_Host

  def capabilities: () -> Set[Symbol]

  def ask: (?String? question, ?options: Array[String]?, ?secret: bool) -> String?

  def confirm: (?String? question) -> bool?

  def notify: (?String? message, ?level: Symbol) -> void

  def progress: (?String? label) ?{ () -> void } -> void
end
```

## `Riffer::Rig::Hosts::NonInteractive`

```rbs
module Riffer::Rig::Hosts::NonInteractive
  def ask: (?String? question, ?options: Array[String]?, ?secret: bool) -> String?

  def confirm: (?String? question) -> bool

  def progress: (?String? label) ?{ () -> void } -> void
end
```

## `Riffer::Rig::Hosts::Null`

```rbs
class Riffer::Rig::Hosts::Null
  include ::Riffer::Rig::Hosts::NonInteractive

  def capabilities: () -> Set[Symbol]

  def notify: (?String? message, ?level: Symbol) -> void
end
```

## `Riffer::Rig::Hosts::_Host`

```rbs
interface Riffer::Rig::Hosts::_Host
  def capabilities: () -> Set[Symbol]

  def ask: (?String?, ?options: Array[String]?, ?secret: bool) -> String?

  def confirm: (?String?) -> bool?

  def notify: (?String?, ?level: Symbol) -> void

  def progress: (?String?) ?{ () -> void } -> void
end
```

## `Riffer::Rig::Loader`

```rbs
class Riffer::Rig::Loader
  def self.runtime: (cwd: String, host: ::Riffer::Rig::Hosts::_Host, ?env: ::Riffer::Rig::Env | ::Riffer::Rig::Env::Invalid, ?home: String, ?riffer_config: Riffer::Config, ?store: ::Riffer::Rig::Stores::_Store | nil, ?options: ::Riffer::Rig::Loader::Options, ?reload: :auto | :manual | nil, ?extra_extensions: Array[::Riffer::Rig::Extension], ?snapshot: (::Riffer::Rig::Runtime::Snapshot | Hash[Symbol, untyped])?) -> ::Riffer::Rig::Runtime

  def initialize: (cwd: String, host: ::Riffer::Rig::Hosts::_Host, ?env: ::Riffer::Rig::Env | ::Riffer::Rig::Env::Invalid, ?home: String, ?riffer_config: Riffer::Config, ?store: ::Riffer::Rig::Stores::_Store | nil, ?sdk: singleton(::Riffer::Rig::SDK)) -> void

  def runtime: (?::Riffer::Rig::Loader::Options options, ?reload: :auto | :manual | nil, ?extra_extensions: Array[::Riffer::Rig::Extension], ?snapshot: (::Riffer::Rig::Runtime::Snapshot | Hash[Symbol, untyped])?) -> ::Riffer::Rig::Runtime

  def continue: (?::Riffer::Rig::Loader::Options options) -> ::Riffer::Rig::Runtime?

  def resume: (String id, ?::Riffer::Rig::Loader::Options options, ?extra_extensions: Array[::Riffer::Rig::Extension]) -> ::Riffer::Rig::Runtime?

  def list: (?all: bool) -> Array[::Riffer::Rig::Stores::Header]

  def delete: (String id) -> void

  def reload: (::Riffer::Rig::Runtime runtime, ?force: bool) -> (::Riffer::Rig::Runtime | String)
end
```

## `Riffer::Rig::Loader::ConfigurationError`

```rbs
class Riffer::Rig::Loader::ConfigurationError < StandardError
end
```

## `Riffer::Rig::Loader::Options`

```rbs
class Riffer::Rig::Loader::Options
  attr_reader model: String?

  attr_reader reasoning: String?

  attr_reader extensions: bool

  attr_reader skills: bool

  attr_reader agents_md: bool

  attr_reader tools: Array[String]?

  attr_reader max_steps: Integer?

  def initialize: (?model: String?, ?reasoning: String?, ?extensions: bool, ?skills: bool, ?agents_md: bool, ?tools: Array[String]?, ?max_steps: Integer?) -> void
end
```

## `Riffer::Rig::Registrar`

```rbs
class Riffer::Rig::Registrar
  def tool: (singleton(Riffer::Tool) klass) -> void

  def prompt: (Symbol name) { (::Riffer::Rig::Runtime) -> String? } -> void

  def command: (String name, description: String) { (::Riffer::Rig::Command::Context) -> void } -> void

  def skills: () { (::Riffer::Rig::Runtime) -> Riffer::Skills::Backend } -> void

  def setting: (Symbol key, default: untyped) -> void

  def mcp: (String name, ?url: String?, ?headers: Hash[String, String], ?auth: Hash[Symbol, String | Array[String]], ?command: String?, ?args: Array[String], ?env: Hash[String, String]) -> void

  def provider: (String | Symbol prefix, ?setup: ::Riffer::Rig::ProviderSetup | Hash[Symbol, untyped]?) { () -> singleton(::Riffer::Providers::Base) } -> void

  def on: (Symbol event) { (::Riffer::Rig::Events::_Event | ::Riffer::StreamEvents::Base) -> untyped } -> void

  def settings: () -> Hash[Symbol, untyped]
end
```

## `Riffer::Rig::Runtime`

```rbs
class Riffer::Rig::Runtime
  attr_reader cwd: String

  attr_reader host: ::Riffer::Rig::Hosts::Mirror

  attr_reader id: String

  def initialize: (String model, ?extensions: Array[::Riffer::Rig::Extension], ?tools: Array[String]?, ?settings: Hash[Symbol, untyped], ?host: ::Riffer::Rig::Hosts::_Host, ?cwd: String?, ?name: String, ?instructions: String?, ?credentials: Hash[Symbol, Hash[Symbol, String]], ?env: ::Riffer::Rig::Env, ?auth_path: String, ?settings_path: String, ?reasoning: String?, ?riffer_config: Riffer::Config, ?mcp_registry: ::Riffer::Rig::Mcp::_Registry, ?max_steps: Integer?, ?model_options: Hash[Symbol, untyped], ?native_tools: Hash[Symbol, untyped], ?max_tokens: Integer?, ?clock: ^() -> Float, ?snapshot: (::Riffer::Rig::Runtime::Snapshot | Hash[Symbol, untyped])?) -> void

  def prompt: (String text) ?{ (::Riffer::StreamEvents::Base | ::Riffer::Rig::Events::_Event) -> void } -> (nil | Enumerator[::Riffer::StreamEvents::Base | ::Riffer::Rig::Events::_Event, Riffer::Agent::Response])

  def follow_up: () ?{ (::Riffer::StreamEvents::Base | ::Riffer::Rig::Events::_Event) -> void } -> (nil | Enumerator[::Riffer::StreamEvents::Base | ::Riffer::Rig::Events::_Event, Riffer::Agent::Response])

  def ask: (String text) -> Riffer::Agent::Response

  def commands: () -> Array[::Riffer::Rig::Command]

  def run_command: (String name, ?String args) ?{ (::Riffer::StreamEvents::Base | ::Riffer::Rig::Events::_Event) -> void } -> nil

  def errors: () -> Array[::Riffer::Rig::Extension::Failure]

  def settings: () -> Hash[Symbol, untyped]

  def declared_settings: () -> Hash[Symbol, Hash[Symbol, untyped]]

  def model=: (String model) -> void

  def reasoning=: (String level) -> void

  def rebuild: (extensions: Array[::Riffer::Rig::Extension], settings: Hash[Symbol, untyped]) -> nil

  def to_h: () -> Hash[Symbol, untyped]

  def on_message: () { (Riffer::Messages::Base) -> void } -> nil

  def on_job_exit: () { (::Riffer::Rig::Runtime::JobCompletion) -> void } -> nil

  def running_job_count: () -> Integer

  def busy?: () -> bool

  def pending_jobs?: () -> bool

  def await_job_exit: (?timeout: Numeric?) -> bool

  def pending_job_exit_count: () -> Integer

  def cancel: () -> nil

  def tally: () -> Riffer::Providers::TokenUsage?

  def close: () -> void
end
```

## `Riffer::Rig::Runtime::BusyError`

```rbs
class Riffer::Rig::Runtime::BusyError < StandardError
end
```

## `Riffer::Rig::Runtime::CancelFlag`

```rbs
class Riffer::Rig::Runtime::CancelFlag
  def set?: () -> bool
end
```

## `Riffer::Rig::Runtime::ErrorMessage`

```rbs
module Riffer::Rig::Runtime::ErrorMessage
  extend ::Riffer::Rig::Runtime::ErrorMessage

  def of: (StandardError error) -> String
end
```

## `Riffer::Rig::Runtime::Job`

```rbs
class Riffer::Rig::Runtime::Job
  attr_reader id: String

  attr_reader output_path: String
end
```

## `Riffer::Rig::Runtime::JobCompletion`

```rbs
class Riffer::Rig::Runtime::JobCompletion < Data
  attr_reader job_id(): String

  attr_reader command(): String

  attr_reader exit_status(): Integer?

  attr_reader signal(): String?

  attr_reader duration(): Float

  attr_reader output_path(): String

  attr_reader tail(): String

  def self.new: (String job_id, String command, Integer? exit_status, String? signal, Float duration, String output_path, String tail) -> instance
              | (job_id: String, command: String, exit_status: Integer?, signal: String?, duration: Float, output_path: String, tail: String) -> instance

  def self.members: () -> [ :job_id, :command, :exit_status, :signal, :duration, :output_path, :tail ]

  def members: () -> [ :job_id, :command, :exit_status, :signal, :duration, :output_path, :tail ]
end
```

## `Riffer::Rig::Runtime::JobNotification`

```rbs
class Riffer::Rig::Runtime::JobNotification < Riffer::Messages::User
  attr_reader follow_up_exits: Integer?

  def to_h: () -> Hash[Symbol, untyped]
end
```

## `Riffer::Rig::Runtime::Jobs`

```rbs
class Riffer::Rig::Runtime::Jobs
  def register: (Integer pid, String command, IO output) -> ::Riffer::Rig::Runtime::Job
end
```

## `Riffer::Rig::Stores::Header`

```rbs
class Riffer::Rig::Stores::Header
  attr_reader schema_version: Integer

  attr_reader id: String

  attr_reader cwd: String

  attr_reader created_at: String

  attr_reader model: String

  attr_reader riffer_rig_version: String

  attr_reader riffer_version: String

  attr_reader title: String

  attr_reader updated: Time?

  def initialize: (schema_version: Integer, id: String, cwd: String, created_at: String, model: String, riffer_rig_version: String, riffer_version: String, title: String, ?updated: Time?) -> void
end
```

## `Riffer::Rig::Stores::JSONL`

```rbs
class Riffer::Rig::Stores::JSONL
  def initialize: (?home: String) -> void

  def append: (String id, ::Riffer::Rig::Stores::entry entry) -> void

  def read: (String id) -> Array[::Riffer::Rig::Stores::entry]

  def list: (?cwd: String?) -> Array[::Riffer::Rig::Stores::Header]

  def delete: (String id) -> void
end
```

## `Riffer::Rig::Stores::MessageEntry`

```rbs
class Riffer::Rig::Stores::MessageEntry
  attr_reader message: Hash[Symbol, untyped]

  attr_reader recorded_at: String?

  def initialize: (message: Hash[Symbol, untyped], ?recorded_at: String?) -> void

  def recorded_time: () -> Time?
end
```

## `Riffer::Rig::Stores::ModelEntry`

```rbs
class Riffer::Rig::Stores::ModelEntry
  attr_reader model: String

  attr_reader recorded_at: String?

  def initialize: (model: String, ?recorded_at: String?) -> void

  def recorded_time: () -> Time?
end
```

## `Riffer::Rig::Stores::ReasoningEntry`

```rbs
class Riffer::Rig::Stores::ReasoningEntry
  attr_reader reasoning: String

  attr_reader recorded_at: String?

  def initialize: (reasoning: String, ?recorded_at: String?) -> void

  def recorded_time: () -> Time?
end
```

## `Riffer::Rig::Stores::SkillEntry`

```rbs
class Riffer::Rig::Stores::SkillEntry
  attr_reader skill: String

  attr_reader recorded_at: String?

  def initialize: (skill: String, ?recorded_at: String?) -> void

  def recorded_time: () -> Time?
end
```

## `Riffer::Rig::Stores::_Store`

```rbs
interface Riffer::Rig::Stores::_Store
  def append: (String id, ::Riffer::Rig::Stores::entry entry) -> void

  def read: (String id) -> Array[::Riffer::Rig::Stores::entry]

  def list: (?cwd: String?) -> Array[::Riffer::Rig::Stores::Header]

  def delete: (String id) -> void
end
```

## `Riffer::Rig::Stores::entry`

```rbs
type Riffer::Rig::Stores::entry = ::Riffer::Rig::Stores::Header | ::Riffer::Rig::Stores::MessageEntry | ::Riffer::Rig::Stores::ModelEntry | ::Riffer::Rig::Stores::ReasoningEntry | ::Riffer::Rig::Stores::SkillEntry
```

## `Riffer::Rig::VERSION`

```rbs
Riffer::Rig::VERSION: ::String
```
