# Changelog

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
