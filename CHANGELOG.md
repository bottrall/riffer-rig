# Changelog

## [0.8.0](https://github.com/bottrall/riffer-rig/compare/v0.7.0...v0.8.0) (2026-10-02)


### Features

* discover rig.rb files with project trust and optional gem autoload ([#208](https://github.com/bottrall/riffer-rig/issues/208)) ([6ed818f](https://github.com/bottrall/riffer-rig/commit/6ed818f5b5d382b3a9c7d48ce667892b10190985))
* truncate tool output and fit lines to the terminal width ([#209](https://github.com/bottrall/riffer-rig/issues/209)) ([3765de1](https://github.com/bottrall/riffer-rig/commit/3765de1f4392d903939c1458e843c2ca1e70112e))

## [0.7.0](https://github.com/bottrall/riffer-rig/compare/v0.6.0...v0.7.0) (2026-09-30)


### ⚠ BREAKING CHANGES

* Riffer::Rig::CodingAgent, REPL, TokenTally and the UI namespace are removed, and the old CLI is replaced by the dispatcher. Embed a Runtime through Riffer::Rig::Loader.runtime instead of CodingAgent; the terminal UI classes now live under Riffer::Rig::Terminal. The bash tool now errors when its context has no :cwd.
* DEFAULT_MODEL is gone; with no model the Loader asks the host to onboard and the null host's refusal is a configuration error. The old Settings module API changes shape.
* Riffer::Rig::Hosts::Base and Riffer::Rig::Events::Event are removed. A host is any object implementing the five host methods (Riffer::Rig::Hosts::_Host); drop the superclass. A custom event drops the superclass and super(), and includes Riffer::Rig::Events::Value for equality.

### Features

* /model switches the model for the current Runtime ([#193](https://github.com/bottrall/riffer-rig/issues/193)) ([f888972](https://github.com/bottrall/riffer-rig/commit/f8889722f62499f97ee34158826e9d00dd3d92ef))
* bundle Agent Skills with /skill: commands over the skills seam ([#201](https://github.com/bottrall/riffer-rig/issues/201)) ([e14844d](https://github.com/bottrall/riffer-rig/commit/e14844d9c7c22dd85b3d4158892ec53bae736c6b))
* bundle AGENTS.md as the agents_md prompt section ([#198](https://github.com/bottrall/riffer-rig/issues/198)) ([e2e9141](https://github.com/bottrall/riffer-rig/commit/e2e914195f7c15c75ee2ae6bb55d772d754a2f37))
* bundle read, write, edit and bash as extensions ([#195](https://github.com/bottrall/riffer-rig/issues/195)) ([d5c9ffe](https://github.com/bottrall/riffer-rig/commit/d5c9ffe692abf5e5cab16af0686f96b040a6cbaa))
* bundle the MCP client over the mcp seam ([#202](https://github.com/bottrall/riffer-rig/issues/202)) ([c2fc42f](https://github.com/bottrall/riffer-rig/commit/c2fc42ff873af8205f3a8042069a3dd5f27420e6))
* isolate extension load errors and check requires ([#192](https://github.com/bottrall/riffer-rig/issues/192)) ([0aac3bf](https://github.com/bottrall/riffer-rig/commit/0aac3bf7d3b6ada84a4f38a40abc181f7d3f57c7)), closes [#114](https://github.com/bottrall/riffer-rig/issues/114)
* lifecycle, vetoable and observe hooks plus the stream passthrough ([#194](https://github.com/bottrall/riffer-rig/issues/194)) ([206d349](https://github.com/bottrall/riffer-rig/commit/206d349a4967081961372d1692b0946663f32a10))
* Loader builds a Runtime from settings, credentials and the bundle ([#205](https://github.com/bottrall/riffer-rig/issues/205)) ([01170fe](https://github.com/bottrall/riffer-rig/commit/01170fee282deae87aba1b8797cfe5cedc892deb)), closes [#123](https://github.com/bottrall/riffer-rig/issues/123)
* namespaced extension settings ([#196](https://github.com/bottrall/riffer-rig/issues/196)) ([dc16a84](https://github.com/bottrall/riffer-rig/commit/dc16a8424ea00ea0b39323db97309c9c94224443)), closes [#117](https://github.com/bottrall/riffer-rig/issues/117)
* rebuild the registrar in place ([#199](https://github.com/bottrall/riffer-rig/issues/199)) ([f4b742b](https://github.com/bottrall/riffer-rig/commit/f4b742b3f45a28f3c69d75a355c3a2880938de1b))
* runtime commands with run_command and the command context ([#190](https://github.com/bottrall/riffer-rig/issues/190)) ([159d007](https://github.com/bottrall/riffer-rig/commit/159d0077b34773fadb2cc6f5f66622b12e4b7a0e)), closes [#111](https://github.com/bottrall/riffer-rig/issues/111)
* snapshot and restore a Runtime ([#200](https://github.com/bottrall/riffer-rig/issues/200)) ([aaad579](https://github.com/bottrall/riffer-rig/commit/aaad5797e5e626b6f560b96a5f4cf1bf5bc379a3))
* Terminal drives a Loader-built Runtime ([#206](https://github.com/bottrall/riffer-rig/issues/206)) ([f805db6](https://github.com/bottrall/riffer-rig/commit/f805db625e69f90c2dd343bbb7ca016aba7cecf0))
* token tally and pricing behind the Runtime ([#189](https://github.com/bottrall/riffer-rig/issues/189)) ([1ccde0d](https://github.com/bottrall/riffer-rig/commit/1ccde0d1670feaa2a9b9c957bbe79fa80ca47d4f))


### Bug Fixes

* run steep check without attaching to a language server ([#197](https://github.com/bottrall/riffer-rig/issues/197)) ([4f0b92e](https://github.com/bottrall/riffer-rig/commit/4f0b92eeafcb4e4fb6d054c29d707fcfb39766d5))


### Code Refactoring

* interfaces over inheritance, POROs over hashes, new cops ([#204](https://github.com/bottrall/riffer-rig/issues/204)) ([7fda3e3](https://github.com/bottrall/riffer-rig/commit/7fda3e3ec79ea97479008127f0c153ce84b888d5))

## [0.6.0](https://github.com/bottrall/riffer-rig/compare/v0.5.0...v0.6.0) (2026-09-27)


### ⚠ BREAKING CHANGES

* the flat `{"anthropic": "sk-..."}` auth.json shape is no longer read, with no migration. Stored keys must be re-entered or rewritten as `{"anthropic": {"type": "api_key", "api_key": "sk-..."}}`.
* Riffer::Rig::Host is removed. A host subclasses Riffer::Rig::Hosts::Base and implements all five methods; the null host is Riffer::Rig::Hosts::Null.

### Features

* add the rig event vocabulary and close ([#179](https://github.com/bottrall/riffer-rig/issues/179)) ([35bfa6e](https://github.com/bottrall/riffer-rig/commit/35bfa6e5dc1dc9825fd03843a4e69ec24e675b66))
* cancel a running turn from any thread ([#186](https://github.com/bottrall/riffer-rig/issues/186)) ([ec68188](https://github.com/bottrall/riffer-rig/commit/ec68188cc7dbcaf0cd56dd41d83cda216661fbe7))
* **deps:** upgrade riffer to 0.49.0 ([#188](https://github.com/bottrall/riffer-rig/issues/188)) ([821413f](https://github.com/bottrall/riffer-rig/commit/821413f5af65bfcb159ddad532deb3c15779112d))
* named prompt sections rendered every turn ([#184](https://github.com/bottrall/riffer-rig/issues/184)) ([d190a07](https://github.com/bottrall/riffer-rig/commit/d190a07dfa99764b82bba00745a07e7738c3532a))
* provider setup table and typed auth.json credentials ([#185](https://github.com/bottrall/riffer-rig/issues/185)) ([0a30c35](https://github.com/bottrall/riffer-rig/commit/0a30c357793716acfabcd1ddd41ea9f98c8a6a8f))
* store credentials on the Runtime ([#181](https://github.com/bottrall/riffer-rig/issues/181)) ([474a515](https://github.com/bottrall/riffer-rig/commit/474a51586011e413482f0275a7abd3a542e91914))


### Code Refactoring

* make the host contract the abstract Hosts::Base ([#183](https://github.com/bottrall/riffer-rig/issues/183)) ([3fd4f14](https://github.com/bottrall/riffer-rig/commit/3fd4f14a193d546ae06e00776f209a52c0593854))

## [0.5.0](https://github.com/bottrall/riffer-rig/compare/v0.4.0...v0.5.0) (2026-09-19)


### Features

* add ask, max_steps and riffer response ([#178](https://github.com/bottrall/riffer-rig/issues/178)) ([948d753](https://github.com/bottrall/riffer-rig/commit/948d75354a7d0a5a9d35055b7d890dea9e51f1a1))
* add Runtime with a per-instance agent, base prompt and tool seam ([#160](https://github.com/bottrall/riffer-rig/issues/160)) ([97019ca](https://github.com/bottrall/riffer-rig/commit/97019ca6f80c95bcf22e443652f1d90d453d02de))
* type IO streams and JSON boundaries, dropping explicit untyped ([#174](https://github.com/bottrall/riffer-rig/issues/174)) ([22407be](https://github.com/bottrall/riffer-rig/commit/22407befc471d1fbbe14188456ee1ce248ddc4c7))


### Bug Fixes

* drain smoother backlog before every animator restart ([#177](https://github.com/bottrall/riffer-rig/issues/177)) ([3126155](https://github.com/bottrall/riffer-rig/commit/3126155fdeba3de2ab2b9905b7e7de55593de834))
* drop invalid ? optional markers from rbs-inline annotations ([#171](https://github.com/bottrall/riffer-rig/issues/171)) ([60030bf](https://github.com/bottrall/riffer-rig/commit/60030bf7ca930e9d35cbd8c2e3a8ae8ae1692830))

## [0.4.0](https://github.com/bottrall/riffer-rig/compare/v0.3.0...v0.4.0) (2026-09-13)


### Features

* **ui:** one blank line between blocks, prompt-owned gaps ([#170](https://github.com/bottrall/riffer-rig/issues/170)) ([636e4d8](https://github.com/bottrall/riffer-rig/commit/636e4d82a069f158775043037a43e2aa494f56dc))


### Bug Fixes

* **lint:** adjust rubocop rules and reformat to match ([#168](https://github.com/bottrall/riffer-rig/issues/168)) ([56b81aa](https://github.com/bottrall/riffer-rig/commit/56b81aa904609f246340c8b8135ee7e57791abdd))

## [0.3.0](https://github.com/bottrall/riffer-rig/compare/v0.2.1...v0.3.0) (2026-09-10)


### Features

* **types:** strict rbs-inline typing with collection-managed third-party RBS ([#164](https://github.com/bottrall/riffer-rig/issues/164)) ([be59fb9](https://github.com/bottrall/riffer-rig/commit/be59fb9102d9c6f9bae2a5f456650cc68131924f))


### Bug Fixes

* print tool call lines after the round's stats line ([#166](https://github.com/bottrall/riffer-rig/issues/166)) ([dcc4e80](https://github.com/bottrall/riffer-rig/commit/dcc4e8093ffaec0bc93bb3eaafb47acd72292710))

## [0.2.1](https://github.com/bottrall/riffer-rig/compare/v0.2.0...v0.2.1) (2026-09-08)


### Bug Fixes

* **ui:** hide the cursor while a turn is in flight ([#161](https://github.com/bottrall/riffer-rig/issues/161)) ([0d18fe0](https://github.com/bottrall/riffer-rig/commit/0d18fe06c51bb75a8f3002d22d64bda23671bad6))
* **ui:** stop the equalizer before the end-of-turn newline ([#158](https://github.com/bottrall/riffer-rig/issues/158)) ([00edaa3](https://github.com/bottrall/riffer-rig/commit/00edaa3bbf35a7d797ca3596820d11bd8c62789a))

## [0.2.0](https://github.com/bottrall/riffer-rig/compare/v0.1.2...v0.2.0) (2026-09-08)


### ⚠ BREAKING CHANGES

* remove the Riffy mascot entirely ([#151](https://github.com/bottrall/riffer-rig/issues/151))

### Features

* remove the Riffy mascot entirely ([#151](https://github.com/bottrall/riffer-rig/issues/151)) ([af17f99](https://github.com/bottrall/riffer-rig/commit/af17f9907e8d43a01f966e1a0979f868a8d50466))
* **ui:** keep the thinking indicator alive during reasoning ([#156](https://github.com/bottrall/riffer-rig/issues/156)) ([4ff67cc](https://github.com/bottrall/riffer-rig/commit/4ff67cc6a2e133324b98dbdf40f63c500ee00a4c))
* **ui:** smooth streamed text output at 60fps ([#153](https://github.com/bottrall/riffer-rig/issues/153)) ([42dc781](https://github.com/bottrall/riffer-rig/commit/42dc781b3fc4a942e0eaca755b9e0b4180659506))


### Bug Fixes

* **ui:** drop 'code' subtitle from banner ([#157](https://github.com/bottrall/riffer-rig/issues/157)) ([dfd2e73](https://github.com/bottrall/riffer-rig/commit/dfd2e73d6b71f10adbf1dfa2ae659aad85ed547e))

## [0.1.2](https://github.com/bottrall/riffer-rig/compare/v0.1.1...v0.1.2) (2026-09-07)


### Bug Fixes

* **ci:** build and push the gem directly instead of rake release ([#148](https://github.com/bottrall/riffer-rig/issues/148)) ([7410915](https://github.com/bottrall/riffer-rig/commit/74109151a8275561dc1fac3bd6ec5b997a08e004))

## [0.1.1](https://github.com/bottrall/riffer-rig/compare/v0.1.0...v0.1.1) (2026-09-07)


### Bug Fixes

* ship the openai SDK so OpenAI and OpenRouter models work ([#145](https://github.com/bottrall/riffer-rig/issues/145)) ([92aba9b](https://github.com/bottrall/riffer-rig/commit/92aba9bb3b8fe097e90bb9375465636fac37afef))

## 0.1.0 (2026-09-05)


### ⚠ BREAKING CHANGES

* the gem, executable, namespace, config directory and environment variable are all renamed; nothing reads the old names.

### Features

* add prompt caching, token tally, and settings ([#7](https://github.com/bottrall/riffer-rig/issues/7)) ([bb02a95](https://github.com/bottrall/riffer-rig/commit/bb02a954c2fffa13ad8e564513c82681ab02d1e4))
* add skills support to CLI, REPL, and banner ([#5](https://github.com/bottrall/riffer-rig/issues/5)) ([5ac1dd1](https://github.com/bottrall/riffer-rig/commit/5ac1dd186c3f05adb342e1dead6102f2544d3b2b))
* configurable reasoning levels ([#34](https://github.com/bottrall/riffer-rig/issues/34)) ([a9604f3](https://github.com/bottrall/riffer-rig/commit/a9604f3994fc2cef5888c653fd1f07b82ac662f8))
* multi-provider support (Anthropic, OpenAI, Gemini, OpenRouter) ([#32](https://github.com/bottrall/riffer-rig/issues/32)) ([30b5ccf](https://github.com/bottrall/riffer-rig/commit/30b5ccf92ea43182953f1b5da089fe9e4550c9c9))
* rename to riffer-rig ([#95](https://github.com/bottrall/riffer-rig/issues/95)) ([d036d57](https://github.com/bottrall/riffer-rig/commit/d036d57f6fd48c3171383708caa0f22a34f7343d))


### Bug Fixes

* point riffer dependency to janeapp/riffer ([#2](https://github.com/bottrall/riffer-rig/issues/2)) ([0060283](https://github.com/bottrall/riffer-rig/commit/00602835baf9759d4a012b4506605f2b6ed7c250))
* rename Riffer::Boolean to Riffer::Params::Boolean ([#3](https://github.com/bottrall/riffer-rig/issues/3)) ([8996d01](https://github.com/bottrall/riffer-rig/commit/8996d0114a69b4db212cc9b0cbd2ec796f35a779))
* require /skill: prefix to activate skills ([#37](https://github.com/bottrall/riffer-rig/issues/37)) ([ac6313d](https://github.com/bottrall/riffer-rig/commit/ac6313d7622e3483271cacef8b7bfe60ed33503a))
