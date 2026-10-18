# Changelog

## [0.15.0](https://github.com/bottrall/riffer-rig/compare/v0.14.0...v0.15.0) (2026-10-18)


### Features

* **terminal:** style the turn report like the status bar ([#562](https://github.com/bottrall/riffer-rig/issues/562)) ([710bd34](https://github.com/bottrall/riffer-rig/commit/710bd34b993d2743a78935ebbf3116d50cc063d7))


### Bug Fixes

* label the status-bar step counter as steps, not turns ([#560](https://github.com/bottrall/riffer-rig/issues/560)) ([80e6b2b](https://github.com/bottrall/riffer-rig/commit/80e6b2b60756ba4896878ef7df736511a3ec2ed0))

## [0.14.0](https://github.com/bottrall/riffer-rig/compare/v0.13.0...v0.14.0) (2026-10-18)


### Features

* **headless:** print the session id on stderr ([#556](https://github.com/bottrall/riffer-rig/issues/556)) ([2816938](https://github.com/bottrall/riffer-rig/commit/2816938f66d32ccf557d83a33e40300e68a68032))
* make reasoning effort configurable like the model ([#553](https://github.com/bottrall/riffer-rig/issues/553)) ([330f190](https://github.com/bottrall/riffer-rig/commit/330f190244353ed5e967b0f29d574c2741d92dba))
* **terminal:** keep the status bar filled between turns ([#555](https://github.com/bottrall/riffer-rig/issues/555)) ([e0918ec](https://github.com/bottrall/riffer-rig/commit/e0918ecd050519cf06d0593221b3b50e0e1a6778))
* **terminal:** type a multiline prompt ([#557](https://github.com/bottrall/riffer-rig/issues/557)) ([a55091c](https://github.com/bottrall/riffer-rig/commit/a55091c091e4df4ad6c63a71d7dd16d1de98e835))
* upgrade riffer to 0.53.0 and adopt the model catalog ([#552](https://github.com/bottrall/riffer-rig/issues/552)) ([70b129b](https://github.com/bottrall/riffer-rig/commit/70b129b27a4d03188ef7831937874d7bb73cea08))


### Bug Fixes

* stop models from polling background bash jobs ([#559](https://github.com/bottrall/riffer-rig/issues/559)) ([57ad0ba](https://github.com/bottrall/riffer-rig/commit/57ad0ba259d0ebd71f4cc4178172364f39a62782))
* **terminal:** draw the banner and the input row together ([#549](https://github.com/bottrall/riffer-rig/issues/549)) ([e847277](https://github.com/bottrall/riffer-rig/commit/e847277af41ebd824dd115105d7d40e9af236da4))

## [0.13.0](https://github.com/bottrall/riffer-rig/compare/v0.12.0...v0.13.0) (2026-10-17)


### ⚠ BREAKING CHANGES

* Riffer::Rig::Loader takes its per-build choices as a Riffer::Rig::Loader::Options instead of keywords. Loader.runtime no longer accepts model:, extensions:, skills:, agents_md:, tools: or max_steps: (ArgumentError: unknown keywords); pass options: Riffer::Rig::Loader::Options.new(model: ..., skills: false). On a Loader instance the Options is the optional first positional argument: runtime(options), continue(options) and resume(id, options). Loader#tracked_files is removed with no replacement.

### Features

* **acp:** add adopt: hook and yield the connection from run ([#336](https://github.com/bottrall/riffer-rig/issues/336)) ([612a9c4](https://github.com/bottrall/riffer-rig/commit/612a9c4710f41ab19140d91112887e833c40ce4d)), closes [#302](https://github.com/bottrall/riffer-rig/issues/302)
* **acp:** announce background job exits between prompts ([#437](https://github.com/bottrall/riffer-rig/issues/437)) ([cd40e5b](https://github.com/bottrall/riffer-rig/commit/cd40e5b1778a72595b4c2f4a376544052c5c1a3d)), closes [#334](https://github.com/bottrall/riffer-rig/issues/334)
* **acp:** relay host questions to the client ([#337](https://github.com/bottrall/riffer-rig/issues/337)) ([e4fe093](https://github.com/bottrall/riffer-rig/commit/e4fe093505c74f89b7a8fc93680425b95c59e663))
* carry the tool lifecycle on before/after_tool_call events ([#321](https://github.com/bottrall/riffer-rig/issues/321)) ([c3967e2](https://github.com/bottrall/riffer-rig/commit/c3967e224b2d7427f6fd54e028b47f9644e24375))
* **commands:** add /cost runtime command ([#431](https://github.com/bottrall/riffer-rig/issues/431)) ([f7f36e8](https://github.com/bottrall/riffer-rig/commit/f7f36e8e91038952ca3a6762d792e0aea8ed67e6)), closes [#260](https://github.com/bottrall/riffer-rig/issues/260)
* **commands:** add /trace runtime command ([#373](https://github.com/bottrall/riffer-rig/issues/373)) ([95fc4cc](https://github.com/bottrall/riffer-rig/commit/95fc4cca0ab07cc7d1d39d726875e21eaa184fbb)), closes [#250](https://github.com/bottrall/riffer-rig/issues/250)
* **deps:** upgrade riffer to 0.51.0 ([#306](https://github.com/bottrall/riffer-rig/issues/306)) ([255c3d7](https://github.com/bottrall/riffer-rig/commit/255c3d7474baf3e669b5b093eb492984e3235cbd))
* **deps:** upgrade riffer to 0.52.1 ([#418](https://github.com/bottrall/riffer-rig/issues/418)) ([7b9c085](https://github.com/bottrall/riffer-rig/commit/7b9c085de9c3ea5d7fc6a5b3c3d4c9b3b6e1825b))
* **headless:** wait for background jobs at exit ([#438](https://github.com/bottrall/riffer-rig/issues/438)) ([91c7f9f](https://github.com/bottrall/riffer-rig/commit/91c7f9fc09fa6ea0a95c3e0221978979a1ff90f1)), closes [#331](https://github.com/bottrall/riffer-rig/issues/331)
* **runtime:** deliver background job exits to the model ([#434](https://github.com/bottrall/riffer-rig/issues/434)) ([e3f87b3](https://github.com/bottrall/riffer-rig/commit/e3f87b3a8d8efbe9a1f380b161b80f00bb89da00))
* **runtime:** keep background jobs running through a cancel ([#436](https://github.com/bottrall/riffer-rig/issues/436)) ([699ebbc](https://github.com/bottrall/riffer-rig/commit/699ebbc9055f11b95e7446a94ed33895387d8661)), closes [#333](https://github.com/bottrall/riffer-rig/issues/333)
* **stores:** stamp session entries with recorded_at ([#316](https://github.com/bottrall/riffer-rig/issues/316)) ([44dd322](https://github.com/bottrall/riffer-rig/commit/44dd3221b6a6c34528fb17772f15b2449a4ebdfc))
* **terminal:** add a /help command that lists the session's commands ([#547](https://github.com/bottrall/riffer-rig/issues/547)) ([81acfcf](https://github.com/bottrall/riffer-rig/commit/81acfcf7946033ecc0bebcf886db32b5b2a81e72)), closes [#545](https://github.com/bottrall/riffer-rig/issues/545)
* **terminal:** add the message queue and its footer chip ([#410](https://github.com/bottrall/riffer-rig/issues/410)) ([9a4c41a](https://github.com/bottrall/riffer-rig/commit/9a4c41a630fdabf4edaf90434ed4cc1c441ecbbb)), closes [#243](https://github.com/bottrall/riffer-rig/issues/243)
* **terminal:** make the ticker UI the default and document it ([#435](https://github.com/bottrall/riffer-rig/issues/435)) ([3400949](https://github.com/bottrall/riffer-rig/commit/34009492060bec9f36be554ffcebac770b247d4a)), closes [#265](https://github.com/bottrall/riffer-rig/issues/265)
* **terminal:** replay prior turns on resume ([#432](https://github.com/bottrall/riffer-rig/issues/432)) ([7652083](https://github.com/bottrall/riffer-rig/commit/765208399a1c3a69791ba85bb9a97dc2914206ed)), closes [#262](https://github.com/bottrall/riffer-rig/issues/262)
* **terminal:** run the REPL as a queue-draining loop ([#429](https://github.com/bottrall/riffer-rig/issues/429)) ([0213860](https://github.com/bottrall/riffer-rig/commit/021386049d753b48226cc6dbb8a63312d03dacdf))
* **terminal:** show session totals in the banner and redraw on /model ([#317](https://github.com/bottrall/riffer-rig/issues/317)) ([69232fd](https://github.com/bottrall/riffer-rig/commit/69232fde93179869cce86b66bcc6aa0da9dfa731)), closes [#264](https://github.com/bottrall/riffer-rig/issues/264)
* **terminal:** show turns through the ticker and delete the old renderer ([#433](https://github.com/bottrall/riffer-rig/issues/433)) ([4ec3388](https://github.com/bottrall/riffer-rig/commit/4ec3388df41a01d34b9fa9686df7f63ba0b42062))
* **terminal:** start a turn when a background job exits at an idle prompt ([#439](https://github.com/bottrall/riffer-rig/issues/439)) ([0d5198a](https://github.com/bottrall/riffer-rig/commit/0d5198af9b1c65c06277b0201fc48355283bce7e)), closes [#332](https://github.com/bottrall/riffer-rig/issues/332)
* **terminal:** wire slash autocomplete into the REPL ([#495](https://github.com/bottrall/riffer-rig/issues/495)) ([af936d9](https://github.com/bottrall/riffer-rig/commit/af936d96e786ad9e76e1283763b17dfac3c4daba))
* **tools:** add bash_output and bash_kill for background jobs ([#409](https://github.com/bottrall/riffer-rig/issues/409)) ([88fc7a9](https://github.com/bottrall/riffer-rig/commit/88fc7a9ad321dc443f57dbb3455c599a7db5e5e0)), closes [#329](https://github.com/bottrall/riffer-rig/issues/329)
* **tools:** job registry for background bash jobs ([#305](https://github.com/bottrall/riffer-rig/issues/305)) ([54f7df1](https://github.com/bottrall/riffer-rig/commit/54f7df15d140b499ec9c3e3b612c6d71df201563)), closes [#276](https://github.com/bottrall/riffer-rig/issues/276)
* watch background jobs and route their exits through the Runtime ([#376](https://github.com/bottrall/riffer-rig/issues/376)) ([32a3be2](https://github.com/bottrall/riffer-rig/commit/32a3be20edb330f528318e07a6aaf10e5019e0e2)), closes [#328](https://github.com/bottrall/riffer-rig/issues/328)


### Bug Fixes

* acp banner, close TODO, settings key types ([#304](https://github.com/bottrall/riffer-rig/issues/304)) ([baa6597](https://github.com/bottrall/riffer-rig/commit/baa659764ea1293792a0ee1dd8f40e289ed807bc))
* **acp:** announce the tool call of a relayed question ([#511](https://github.com/bottrall/riffer-rig/issues/511)) ([b20f0ee](https://github.com/bottrall/riffer-rig/commit/b20f0ee38ac722f7804dc15555cc00971ecde457)), closes [#472](https://github.com/bottrall/riffer-rig/issues/472)
* **acp:** answer a failed prompt with the provider's message ([#526](https://github.com/bottrall/riffer-rig/issues/526)) ([976c670](https://github.com/bottrall/riffer-rig/commit/976c670b6d5db43d50b969cc951e56c068c0fc58)), closes [#519](https://github.com/bottrall/riffer-rig/issues/519)
* **acp:** answer a prompt on a busy session with invalid request ([#508](https://github.com/bottrall/riffer-rig/issues/508)) ([3a50652](https://github.com/bottrall/riffer-rig/commit/3a50652a23a98b48675ae5e46df7ba1cc5b98c01)), closes [#473](https://github.com/bottrall/riffer-rig/issues/473)
* **acp:** close the tool call of a relayed question ([#404](https://github.com/bottrall/riffer-rig/issues/404)) ([2dc638c](https://github.com/bottrall/riffer-rig/commit/2dc638cc5a7a275e5d0f968b9e83530aa97967e4)), closes [#395](https://github.com/bottrall/riffer-rig/issues/395)
* **acp:** declare the client's MCP servers on session/load ([#374](https://github.com/bottrall/riffer-rig/issues/374)) ([06e07bd](https://github.com/bottrall/riffer-rig/commit/06e07bdea43cdf74be02fe6342b06e344aa75d0e)), closes [#343](https://github.com/bottrall/riffer-rig/issues/343)
* **acp:** decline build-time questions while session/load builds ([#405](https://github.com/bottrall/riffer-rig/issues/405)) ([98cf668](https://github.com/bottrall/riffer-rig/commit/98cf668041eb6b239d9bc8fa3e47288f7469dcf7)), closes [#394](https://github.com/bottrall/riffer-rig/issues/394)
* **acp:** re-send the command list after a reload changes it ([#535](https://github.com/bottrall/riffer-rig/issues/535)) ([a904bc7](https://github.com/bottrall/riffer-rig/commit/a904bc7cdba4a39506196980ac0333ec2df7a89f)), closes [#521](https://github.com/bottrall/riffer-rig/issues/521)
* **acp:** run slash commands instead of sending them to the model ([#494](https://github.com/bottrall/riffer-rig/issues/494)) ([3924ce5](https://github.com/bottrall/riffer-rig/commit/3924ce52b39e0ae3ef4d409200ce00ca464d38e3)), closes [#444](https://github.com/bottrall/riffer-rig/issues/444)
* **acp:** send available_commands_update on session/load ([#403](https://github.com/bottrall/riffer-rig/issues/403)) ([3659b0a](https://github.com/bottrall/riffer-rig/commit/3659b0a9b7129e7c1664f6158f6b51a46a9d95d4)), closes [#383](https://github.com/bottrall/riffer-rig/issues/383)
* **acp:** send each notice as a paragraph of its own ([#527](https://github.com/bottrall/riffer-rig/issues/527)) ([e665309](https://github.com/bottrall/riffer-rig/commit/e665309ad401330c9abc511e2645054a274838e2)), closes [#520](https://github.com/bottrall/riffer-rig/issues/520)
* **acp:** skip blank assistant messages when replaying a loaded session ([#509](https://github.com/bottrall/riffer-rig/issues/509)) ([85f0aa3](https://github.com/bottrall/riffer-rig/commit/85f0aa3582c893d2eb5ef58dbb9103cdd89f7568)), closes [#471](https://github.com/bottrall/riffer-rig/issues/471)
* **cli:** answer --version and -v with the riffer-rig version ([#399](https://github.com/bottrall/riffer-rig/issues/399)) ([08ad995](https://github.com/bottrall/riffer-rig/commit/08ad995ba8570a2aced722fa1305c025939d5ee4)), closes [#380](https://github.com/bottrall/riffer-rig/issues/380)
* **cli:** open the picker for a bare -r followed by another flag ([#370](https://github.com/bottrall/riffer-rig/issues/370)) ([e01bd20](https://github.com/bottrall/riffer-rig/commit/e01bd20d8c599d208c0e2541e34d7575df9d7e83)), closes [#342](https://github.com/bottrall/riffer-rig/issues/342)
* **cli:** recognise clustered short flags such as -pc as headless ([#406](https://github.com/bottrall/riffer-rig/issues/406)) ([2e28f63](https://github.com/bottrall/riffer-rig/commit/2e28f630601ac774652467ca0d1efbbaa5208428)), closes [#384](https://github.com/bottrall/riffer-rig/issues/384)
* **cli:** reject --max-steps values below 1 ([#499](https://github.com/bottrall/riffer-rig/issues/499)) ([e0e33ad](https://github.com/bottrall/riffer-rig/commit/e0e33ad13e3d04d4f555f0e455997f7d6a5938da)), closes [#467](https://github.com/bottrall/riffer-rig/issues/467)
* **commands:** confirm the save in /model --save ([#500](https://github.com/bottrall/riffer-rig/issues/500)) ([7c0035b](https://github.com/bottrall/riffer-rig/commit/7c0035b1b6780955f8f8508d6cda3459ab4721eb)), closes [#464](https://github.com/bottrall/riffer-rig/issues/464)
* **credentials:** never overwrite a malformed auth, settings or trust file ([#415](https://github.com/bottrall/riffer-rig/issues/415)) ([c8d66aa](https://github.com/bottrall/riffer-rig/commit/c8d66aa6babdf791ce9e3a47bdbdd168454dffd0)), closes [#381](https://github.com/bottrall/riffer-rig/issues/381)
* **credentials:** preserve unrecognised auth.json entries on store and remove ([#365](https://github.com/bottrall/riffer-rig/issues/365)) ([a7d26e7](https://github.com/bottrall/riffer-rig/commit/a7d26e799d64099a711a771b30e42bdf4a8c86c8)), closes [#344](https://github.com/bottrall/riffer-rig/issues/344)
* **credentials:** tighten an existing auth.json to 0600 on rewrite ([#400](https://github.com/bottrall/riffer-rig/issues/400)) ([59765c8](https://github.com/bottrall/riffer-rig/commit/59765c822cbae0b168c7ba63e440b2dfdc6f4529)), closes [#382](https://github.com/bottrall/riffer-rig/issues/382)
* **deps:** pin acp-sdk to one minor ([#397](https://github.com/bottrall/riffer-rig/issues/397)) ([7bcad06](https://github.com/bottrall/riffer-rig/commit/7bcad0649686e052afe5e5fc371212800d493237))
* **deps:** upgrade acp-sdk to 0.11.0 ([#338](https://github.com/bottrall/riffer-rig/issues/338)) ([8e61f4a](https://github.com/bottrall/riffer-rig/commit/8e61f4a887ded320cf668300629f210bb02c91f9))
* **deps:** upgrade acp-sdk to 0.13.0 ([#424](https://github.com/bottrall/riffer-rig/issues/424)) ([ba080c1](https://github.com/bottrall/riffer-rig/commit/ba080c1621cff5d3ea77e73863558e6778ff6445))
* **headless:** print the --verbose tool trace in --json mode ([#501](https://github.com/bottrall/riffer-rig/issues/501)) ([4fba2a0](https://github.com/bottrall/riffer-rig/commit/4fba2a060bd07e1745d46f41bf6b655a553f8d5a)), closes [#468](https://github.com/bottrall/riffer-rig/issues/468)
* **headless:** refuse a whitespace-only prompt ([#498](https://github.com/bottrall/riffer-rig/issues/498)) ([633d099](https://github.com/bottrall/riffer-rig/commit/633d099cdaf473a963e20d4b11140749580afe64)), closes [#465](https://github.com/bottrall/riffer-rig/issues/465)
* **headless:** replace invalid UTF-8 in piped stdin ([#482](https://github.com/bottrall/riffer-rig/issues/482)) ([1e726f4](https://github.com/bottrall/riffer-rig/commit/1e726f4650ea3a968e466aee7480ee57caf86580)), closes [#451](https://github.com/bottrall/riffer-rig/issues/451)
* **headless:** report a missing session before the missing prompt ([#507](https://github.com/bottrall/riffer-rig/issues/507)) ([60ad490](https://github.com/bottrall/riffer-rig/commit/60ad49009836e7706a0429927d8f0ad2630ec7ac))
* **headless:** separate follow-up answers with a blank line in text mode ([#505](https://github.com/bottrall/riffer-rig/issues/505)) ([4c74399](https://github.com/bottrall/riffer-rig/commit/4c7439915932155c50378769b5d40f01eba29dc9)), closes [#469](https://github.com/bottrall/riffer-rig/issues/469)
* **headless:** serialise non-pair Enumerables in Ndjson as arrays ([#357](https://github.com/bottrall/riffer-rig/issues/357)) ([0b5e16a](https://github.com/bottrall/riffer-rig/commit/0b5e16a6339b42d87504bfd85e21f501aeaad9e6)), closes [#348](https://github.com/bottrall/riffer-rig/issues/348)
* **headless:** stop waiting on a silent stdin when -p has a prompt argument ([#541](https://github.com/bottrall/riffer-rig/issues/541)) ([32d0ca9](https://github.com/bottrall/riffer-rig/commit/32d0ca9cbccf089461030de33f8f4475f1b2fb47)), closes [#529](https://github.com/bottrall/riffer-rig/issues/529)
* **headless:** stream stdout to pipes and files as it is written ([#484](https://github.com/bottrall/riffer-rig/issues/484)) ([3fbc295](https://github.com/bottrall/riffer-rig/commit/3fbc295ebef30269546ec87c3af0fb4a8a6d6fe1)), closes [#452](https://github.com/bottrall/riffer-rig/issues/452)
* **loader:** ask again about a trust question left unanswered ([#522](https://github.com/bottrall/riffer-rig/issues/522)) ([c5e8dae](https://github.com/bottrall/riffer-rig/commit/c5e8dae6891cd1388dc71ef8c3d38e5e55021c7f)), closes [#517](https://github.com/bottrall/riffer-rig/issues/517)
* **mcp:** preserve stdio fields in Declaration#with_headers ([#310](https://github.com/bottrall/riffer-rig/issues/310)) ([90b6f8e](https://github.com/bottrall/riffer-rig/commit/90b6f8e2b87b68b726eec599e5d6c905801681ff)), closes [#307](https://github.com/bottrall/riffer-rig/issues/307)
* route missing-session wording through the sessions collaborator ([#298](https://github.com/bottrall/riffer-rig/issues/298)) ([a22e2bd](https://github.com/bottrall/riffer-rig/commit/a22e2bd483c44a6ec345f50f0a15a8a84c4c9b66)), closes [#283](https://github.com/bottrall/riffer-rig/issues/283)
* **runtime:** keep a resumed session's first user message ([#478](https://github.com/bottrall/riffer-rig/issues/478)) ([3a1e7e5](https://github.com/bottrall/riffer-rig/commit/3a1e7e5523ffc5cc060bc57eeeb70a46cc3467cd)), closes [#441](https://github.com/bottrall/riffer-rig/issues/441)
* **runtime:** show the provider's response body message on HTTP errors ([#491](https://github.com/bottrall/riffer-rig/issues/491)) ([4e93ec4](https://github.com/bottrall/riffer-rig/commit/4e93ec486820f8a49b8d6a00a7838ff9e0f90561))
* **runtime:** warn about tool allowlist names no extension registered ([#485](https://github.com/bottrall/riffer-rig/issues/485)) ([da61612](https://github.com/bottrall/riffer-rig/commit/da6161282e965dac648c6b4b213c9441d8385b79)), closes [#453](https://github.com/bottrall/riffer-rig/issues/453)
* **sdk:** return a message when the gem install fails ([#369](https://github.com/bottrall/riffer-rig/issues/369)) ([1cf5557](https://github.com/bottrall/riffer-rig/commit/1cf55574568868fa162200d84b74eb34f73cd9c2)), closes [#351](https://github.com/bottrall/riffer-rig/issues/351)
* **sessions:** let --model win over a resumed session's /model switch ([#537](https://github.com/bottrall/riffer-rig/issues/537)) ([8233c13](https://github.com/bottrall/riffer-rig/commit/8233c13f75cbb883577c0bc00a40e80b6d9507b4)), closes [#528](https://github.com/bottrall/riffer-rig/issues/528)
* **sessions:** resume a session in the directory it was saved in ([#544](https://github.com/bottrall/riffer-rig/issues/544)) ([6cd8df2](https://github.com/bottrall/riffer-rig/commit/6cd8df2c80947920d5ea479a4bd5cd1b0b19a892)), closes [#530](https://github.com/bottrall/riffer-rig/issues/530)
* **settings:** report a non-string model as a settings error ([#510](https://github.com/bottrall/riffer-rig/issues/510)) ([5fde7c2](https://github.com/bottrall/riffer-rig/commit/5fde7c2a0687a99fa3a83c96c0bfc016329f82e7)), closes [#470](https://github.com/bottrall/riffer-rig/issues/470)
* single credentials install flow, fixing the /auth partial-apply ([#295](https://github.com/bottrall/riffer-rig/issues/295)) ([d6626d8](https://github.com/bottrall/riffer-rig/commit/d6626d8b8f46c78f2c9a7b3a50f4d730c4d63a71))
* **stores:** keep recording skill activations after a reload ([#371](https://github.com/bottrall/riffer-rig/issues/371)) ([d81abb2](https://github.com/bottrall/riffer-rig/commit/d81abb2a33efba05bf0264ea5708808b95a4e352)), closes [#327](https://github.com/bottrall/riffer-rig/issues/327)
* **stores:** skip non-object JSON lines in Stores::JSONL ([#361](https://github.com/bottrall/riffer-rig/issues/361)) ([14f9d3a](https://github.com/bottrall/riffer-rig/commit/14f9d3afe2dd46aceb33c5d2ffaa59e773e944ec)), closes [#346](https://github.com/bottrall/riffer-rig/issues/346)
* **terminal:** announce the exits a follow-up turn actually delivers ([#542](https://github.com/bottrall/riffer-rig/issues/542)) ([f04e762](https://github.com/bottrall/riffer-rig/commit/f04e762922eef0c015ffef25e84b474897973367)), closes [#532](https://github.com/bottrall/riffer-rig/issues/532)
* **terminal:** cancel a credential question on Ctrl-C ([#490](https://github.com/bottrall/riffer-rig/issues/490)) ([37579b6](https://github.com/bottrall/riffer-rig/commit/37579b61f448d0015ff7947f81e10e5fbb7c03ab))
* **terminal:** close the session /new or /resume swapped in at exit ([#480](https://github.com/bottrall/riffer-rig/issues/480)) ([dd3de41](https://github.com/bottrall/riffer-rig/commit/dd3de41d87cda9a5b5e39b4693eb927a5a0da9bc)), closes [#442](https://github.com/bottrall/riffer-rig/issues/442)
* **terminal:** confirm /model in one line instead of the banner ([#401](https://github.com/bottrall/riffer-rig/issues/401)) ([083a2c0](https://github.com/bottrall/riffer-rig/commit/083a2c076a9c6d2b2dc028a26f68200b5ea8cf95)), closes [#378](https://github.com/bottrall/riffer-rig/issues/378)
* **terminal:** fit the banner to narrow terminals ([#513](https://github.com/bottrall/riffer-rig/issues/513)) ([9a19efa](https://github.com/bottrall/riffer-rig/commit/9a19efaf437c633f89600c9d7b3be18d83eacedb)), closes [#474](https://github.com/bottrall/riffer-rig/issues/474)
* **terminal:** handle Ctrl-C at idle when SIGINT is inherited as ignored ([#512](https://github.com/bottrall/riffer-rig/issues/512)) ([73d51e7](https://github.com/bottrall/riffer-rig/commit/73d51e7396bf3b9b37a6230fe056501eb85d3852)), closes [#476](https://github.com/bottrall/riffer-rig/issues/476)
* **terminal:** indent and wrap command output like the turn report ([#497](https://github.com/bottrall/riffer-rig/issues/497)) ([2aadbd0](https://github.com/bottrall/riffer-rig/commit/2aadbd049a96de45e1b11e323e8c89c069eb9a30)), closes [#458](https://github.com/bottrall/riffer-rig/issues/458)
* **terminal:** interrupt a streaming reply on Ctrl-C ([#416](https://github.com/bottrall/riffer-rig/issues/416)) ([0f123dc](https://github.com/bottrall/riffer-rig/commit/0f123dc01fa2f30ceab3cdd45c08e77a73845efe))
* **terminal:** keep a blank row between output and the input row ([#534](https://github.com/bottrall/riffer-rig/issues/534)) ([01070f4](https://github.com/bottrall/riffer-rig/commit/01070f40e7b6b6ba0d3a8671d3d6c37bd55ba68f)), closes [#515](https://github.com/bottrall/riffer-rig/issues/515)
* **terminal:** keep a pasted prompt's line breaks in its echo ([#536](https://github.com/bottrall/riffer-rig/issues/536)) ([73b73ec](https://github.com/bottrall/riffer-rig/commit/73b73ecfb4cd59b8eacb8bc43b38048d17349685)), closes [#525](https://github.com/bottrall/riffer-rig/issues/525)
* **terminal:** keep a whitespace-only line as a paragraph break ([#366](https://github.com/bottrall/riffer-rig/issues/366)) ([3a402c8](https://github.com/bottrall/riffer-rig/commit/3a402c85b64b61f508a7990b36b032d9276ab6e4)), closes [#341](https://github.com/bottrall/riffer-rig/issues/341)
* **terminal:** keep the columns of a /trace line that wraps ([#538](https://github.com/bottrall/riffer-rig/issues/538)) ([d24cfc5](https://github.com/bottrall/riffer-rig/commit/d24cfc501cecfd7e3129d12b72487bc467af640a)), closes [#524](https://github.com/bottrall/riffer-rig/issues/524)
* **terminal:** keep the key reader alive on non-UTF-8 input ([#496](https://github.com/bottrall/riffer-rig/issues/496)) ([f7382c6](https://github.com/bottrall/riffer-rig/commit/f7382c6d4b55fad766285c2c1e6a910ae9f5f291)), closes [#443](https://github.com/bottrall/riffer-rig/issues/443)
* **terminal:** make the key pipeline restartable and end-of-input aware ([#408](https://github.com/bottrall/riffer-rig/issues/408)) ([c2b4787](https://github.com/bottrall/riffer-rig/commit/c2b4787c35e0e86a1b196b4538d52d8eafe045bd)), closes [#396](https://github.com/bottrall/riffer-rig/issues/396)
* **terminal:** print the missing-session notice below the banner ([#514](https://github.com/bottrall/riffer-rig/issues/514)) ([2b3a296](https://github.com/bottrall/riffer-rig/commit/2b3a29687a099bfa3eee0d9a4bd767dee6621ea3)), closes [#475](https://github.com/bottrall/riffer-rig/issues/475)
* **terminal:** render a paragraph's single newlines as line breaks ([#479](https://github.com/bottrall/riffer-rig/issues/479)) ([fa9d08f](https://github.com/bottrall/riffer-rig/commit/fa9d08f9122952a5c7af1c6876ccdfdb21c7550f)), closes [#450](https://github.com/bottrall/riffer-rig/issues/450)
* **terminal:** render non-object tool-call arguments verbatim ([#359](https://github.com/bottrall/riffer-rig/issues/359)) ([956ae23](https://github.com/bottrall/riffer-rig/commit/956ae2385b42012b1832fc58a7765de570dc4846)), closes [#347](https://github.com/bottrall/riffer-rig/issues/347)
* **terminal:** replay a job-exit turn on its own when resuming ([#493](https://github.com/bottrall/riffer-rig/issues/493)) ([24c84c2](https://github.com/bottrall/riffer-rig/commit/24c84c29b884b4bcb5818a61fa903a6c8251f5a4))
* **terminal:** report a bare / instead of sending it to the model ([#504](https://github.com/bottrall/riffer-rig/issues/504)) ([c66d2ae](https://github.com/bottrall/riffer-rig/commit/c66d2ae47a9477d1819b7aeb0f0ccf86fa2952fd)), closes [#460](https://github.com/bottrall/riffer-rig/issues/460)
* **terminal:** say sessions are off under --no-save instead of none saved ([#506](https://github.com/bottrall/riffer-rig/issues/506)) ([777aba0](https://github.com/bottrall/riffer-rig/commit/777aba0c4b368d6d95f26447b4871f01c2a82201)), closes [#463](https://github.com/bottrall/riffer-rig/issues/463)
* **terminal:** say when a picker filter matches no session ([#502](https://github.com/bottrall/riffer-rig/issues/502)) ([07b39bd](https://github.com/bottrall/riffer-rig/commit/07b39bdac94ec32731475ac22d844318178ddd3d)), closes [#462](https://github.com/bottrall/riffer-rig/issues/462)
* **terminal:** say when the /resume picker closes without a pick ([#503](https://github.com/bottrall/riffer-rig/issues/503)) ([327d34b](https://github.com/bottrall/riffer-rig/commit/327d34bc681e18a39bba4dc3e8565242e5a45ad8)), closes [#461](https://github.com/bottrall/riffer-rig/issues/461)
* **terminal:** show a static hint on the status line while a question waits ([#486](https://github.com/bottrall/riffer-rig/issues/486)) ([ee53ed5](https://github.com/bottrall/riffer-rig/commit/ee53ed5c61eaacf14acf57af7a66578f24ff797a)), closes [#457](https://github.com/bottrall/riffer-rig/issues/457)
* **terminal:** show every reply of a turn a job exit continued ([#543](https://github.com/bottrall/riffer-rig/issues/543)) ([763558d](https://github.com/bottrall/riffer-rig/commit/763558d845b9387cdd53e74f862991c602034b59)), closes [#531](https://github.com/bottrall/riffer-rig/issues/531)
* **terminal:** show the cursor while suspended with Ctrl-Z ([#414](https://github.com/bottrall/riffer-rig/issues/414)) ([fa6e7b4](https://github.com/bottrall/riffer-rig/commit/fa6e7b43e42405cb289e15741d7162880ea0583e))
* **terminal:** size a table by its header and keep pipes in code spans ([#489](https://github.com/bottrall/riffer-rig/issues/489)) ([324ba0e](https://github.com/bottrall/riffer-rig/commit/324ba0eead841027cafff9d60441de90500f4e25)), closes [#455](https://github.com/bottrall/riffer-rig/issues/455)
* **terminal:** stop Wrapper hanging when the width is at or below the indent ([#367](https://github.com/bottrall/riffer-rig/issues/367)) ([cbbca89](https://github.com/bottrall/riffer-rig/commit/cbbca899769a0782ad146e705f06a6055168daa4)), closes [#340](https://github.com/bottrall/riffer-rig/issues/340)
* **terminal:** treat 0 in the /resume picker as filter text ([#362](https://github.com/bottrall/riffer-rig/issues/362)) ([ae7516b](https://github.com/bottrall/riffer-rig/commit/ae7516bba9ea207337ef856d4132eaf8ee6095a4)), closes [#350](https://github.com/bottrall/riffer-rig/issues/350)
* **terminal:** word-wrap questions with a hanging indent ([#540](https://github.com/bottrall/riffer-rig/issues/540)) ([16fb443](https://github.com/bottrall/riffer-rig/commit/16fb443eb38e6428c313fb763dc7480f30cc56b3)), closes [#523](https://github.com/bottrall/riffer-rig/issues/523)
* **terminal:** word-wrap the echoed prompt with a hanging indent ([#483](https://github.com/bottrall/riffer-rig/issues/483)) ([3f357a1](https://github.com/bottrall/riffer-rig/commit/3f357a12c7af55a676dfc00af3ef4e9d593b9b15)), closes [#459](https://github.com/bottrall/riffer-rig/issues/459)
* **terminal:** wrap a table column at spaces before breaking a token ([#518](https://github.com/bottrall/riffer-rig/issues/518)) ([6208f11](https://github.com/bottrall/riffer-rig/commit/6208f1195a0bef97307984b35f923487bd865b9b)), closes [#516](https://github.com/bottrall/riffer-rig/issues/516)
* **terminal:** wrap markdown tables to the terminal width ([#492](https://github.com/bottrall/riffer-rig/issues/492)) ([3b998eb](https://github.com/bottrall/riffer-rig/commit/3b998eba84bf7b2311984c7d0b64c54ee2be3ded))
* **terminal:** wrap prose by display columns and keep its indentation ([#412](https://github.com/bottrall/riffer-rig/issues/412)) ([40f83ce](https://github.com/bottrall/riffer-rig/commit/40f83ce3b4cd7a00a05a8db0d2fc024b6927b024)), closes [#385](https://github.com/bottrall/riffer-rig/issues/385)
* **tools:** cap background job output and remove it on close ([#417](https://github.com/bottrall/riffer-rig/issues/417)) ([02a3c5e](https://github.com/bottrall/riffer-rig/commit/02a3c5ec00b8a0435ff70c7560e0ab652ec69cd7)), closes [#391](https://github.com/bottrall/riffer-rig/issues/391)
* **tools:** end a background job's process group after its leader exits ([#413](https://github.com/bottrall/riffer-rig/issues/413)) ([26de424](https://github.com/bottrall/riffer-rig/commit/26de424d91c7c73623386e9bbd348358536cfc71)), closes [#390](https://github.com/bottrall/riffer-rig/issues/390)
* **tools:** give background bash jobs an empty stdin ([#488](https://github.com/bottrall/riffer-rig/issues/488)) ([23a1a1c](https://github.com/bottrall/riffer-rig/commit/23a1a1c266f7a938c40c0b07c5a0838be6d24d79)), closes [#445](https://github.com/bottrall/riffer-rig/issues/445)
* **tools:** keep bash output valid UTF-8 and report sub-second timeouts ([#360](https://github.com/bottrall/riffer-rig/issues/360)) ([9d74845](https://github.com/bottrall/riffer-rig/commit/9d748453ecab23ac32995d0d26495cfe707ad6d9)), closes [#345](https://github.com/bottrall/riffer-rig/issues/345)
* **tools:** let bash_kill stop a stopped background job ([#487](https://github.com/bottrall/riffer-rig/issues/487)) ([2b5d13e](https://github.com/bottrall/riffer-rig/commit/2b5d13e3096b6a11ab59c5b0002e979f6abf0d21)), closes [#447](https://github.com/bottrall/riffer-rig/issues/447)
* **tools:** read bash output while the command runs ([#407](https://github.com/bottrall/riffer-rig/issues/407)) ([3a94502](https://github.com/bottrall/riffer-rig/commit/3a94502e5328c7b9edbf1ab5a64ac4386b075610)), closes [#379](https://github.com/bottrall/riffer-rig/issues/379)
* **tools:** replace invalid UTF-8 bytes in read output ([#481](https://github.com/bottrall/riffer-rig/issues/481)) ([8bc5c8b](https://github.com/bottrall/riffer-rig/commit/8bc5c8b1686ca4511ca595d535860c783eb170db)), closes [#446](https://github.com/bottrall/riffer-rig/issues/446)
* **tools:** report a background job ended by a signal as killed ([#539](https://github.com/bottrall/riffer-rig/issues/539)) ([db792ec](https://github.com/bottrall/riffer-rig/commit/db792ecde236947ba4681c8132e981def7e04fd0)), closes [#533](https://github.com/bottrall/riffer-rig/issues/533)
* **tools:** treat a missing background job output file as empty ([#402](https://github.com/bottrall/riffer-rig/issues/402)) ([8464463](https://github.com/bottrall/riffer-rig/commit/846446329657c644e6784c7e8d772ff6d3814047)), closes [#392](https://github.com/bottrall/riffer-rig/issues/392)


### Documentation

* describe the Loader::Options and Credentials.install APIs ([#411](https://github.com/bottrall/riffer-rig/issues/411)) ([a3bb5a4](https://github.com/bottrall/riffer-rig/commit/a3bb5a43d0418042919743c3765a99c034f73321)), closes [#387](https://github.com/bottrall/riffer-rig/issues/387)

## [0.12.0](https://github.com/bottrall/riffer-rig/compare/v0.11.0...v0.12.0) (2026-10-07)


### Features

* --json streams every Runtime event as NDJSON ([#231](https://github.com/bottrall/riffer-rig/issues/231)) ([a5e4641](https://github.com/bottrall/riffer-rig/commit/a5e464172cb84fcbfc2fbce0a311c070b54a539a))
* /resume picker and /new in the terminal ([#232](https://github.com/bottrall/riffer-rig/issues/232)) ([140fbac](https://github.com/bottrall/riffer-rig/commit/140fbac7c7fc966987ee77c78222204bb755e37f))
* ACP session/load and session/list ([#237](https://github.com/bottrall/riffer-rig/issues/237)) ([db81553](https://github.com/bottrall/riffer-rig/commit/db815536fa940d3f14615fa55b27af63164665ce))
* resolve secret MCP headers from env and auth.json ([#234](https://github.com/bottrall/riffer-rig/issues/234)) ([6253f95](https://github.com/bottrall/riffer-rig/commit/6253f95932b81e276cec0850f7aa48abdb332b63))
* riffer acp serves the Runtime over ACP ([#235](https://github.com/bottrall/riffer-rig/issues/235)) ([9497122](https://github.com/bottrall/riffer-rig/commit/9497122cc0cdac3576481f6efeda6e49f595d999))

## [0.11.0](https://github.com/bottrall/riffer-rig/compare/v0.10.0...v0.11.0) (2026-10-06)


### Features

* riffer -p runs one prompt headless with exit codes ([#226](https://github.com/bottrall/riffer-rig/issues/226)) ([eaa91d6](https://github.com/bottrall/riffer-rig/commit/eaa91d625eb303e4dc8a08c317ea38fc136a729d)), closes [#137](https://github.com/bottrall/riffer-rig/issues/137)
* store entries as typed POROs at the store boundary ([#225](https://github.com/bottrall/riffer-rig/issues/225)) ([05431e5](https://github.com/bottrall/riffer-rig/commit/05431e583c412ee7c3551dadd61db1089af465a9))

## [0.10.0](https://github.com/bottrall/riffer-rig/compare/v0.9.0...v0.10.0) (2026-10-05)


### Features

* continue and resume sessions with -c and -r ([#220](https://github.com/bottrall/riffer-rig/issues/220)) ([e43d3ac](https://github.com/bottrall/riffer-rig/commit/e43d3ac44678e56016791545ea241779569687c9))
* reload automatically before each request ([#222](https://github.com/bottrall/riffer-rig/issues/222)) ([fe96aa4](https://github.com/bottrall/riffer-rig/commit/fe96aa4476b0765e58824a8eb59301f0986e397c))

## [0.9.0](https://github.com/bottrall/riffer-rig/compare/v0.8.0...v0.9.0) (2026-10-04)


### ⚠ BREAKING CHANGES

* optional provider SDKs and the missing-SDK flow ([#211](https://github.com/bottrall/riffer-rig/issues/211))

### Features

* /auth lists, re-runs and removes provider credentials ([#213](https://github.com/bottrall/riffer-rig/issues/213)) ([ce17f15](https://github.com/bottrall/riffer-rig/commit/ce17f15286f5bc776775e1cbff4fb6db673379f7))
* /model --save and provider switching through the Loader ([#214](https://github.com/bottrall/riffer-rig/issues/214)) ([f033caa](https://github.com/bottrall/riffer-rig/commit/f033caa6fc4b02b8a4429174f7d5256e4e7ece5b))
* extension providers with a setup on the provider seam ([#216](https://github.com/bottrall/riffer-rig/issues/216)) ([f24f632](https://github.com/bottrall/riffer-rig/commit/f24f632f7f6a1a9903e1bdd0985076a1d03f12d3))
* JSONL session store appends every Loader-built Runtime ([#219](https://github.com/bottrall/riffer-rig/issues/219)) ([67c5e80](https://github.com/bottrall/riffer-rig/commit/67c5e80efcea07b421b2c8512e576593d7a826d3))
* optional provider SDKs and the missing-SDK flow ([#211](https://github.com/bottrall/riffer-rig/issues/211)) ([334c94b](https://github.com/bottrall/riffer-rig/commit/334c94bc4954f87846ead17a936690a40d847c75)), closes [#127](https://github.com/bottrall/riffer-rig/issues/127)
* provider-native tools switched on in settings ([#217](https://github.com/bottrall/riffer-rig/issues/217)) ([6ba2a6a](https://github.com/bottrall/riffer-rig/commit/6ba2a6ad7ca0885af3e5c853786a0f3e22e0373a))
* reload tracked files with /reload ([#218](https://github.com/bottrall/riffer-rig/issues/218)) ([403de96](https://github.com/bottrall/riffer-rig/commit/403de9645afd91082551a966d04cc18beeb8f194)), closes [#132](https://github.com/bottrall/riffer-rig/issues/132)


### Bug Fixes

* bundle provider SDKs for the checkout's bundler/setup ([#215](https://github.com/bottrall/riffer-rig/issues/215)) ([f0cc9e6](https://github.com/bottrall/riffer-rig/commit/f0cc9e6afcf82d1f006ab09679a4be38be846af2))

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
