# Testing AWiki Me

AWiki Me keeps two active test domains plus Flutter tooling shims:

```text
tests/unit/         # fast unit, widget, provider, and pure Dart tests
tests/e2e/          # desktop user-flow runner plus Flutter platform shims/support
integration_test/   # Flutter tooling shims only; do not put test logic here
.e2e/               # local E2E reports/state; ignored by Git
```

Root files under `integration_test/` are Flutter-tooling shims. Each shim imports
the real implementation under `tests/e2e/flutter/`. Do not add durable test logic
to root shims.

## Choosing The Right Test

Use the smallest deterministic test that answers the question:

| Directory | Answers | Uses real backend/devices? | Put these tests here |
| --- | --- | --- | --- |
| `tests/unit/` | Does this Dart logic, mapper, provider, service, or widget state behave correctly? | No | Pure Dart unit tests, widget/provider tests, fake service-client tests, parser tests, E2E runner plan/redaction tests. |
| `tests/e2e/` | Does the user/business chain work through the App runner, platform shims, native plugin, CLI peer, backend, or devices? | Case-dependent | E2E runners, scenario orchestration, local/example configs, Flutter shim implementations, App + CLI peer/backend reports. |
| `integration_test/` | Can Flutter tooling discover and launch the test entrypoint? | No business ownership | Thin imports only. Keep orchestration in `tests/e2e/`. |

Do not use the root `integration_test/` directory as the owner of a real
multi-client backend scenario. If Flutter tooling requires a root entrypoint,
keep the scenario contract, config, runner, reports, and assertions under
`tests/e2e/`.

## Required Coverage

Every new feature or behavior change must ship with matching test coverage in
the same change:

1. Start with focused `tests/unit/` coverage for changed domain logic, data
   mapping, service-client behavior, provider state, or widget behavior.
2. Add or update `tests/e2e/` Flutter smoke coverage when App startup,
   navigation, platform bindings, native SDK/plugin loading, fake-port App
   bootstrap, or screenshot-visible UI surfaces change.
3. Add or update `tests/e2e/` runner assets when the behavior spans real
   non-production services, account/OTP flows, CLI peer behavior, multi-client
   messaging, attachments, group flows, mobile devices, Maestro, or report
   redaction.
4. If a full real E2E case is too expensive or blocked, keep deterministic
   unit/smoke coverage, record the skipped E2E case ID, owner, blocker, and
   follow-up in the relevant E2E docs or plan, and do not present the skipped
   case as passing evidence.

Code-only feature changes without corresponding tests are not acceptable unless
the exception and follow-up are explicitly documented.

## Unit Gate

Run the full local unit/widget/provider suite:

```bash
dart run tests/unit/runner.dart
```

Collect the reproducible line + branch baseline and enforce both the overall
floor and critical chat/conversation/relationship/read-sync file floors:

```bash
dart run tests/unit/runner.dart --branch-coverage
dart run tool/test_coverage_gate.dart
```

The checked-in policy is `tests/quality/coverage_baseline.json`. It was
established from 972 passing tests on 2026-07-10: overall line coverage
76.95% (23986/31171) and branch coverage 62.28% (6468/10385). Critical
baselines are intentionally per-file so a high aggregate cannot hide removed
dedupe, unread/read, relationship or sync branches. The CI unit invocation
collects this coverage once; it does not rerun the suite just to enforce the
policy.

The unit gate must stay deterministic and Mac-friendly. It must not require a
real backend, real OTP, real CLI peer, Hermes, daemon, or mobile device. Focused
Flutter arguments can be passed through when debugging:

```bash
dart run tests/unit/runner.dart --name mention
```

Focused UI checks are owned by the relevant files under `tests/unit/`, for
example:

```bash
dart run tests/unit/runner.dart tests/unit/agents/agents_page_layout_test.dart
dart run tests/unit/runner.dart tests/unit/agents/agent_inbox_provider_test.dart
dart run tests/unit/runner.dart tests/unit/conversation_workspace_test.dart
dart run tests/unit/runner.dart tests/unit/chat_page_test.dart
dart run tests/unit/runner.dart tests/unit/onboarding_page_test.dart
flutter test tests/unit/data/im_core/awiki_im_core_device_management_adapter_test.dart \
  tests/unit/devices/device_management_service_test.dart \
  tests/unit/devices/devices_ui_test.dart
```

`--case multi-device` 目前是可执行的本地 capability-gate E2E：它使用两个独立临时
Storage Scope、production `AppBootstrap` 和 native Core，验证默认关闭时不组合高风险
adapter/入口，以及只开启 Join 时公共 onboarding 入口只能打开真实 OTP 表单。它不发送
OTP，也不声称完成远端 Join、SAS、审批、根导入、撤销、MLS 或 Handle Recovery。

`DEVICE-JOIN-E2E-002` 已由独立的 `multi-device-remote-join` suite 承载；它不会混入
本地 capability gate。该 suite 使用真实 AWiki Me 管理设备和独立 CLI 请求设备、动态
一次性 OTP、双端 SAS、真实 macOS user-presence 与场景级 attestation。当
`awiki.info` 隐藏 rollout、专用账号 allowlist 或执行环境尚未全部就绪时，这个入口
不得声称远端通过。`DEVICE-JOIN-E2E-001/003`、`ROOT-TRANSFER-E2E-*`、
`MLS-MULTI-DEVICE-E2E-*` 和 `HANDLE-RECOVERY-E2E-*` 仍为 planned；不得把本地
capability gate、Widget fake 或手工演示记录为这些远端用例的 E2E pass。

聊天附件入口需要同时覆盖按钮、桌面拖拽、剪贴板粘贴和 macOS 交互式截图；
图片附件还要覆盖内联显示、远端下载到 App cache 与文件卡回退。Composer 工具栏
同时覆盖 emoji 在当前选区插入。上述 deterministic 覆盖放在
`tests/unit/chat_page_test.dart`，附件来源与截图进程解析覆盖放在
`tests/unit/attachment_picker_service_test.dart`；真实 App + CLI 附件互通仍由
`dart run tests/e2e/runner.dart --case attachment` 或 `--case full` 验证。

macOS 录屏权限绑定代码签名 designated requirement，而不只是 bundle ID。共享 Debug
配置默认使用 ad-hoc，使没有共享证书的开发者也能直接构建；ad-hoc 会把 CDHash 写进
requirement，二进制变化后 TCC 可能把它视为新的调用方。需要稳定录屏权限的开发者应复制
`macos/Runner/Configs/LocalSigning.xcconfig.example` 为 Git 忽略的
`LocalSigning.xcconfig`，并填写自己 Keychain 中可用的 Apple Development identity、
Team ID 和开发者专用 Bundle ID。任何具体 Team ID 都不得写入共享 Debug 配置。

Debug 的系统显示名必须是 `AWikiMe (Development)`，避免与已安装的 Release
`AWikiMe` 在“屏幕与系统音频录制”列表中同名，导致用户将权限授予错误的 bundle ID。
签名或开发 Bundle ID 变化时，对实际 Bundle ID 执行一次：

```bash
tccutil reset ScreenCapture <developer-bundle-id>
open "build/macos/Build/Products/Debug/AWikiMe.app"
```

系统设置中必须在上方的“录屏与系统录音”列表授权给
`AWikiMe (Development)`，不能只加到下方的“仅系统录音”列表，也不能授权给旧的
Release `AWikiMe`。允许后必须完全退出
并重新启动 App。启用本地稳定签名时，验证 `codesign -dvvv` 中不存在
`Signature=adhoc`、`TeamIdentifier` 与本地配置一致，并检查 `codesign -dr -` 的
requirement 由证书和 identifier 构成而不是 `cdhash`。截图服务还必须先调用 native preflight；权限
未生效时单进程只请求一次授权，并且不得启动 `/usr/sbin/screencapture` 或接收只有桌面的
图片。

The repository configures `package:sqlite3` to use the system SQLite library
through `hooks.user_defines.sqlite3.source: system`. This keeps the test gates
from downloading a prebuilt SQLite dylib from GitHub during native asset build
hooks. macOS provides SQLite by default. Linux runners need `libsqlite3-dev` or
an equivalent package that exposes `libsqlite3.so`.

## E2E Gate

Conversation/list/message/display-name correctness improvements are specified in
[e2e-conversation-correctness-design.md](e2e-conversation-correctness-design.md).
The document distinguishes canonical Core truth, App projection, and visible UI
evidence; none of those layers may substitute for another.

Run the local desktop smoke E2E:

```bash
dart run tests/e2e/runner.dart --case smoke
```

`smoke` starts real Flutter desktop integration shims for the app shell and
native IM Core smoke. It is the default high-frequency E2E gate for a Mac with a
normal Flutter desktop setup. It does not require test accounts, OTP, a backend,
or `awiki-cli`.

Run the local multi-device capability gate:

```bash
dart run tests/e2e/runner.dart --case multi-device

# On this macOS development host, use the audited host config explicitly:
dart run tests/e2e/runner.dart --case multi-device \
  --config tests/e2e/configs/e2e.codex-macos-allowed.local.yaml
```

This suite launches the real production bootstrap/native Core twice with
independent temporary Storage Scopes and deletes both roots after the run. It
checks default-off and Join-only App composition without using a backend, OTP,
CLI peer, copied secret state, or fake providers. The remote Join case remains
separate and is not included in this suite's pass attestation.

Run the activation-gated remote App-admin + CLI Join slice only after the
dedicated ali deployment and account have been reviewed:

```bash
AWIKI_MULTI_DEVICE_REMOTE_JOIN_E2E_ENABLED=1 \
AWIKI_MULTI_DEVICE_E2E_PHONE=<dedicated-test-phone> \
AWIKI_MULTI_DEVICE_E2E_OTP_COMMAND_JSON='["ssh","ali","--","/home/ecs-user/awiki-space/user-service/.venv/bin/python","/home/ecs-user/awiki-space/user-service/scripts/issue_multi_device_test_otp.py","--apply"]' \
AWIKI_MULTI_DEVICE_E2E_HANDLE_PREFIX=appmd \
dart run tests/e2e/runner.dart \
  --case multi-device-remote-join \
  --config <local-awiki-info-config.yaml>
```

The local YAML supplies only the reviewed `awiki.info` service endpoints, the
CLI binary, and its exact 40-character source revision. The dedicated phone and
JSON-argv OTP resolver are environment-only inputs; `otp.code`, a static OTP,
or a command whose local executable is a shell is never accepted by this suite.
Every argv item rejects whitespace, newlines, shell metacharacters and
multi-command strings; a nested `bash`/`sh -c` after `ssh` is also rejected.
The ali-side `user-service` must allow the dedicated phone hash and enable the
hidden Join rollout. The CLI must be built from exactly the configured
revision. The macOS operator must complete the real LocalAuthentication prompt;
the test only counts and delegates that prompt and never injects success.

By default the purpose-bound `/user-service/auth/sms-codes` request remains
strictly 200-only. For the user-authorized synthetic test number, an explicit
operator-only mode may be added to the command above:

```bash
AWIKI_MULTI_DEVICE_E2E_ALLOW_STAGED_OTP_ON_SMS_ERROR=1
```

This flag is accepted only with the exact reviewed resolver argv shown above.
It permits one non-retried HTTP 503 only when the response media type is
`application/problem+json` and its object contains exactly `type`, `title`,
`status`, `detail`, and `instance`: `type=about:blank`,
`title="SMS Service Error"`, integer `status=503`, `detail` beginning with
`[SMS_ERROR]`, and `instance=/user-service/auth/sms-codes`. The same scoped
resolver is then invoked immediately and must return exactly six ASCII digits.
Any other status, content type, key, value, resolver output, or malformed flag
fails closed without recording the response body.

Staged-OTP mode proves only the explicitly reviewed operator test path; it does
not prove SMS delivery, does not turn the 503 into a product-visible success,
and changes no production service behavior. The ali SSH key is not yet limited
by a server-side forced command, which remains tracked security debt. Do not
replace this mode with an online DEV route, plaintext OTP, mock, or generic
shell command.

The App is bootstrapped as the ready admin and the CLI is a newly generated,
independent requester. The test claims the pending session through the real
Devices UI, compares the independently derived six-digit SAS without recording
it, leaves the admin switch off, approves once, and requires the CLI to converge
to `active-member` with `management_ready=false`. Local roots are deleted after
the run. Because the current public contract has no test-owned remote identity
delete operation, the unique identity/Join side effect is recorded in the
runner residual ledger. Resolver stdout/stderr, OTPs, tokens, SAS values, DIDs,
private material, and local secret paths must not enter reports or logs. A
checked-in implementation or `prepare-only` result is not remote pass evidence;
while rollout or account prerequisites are unavailable, the suite fails closed
before claiming success.

Run real App + CLI peer flows when the `awiki.info` remote test account pool,
test OTP, and CLI peer are configured:

```bash
dart run tests/e2e/runner.dart --case full
```

`full` additionally runs the cross-conversation correctness slice: one Direct
and one Group receive messages in alternating order, then the test verifies
exact visible row title/preview/order, per-row and global unread isolation,
exact canonical message sequences with no leakage, and one nickname projection
across identity lookup, Direct, Contacts, group system events, and sender
labels. These checks are cataloged as `CONV-LIST-E2E-001`,
`UNREAD-MULTI-E2E-001`, `MSG-SEQUENCE-E2E-001`, and
`DISPLAY-NAME-E2E-001`. The sequence case also hides the App, sends a three-message
burst without waiting for per-message UI convergence, resumes the App, and
requires exact `+3` unread, latest preview, ordered canonical IDs/bodies, no
cross-thread leakage, and no read-state rebound. Direct and Group semantic identity have separate
`CONV-CANON-E2E-001` / `GROUP-CANON-E2E-001` evidence instead of being hidden
inside a generic message phase.

Display-name acceptance is App-visible and scoped. Once a target contact row
or group-member row is visible, a Handle/DID/Unknown primary title is fatal; the
test does not wait for a later Profile refresh to replace it with the expected
nickname. The group slice opens the real group-info dialog and checks its member
row separately from the member provider, member-added system event, and message
sender label. CLI commands only prepare the peer or trigger remote traffic;
they are diagnostic stimuli rather than a substitute CLI product gate.

AWiki Me case verdicts are App-first. Conversation count/canonical identity,
row order/title/preview/unread, bubble set/order, read transitions, and display
name consistency must be asserted from App projection plus scoped visible UI.
For App outbound flows, a CLI receipt closes the real transport loop only after
the App send state, bubble ownership, and row preview have passed. For inbound
flows, the CLI result identifies the run-owned stimulus; the required product
assertions remain the App row, badge, timeline, sender label, and read state.
Detailed CLI product behavior belongs to the CLI-owned test project and must not
replace a missing App assertion here.

The `direct` and `full` slices also inspect the scoped chat-header title from
the first frame after a restarted App shell selects the cached Direct
conversation. `DISPLAY-NAME-REG-001` fails immediately if that first non-empty
title is a Handle, DID, `Unknown`, a duplicate title widget, or later changes
during the stable observation window.

`DISPLAY-NAME-E2E-004` changes the real peer nickname after the initial
conversation, triggers the user-visible refresh by opening the peer avatar,
and then requires the new nickname to converge on the Direct detail, recents
row/header, identity lookup, Contacts, group member, existing group system
event, and existing group sender label without creating a second Persona or
conversation. The CLI only changes the remote fixture Profile; every required
verdict is taken from App projection or visible App UI.

`DISPLAY-NAME-E2E-001`, `GROUP-E2E-001`, and `GROUP-P9-001` also inspect the
visible add-member and `@` candidate rows before selection. Their primary title,
fallback avatar seed, and optional avatar URI must match the same Persona
Profile projection used by the Direct conversation; merely finding an enabled
candidate or validating the final member DID/P9 payload is insufficient.
The same flow also checks the visible group-message sender avatar and fallback
seed against the Persona Profile projection; a correct sender label alone is
not a complete identity-presentation oracle.

The focused `contacts` slice deliberately establishes the CLI peer as an
inbound follower while the isolated App projection has no Direct for that DID
or Handle. `CONTACT-FIRST-CONV-E2E-001` opens the visible follower row before
identity lookup or a first message, then requires one empty canonical
peer-scope conversation and reuses the same ID for the later contact message
closed loop. The combined `full` slice does not attest this first-create case
because it intentionally creates the Direct in the earlier Direct flow.

On macOS, pass an explicit macOS config such as:

```bash
dart run tests/e2e/runner.dart --case full \
  --config tests/e2e/configs/e2e.codex-macos-allowed.local.yaml

dart run tests/e2e/runner.dart --case restart \
  --config tests/e2e/configs/e2e.codex-macos-allowed.local.yaml

dart run tests/e2e/runner.dart --case display-name-fallback \
  --config tests/e2e/configs/e2e.handle-fallback.local.yaml
```

`display-name-fallback` 使用独立的无 nickname 远端 peer。runner 故意不执行
Profile nickname 更新，并以该 actor 的完整 Handle 作为身份查找、Direct、
Contacts、群成员、群系统事件和 sender label 的唯一 App 主显示名预期。这个
suite 不能与普通 nickname fixture 共用同一个 peer，也不能用 CLI 输出代替
App 可见标题断言。

The remote product suites must point every HTTP/WebSocket/DID domain at
`awiki.info`; they do not start a local backend.

The full real-backend E2E runner reads local configuration from
`tests/e2e/configs/e2e.local.yaml` by default. Copy the tracked template first:

```bash
cp tests/e2e/configs/e2e.example.yaml tests/e2e/configs/e2e.local.yaml
```

Required local values:

- `service.baseUrl`: remote test backend root, `https://awiki.info`.
- `service.didDomain`: remote DID domain, `awiki.info`.
- `otp.phone` and `otp.code`: the test OTP credential.
- `accounts.appUser.handle`: App-side test handle.
- `accounts.cliPeer.handle`: CLI peer test handle.
- `cliPeer.binary`: `awiki-cli` binary path.
- `cliPeer.sourceRef`: exact non-zero 40-character commit SHA embedded in the
  selected CLI binary. It does not attest the App's SDK artifact revision.

Before identity or message assertions, the runner executes `awiki-cli version`
and requires `data.commit` to equal `cliPeer.sourceRef`. `unknown`, all-zero,
malformed, or mismatched build metadata is a failed provenance preflight rather
than auditable product evidence.

Direct-message coverage also requires the App to project a successful send
result into the selected canonical timeline immediately. Realtime pending/final
patches may merge or upgrade that row, but their timing is not allowed to leave
the sender timeline empty or create a duplicate.
For a new peer-scoped conversation, the write request uses the already resolved
peer DID alias because the canonical peer-scope hash is intentionally not
reversible; returned rows and every read/timeline assertion remain canonical.
Handle lookup retries transient directory failures and fails closed rather than
silently falling back to a legacy `dm:<DID>` conversation identity.
The same successful send result must update the canonical conversation preview
immediately; preview lookup is not allowed to downgrade a peer-scoped
conversation to a stale legacy alias while waiting for a realtime patch.
Attachment preview keeps the canonical peer-scoped conversation id for local
timeline ownership, but downloads through the direct peer reference required by
the remote attachment lookup. A raw `dm:peer-scope:*` storage thread must never
be sent to the core `thread-attachment-download` capability.

All live product cases are pinned by `tests/e2e/suite_manifest.json` to
`https://awiki.info` / `wss://awiki.info/im/ws`. They reject localhost,
`awiki.test`, insecure schemes, and other domains before starting Flutter.
The smoke case has no service dependency. Dry-run only validates orchestration
and never counts as a real gate.

E2E runtime configuration is read only from the YAML file. Command-line flags do
not carry backend, account, OTP, platform, or CLI binary values. Use
`--config <path>` only to select another YAML file.

When a real App + CLI peer run starts, the runner writes an internal
`.e2e/desktop-cli-peer/current/run_config.json` file for the Flutter integration
shim. This file is generated from the YAML config and should not be edited by
hand or committed.

Supported E2E cases:

- `smoke`: app shell + native IM Core smoke, no backend account required.
- `direct`: App and CLI peer direct-message flow.
- `group`: App and CLI peer group-message flow.
- `attachment`: App and CLI peer attachment flow.
- `personal-agent`: full App UI Personal Agent real-backend gate.
- `contacts`: App and CLI peer follow/contact flow，包含从可见联系人行打开 canonical Direct 的发送、restart 和 unread/read 闭环。
- `restart`: release-only two-Flutter-process cold restart using one isolated App state root; the second process must restore the active identity, canonical Direct/Group rows, exact messages, unread state, and cached display names without in-memory Provider reuse.
- `full`: all App + CLI peer flows.

群组 E2E 使用协议级身份规则：有 Handle 时必须发送完整 `local-part.provider-domain`，bare Handle 只能从当前已认证 `did:wba` 的 provider domain 补全；无法可信补全时只允许用户显式选择 DID-only。App 和测试不得把内部 User ID 放入 ANP group body，也不得先把 Handle 解析成 DID 后丢失 Handle-backed membership 语义。

`group` / `full` case 会通过当前 tenant-scoped CLI workspace 建群和添加成员。Handle-backed recovery 的跨域 P4 continuity 由 `awiki-system-test/tests_v2/multi_tenant/test_cross_domain_message_flows.py` 负责；AWiki Me full case负责证明真实 App/CLI peer产品入口仍发送完整 Handle并完成后续群消息。

### UI-driven full acceptance

The required `direct`, `group`, `attachment`, `contacts`, and `full` cases are
product E2E, not service-client scripts. App-side sends, retry, navigation,
follow/unfollow, group creation/member invitation, structured mention, and
attachment staging are performed through `WidgetTester` against visible
controls and E2E semantics. Read-only service and CLI probes may verify the
result, but they must not perform the App user action under test.

The product oracle is fail-closed:

- all message checks require one canonical message id, terminal send state,
  exact body, sender and conversation; the direct-message slice additionally
  remains exact-one after a lifecycle reconnect and a Widget/App-shell rebuild,
  while group and attachment slices use a later history stability window (not
  an OS process restart);
- incoming direct messages require an exact unread baseline increment, matching
  navigation badge and conversation count, the exact localized conversation-row
  unread label after an App-shell rebuild, read-clear on open, no rebound, and a
  second-message increment;
- the failure/retry slice uses an E2E-only transport fault that keeps one failed
  row attached to the active canonical conversation across DID-alias writes and
  core reset patches; the visible retry must issue exactly one real remote
  transport attempt and records only its typed failure code for diagnostics;
  the later reconnect uses the legal desktop inactive -> hidden -> inactive ->
  resumed lifecycle path and does not add a production mock or fallback;
- relationship checks require the exact `none -> following -> friend ->
  follower -> none` state sequence; CLI status derives this combined state from
  all five directional booleans and separately validates that `relationship`
  remains the caller's outbound `following|none` projection; reused identities
  may enter the scenario only after both remote perspectives report `none` and
  the App `friendsProvider` projection has been refreshed to that baseline;
- contact-message checks must click the exact DID-keyed visible contact row,
  scope that row to the requested relationship section/detail pane because a
  mutual contact legitimately appears in both following and followers,
  keep one `dm:peer-scope:v1:*` identity across Core summary, UI row, timeline,
  and Product overlay, reject a legacy `dm:<DID>` overlay, and preserve the
  exact-one + unread/read result across an App-shell restart;
- group-member setup may perform one read-only resolver preflight and retry at
  most three visible search submissions, but the member action itself stays in the
  product dialog, selects one exact enabled candidate, and requires the selected
  add-member action to be enabled; the group conversation must also converge to
  its canonical id before messaging;
- group mention composition uses explicit focused text input, proves the exact
  text survives a settled frame, waits for the `GroupState.membersByGroup`
  preload, then requires the filtered candidate to appear in the first local
  frame without a loading indicator; unit coverage additionally proves a cold
  preload and consecutive query edits share exactly one group-member request.
  The flow selects one exact candidate and proves the composer clears after
  submission; CLI payload sends must return both a canonical id and
  `application/json` result type;
  group mentions require one valid structured target DID; attachment checks
  use a real temporary filesystem drop source, require the draft model and
  visible preview to preserve the exact filename, and then require exact ids,
  MIME type, size, digest, and downloaded bytes.
- Robot taps on wrapper controls resolve to exactly one enabled interactive
  `AppPressable` descendant before dispatch, so a wrapper-center hit-test miss
  cannot be mistaken for a successful product click.

`performance` remains a service-driven backend/integration diagnostic because
it directly prepares a large dataset and calls application services to measure
specific timing boundaries. Its results must not be relabeled as required UI
acceptance. Profile editing, directory-wide search, identity switch,
onboarding, group role/remove/leave flows, and secure-trust UI remain roadmap
cases until they receive their own case IDs and vertical slices; `full` does
not imply those features are covered.

Personal Agent UI changes must keep coverage in both active test domains:

- Focused widget/provider/layout coverage under `tests/unit/`, including Settings entry visibility, daemon readiness, missing bootstrap key, and feature-disabled no-op behavior.
- Durable App flow coverage under `tests/e2e/flutter/app/personal_agent_full_ui_test.dart`, with root `integration_test/personal_agent_full_ui_test.dart` kept as a thin Flutter shim.
- The fake-backed Personal Agent App shim expects `--dart-define=AWIKI_E2E=true` when tests assert semantics identifiers such as `personal-agent-settings-entry`.
- The product full chain is owned by `flutter pub run tests/e2e/runner.dart --case personal-agent`; `dart run` is acceptable only in environments where native assets can build through the Dart entrypoint. Selected runs must fail fast when backend, daemon, CLI, OTP, or Hermes prerequisites are missing and must not convert the case into a silent skip.
- Product gate evidence must include passed attestations for `PERSONALAGENT-E2E-001`, `PERSONALAGENT-E2E-002`, and `PERSONALAGENT-E2E-004`; `uiEnabled`, `runtimeFinalReceived`, and `authorizationRevoked` must be derived from those individual case results, not overall runner success. `PERSONALAGENT-E2E-003` remains planned, and there is no executable `PERSONALAGENT-E2E-005` in the current suite.
- Treat `status: success` as the first required report condition. Failed Personal Agent reports now keep evidence flags false, so old failed reports with true-looking flags must not be reused as pass evidence.

Run the Personal Agent full UI real-backend gate:

```bash
flutter pub run tests/e2e/runner.dart \
  --case personal-agent \
  --config tests/e2e/configs/e2e.local.yaml
```

`personal-agent` requires the normal backend/OTP/account/CLI values plus:

- `service.messageServiceUrl`
- `service.messageServiceWsUrl`
- `daemon.rustRepo`
- `daemon.binary`
- `daemon.stateRoot`
- `daemon.readyFile`
- `daemon.fakeHermesGatewayCommand`
- `personalAgent.runtimeProvider: hermes`
- `personalAgent.realBackend: true`

When `--case personal-agent` is selected, omitted `personalAgent.realBackend`
defaults to true. Setting it to false, omitting any required backend/daemon field,
or using a provider other than `hermes` is a configuration failure. This gate uses
the real Settings / Personal Agent UI, isolates the product scenario with the
plain-name `Personal Agent full UI drives real backend daemon and recovery`, sends
a CLI peer direct text, waits for daemon `runtime_final`, confirms the App draft
action, checks a redacted `awiki.app.action.result.v1`, and revokes Daemon message
authorization. Focused fake-backed shim tests can diagnose UI behavior, but they
are not sufficient release evidence for the product chain.

All E2E runtime state and reports go under `.e2e/` and must remain untracked.
Local config files named `tests/e2e/configs/*.local.yaml` are also ignored and
must not be committed because they may contain OTP values.

`tests/e2e/suite_manifest.json` is the checked-in suite source of truth. The
runner fails on case-ID drift, records tier/owner/required triggers/timeout,
and uses a killable child-process runner. A timeout terminates the Flutter/CLI
process tree and records `failure.code=command_timeout`; it cannot leave an
untracked test child running indefinitely.

Desktop Flutter execution is protected by a host-wide per-platform file lock
and a preflight scan for already-running `flutter test integration_test/...`
processes. This prevents separate worktrees from launching the same App bundle
on the same desktop device concurrently. The runner supplies a UTF-8 locale
when the parent shell omits one, so CocoaPods does not depend on interactive
shell initialization.

The E2E runner also gives Flutter an isolated XDG settings directory and pins
its build output to `.e2e/flutter-build/<platform>`. Integration-test host Apps
therefore never overwrite the normal developer artifact under
`build/macos/Build/Products/Debug/AWikiMe.app`. The isolated build directory is
stable per platform so repeated E2E runs remain incremental. A legacy
`$HOME/.flutter_settings` file bypasses XDG configuration, so the runner fails
closed instead of risking the normal App bundle; migrate that legacy file to
the current XDG Flutter settings location before running E2E.

On any non-zero child exit or timeout, redacted `command-failure-*.json`,
`*.stdout.log`, and `*.stderr.log` artifacts are retained in the run report
directory. The Flutter scenario also writes `scenario_progress.json` after
major Direct phases. Progress is diagnostic only and can never replace the
strict case attestation required for a passing result.

When redacted child output contains an explicit remote 5xx or transport
unavailable error, the outer report classifies it as
`remote_service_unavailable` instead of the generic `flutter_product_failed`.
This improves triage only; it never converts the failed product run to passed.

The first fail-closed three-state UI observation is retained separately as
`failure_observation.json`. It contains only a stable snake-case code, one of
`visible_ui` / `app_projection` / `core_canonical` / `remote_service`, and a
`fatal` / `timeout` / `unstable` status. Payload text, Handle, DID, credentials,
and local paths are forbidden. When the observation belongs to one cataloged
case it also records the stable `caseId`, so a failure before attestation is
reported as that case's `failed` result rather than misleading `not_run`.
Runner schema-v2 reports expose this summary as `failureObservation`;
successful runs report `not_observed`.
CLI history/inbox/group collection checks use the same three-state contract and
distinguish pending, duplicate, canonical-ID, sender/receiver/group, and content
type failures instead of returning one ambiguous boolean.

`tests/e2e/case_catalog.json` adds the case-level requirements trace: feature,
preconditions, UI/action, exact oracle, negative guard, environment, cleanup,
owner, implementation path and evidence type. Its generated view is
[test-case-catalog.md](test-case-catalog.md). Run
`dart run tool/validate_test_catalog.dart`; optionally pass
`--report <suite-report.json>` to reject unknown, duplicate, missing or
out-of-order report IDs and, for passed cases, missing, duplicate, unstable or
out-of-order assertion evidence. The catalog also records planned gaps without
adding them to an executable suite. `DISPLAY-NAME-E2E-002` is active in
`display-name-fallback` and requires a real no-nickname peer with a stable full
Handle. A recorded `awiki.info` run currently fails closed because the App
shows the remote generated user name instead of that full Handle. The separate
DID-only case `DISPLAY-NAME-E2E-003` remains planned until an actor without both
nickname and Handle is available. The release
`restart` suite now runs `PROCESS-RESTART-E2E-001` through two distinct Flutter
processes against one isolated state root. Deterministic
Widget coverage already locks identity lookup and group system events to the
public display order nickname, full Handle, then DID; it is not a substitute
for the remaining DID-only remote case.

Suite `timeoutMinutes` must be greater than or equal to `estimatedMinutes`.
The full product suite uses a 30-minute runner budget and a 29-minute Flutter
scenario budget so framework teardown remains bounded without terminating the
declared 25-minute product flow early.

The v8 `awiki.info` `full` evidence
`fixed-full-committed-20260717160000` passes all 24 declared cases with verified
schema-v2 attestation. It closes the earlier v7 red evidence by preserving two
same-body canonical messages during realtime delivery, converging them to
strictly increasing `serverSequence`, keeping hidden-burst order exact, and
persisting the newest visible Direct read watermark even when navigation held
an older conversation summary. The exact-order and unread-no-rebound oracles
remain strict; they were not replaced with eventual containment or UI-only
success.

Conversation-correctness cases additionally declare `assertionContract` in
the catalog. It maps every exact-oracle and negative-guard claim to stable
`CASE-ID:snake_case` evidence and fixes the expected assertion order. A report
whose phases are internally well formed but drift from that catalog contract
is rejected rather than accepted as a generic pass.

Before App launch, the runner creates and activates an isolated CLI tenant whose
`backend_base_url` and `did_host` match `awiki.info`, then proves that the CLI
current DID equals directory resolution of the configured CLI handle, that the
App handle resolves, and that the two identities are distinct. This prevents a
green result or opaque timeout caused by silently using the CLI default
`awiki.ai` tenant or a stale fixed-account mapping.

Every run writes `resource_ledger.json` next to `timings.json`. When remote
product actions may have created messages, groups, relationships, attachments,
or read state but no public deletion API exists, the ledger says `residual`
with categories/count knowledge and no raw DID/token/message content. This is
an explicit retention debt, not a successful-cleanup claim.

### Identity vault test state

E2E runs pass `AWIKI_E2E_APP_STATE_ROOT` to the Flutter shims. That explicit
root selects `E2eFileScopeSecretRepository`; it stores one strict envelope per
Storage Scope under `support/awiki-me/e2e-scope-secrets/`, with `0700` directory
and `0600` envelope/lock permissions on Linux/macOS. It never reads a production
Keychain item.

The native im-core smoke now follows the production lifecycle: explicit scope
provision, runtime `openExisting`, native `VaultRequired` open, same-process
runtime reopen with the same root, and missing-key fail-closed without recreate.
The release-only `NATIVE-E2E-002` gate builds and signs the production bundle
three times, launches three independent App processes for provision/reopen/cleanup,
rejects the development service, proves `createExclusive` cannot replace the item,
and verifies the signing Team/bundle identity before every launch:

```bash
AWIKI_MACOS_SIGNING_IDENTITY="<stable identity>" \
AWIKI_MACOS_DEVELOPMENT_TEAM="<matching team id>" \
scripts/run_macos_production_scope_restart_gate.sh
```

The script never prints the Keychain value and deletes its run-unique production
item on success or best-effort failure cleanup. An ad-hoc signature or mismatched
Team ID fails the gate. Trial-package signing follows the same contract through
`scripts/package_app.local.config` or CI environment variables. See
`docs/macos-signing.md`; certificate bundles and private keys must never be
stored in the repository.

Unit coverage lives in:

- `tests/unit/data/storage/`
- `tests/unit/data/im_core/awiki_im_core_secret_storage_test.dart`
- `tests/unit/data/im_core/awiki_im_core_runtime_test.dart`
- `tests/unit/data/tenant/app_tenant_store_test.dart`
- `tests/unit/tenant_runtime_transition_test.dart`

The App-side vault contract is documented in `docs/identity-secret-storage.md`.
The shared SDK/CLI/daemon design is in
`awiki-cli-rs2/docs/architecture/identity-secret-storage.md`.

## Direct Shim Commands

Useful direct shim commands while debugging E2E internals:

```bash
LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 flutter test integration_test/app_smoke_test.dart -d macos
LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 flutter test integration_test/im_core_open_smoke_test.dart -d macos
LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 flutter test integration_test/ui_visual_verification_test.dart -d macos
```

For UI / visual verification, the screenshot smoke writes PNG evidence under
`docs/ui-optimization-plan/screenshots/`. If the screenshots are not the intended
change, restore them before committing.

## Memory Leak Checks

代码侧内存泄漏检查优先覆盖三类资源：

- StatefulWidget 持有的 `TextEditingController`、`ScrollController`、`FocusNode`
  必须在 `dispose()` 释放；临时 dialog controller 也要在 dialog 关闭后释放。
- provider / controller 持有的 `Timer`、`Timer.periodic`、`StreamSubscription`
  必须在 `dispose()`、`clear()` 或对应 cancel 路径释放。

建议验证流程：

```bash
dart analyze
flutter test tests/unit/chat_page_test.dart tests/unit/conversation_workspace_test.dart
flutter test tests/unit/agents/agents_page_layout_test.dart tests/unit/group_flow_test.dart tests/unit/profile_page_test.dart
```

若要做运行时 retained-object 验证，使用 Flutter DevTools Memory：

```bash
flutter run -d macos --profile
```

打开 DevTools Memory 后，对“消息页 ⇄ 个人资料 / 群弹窗”等常用路径循环 20-50
次，分别在循环前后采集 heap snapshot。重点确认 `ChatView`、
`TextEditingController`、`ScrollController`、`Timer` 和 `StreamSubscription`
没有随循环次数持续增长。

## Local Gate

Recommended deterministic local gate:

```bash
PUB_HOSTED_URL=https://mirrors.tuna.tsinghua.edu.cn/dart-pub flutter pub get
dart analyze
dart run tests/unit/runner.dart
dart run tests/e2e/runner.dart --case smoke
```

Run `dart run tests/e2e/runner.dart --case full` only when real non-production
backend credentials, OTP, and CLI peer configuration are prepared.

## Gate Policy

| Gate | Default trigger | Required environment | Must run | Must not require |
| --- | --- | --- | --- | --- |
| PR required | Every pull request and push to main | Flutter, sibling `awiki-cli-rs2` at an exact SHA, deterministic service-independent dependencies. | `dart analyze`, `dart run tests/unit/runner.dart`, smoke E2E. | Real OTP, real service accounts, live backend, mobile devices, SSH evidence. |
| Optional desktop | Developer or self-hosted runner with desktop support | macOS or Linux desktop runner. | App shell and native SDK smoke on the available desktop platform. | Non-production account pool or real message service. |
| Nightly desktop | Prepared runner | Remote `awiki.info`, OTP/account pool, debug `awiki-cli` + SDK built from one exact SHA, isolated App and CLI state. | Direct message, contacts, group, attachment basics, report/redaction/resource ledger. | Local service stacks or scenarios without owner. |
| Nightly mobile | Prepared device runner | iOS or Android device pair, Maestro, local config from secrets. | Real two-device direct message when device pool is available. | Desktop-only scenarios. |
| Release | Release candidate validation | Stable nightly environment plus release owner review. | P0/P1 regression subset for desktop smoke, native SDK smoke, App + CLI basics, mobile when available. | New feature cases that have not been promoted. |
| Manual | Developer or QA runbook | Local or remote environment prepared by the runner. | Any focused case needed for debugging or evidence, with command, runId, platform, endpoints, and report path recorded. | Manual results presented as automatic PR gate evidence. |

Real E2E reports must record `runId`, platform, scenario, case IDs,
pass/fail/skipped status, skipped reason when applicable, and a redaction scan
result. Keep `.e2e/`, `*.local.yaml`, OTP values, JWTs, private keys, CLI
workspaces, App state roots, remote logs, screenshots, and device state out of
Git.

The checked-in workflow requires `AWIKI_CLI_RS2_REF` to be an exact commit SHA.
Its `remote-product` job is schedule/manual only, builds debug/incremental Rust
artifacts, writes a secret-backed ignored config, and targets only `awiki.info`.
The PR dry-run is orchestration lint and is never substituted for that real job.

### Case-level attestation and fail-closed reports

Runner reports use schema v2. `status=passed` is valid only when the Flutter
scenario itself writes a schema-v2 `case_attestation.json` and every expected
case ID has one unique `status=passed` result with non-empty phases, timestamps,
and structured assertion evidence. Assertion IDs use stable
`CASE-ID:snake_case` names and must match the phase sequence exactly; missing,
duplicate, failed, unstable, or reordered evidence fails closed. The outer
Flutter process exit code is necessary but is not enough.

The runner reports `dry_run` and `prepared` as distinct non-passing suite and
case states. Missing, duplicate, unknown, skipped, failed, corrupt, wrong-run,
or wrong-scenario attestation results make a real run `failed`. The report keeps
the expected IDs in `caseIds`, actual successful IDs in `passedCaseIds`, and one
entry per expected case in `caseResults`. Attestation and workspace paths remain
redacted; the scenario file stores only case IDs, phase/assertion IDs, status,
and timestamps. This is the first assertion-evidence layer; one-to-one trace
from every catalog exact oracle/negative guard to a dedicated assertion ID is
still required before the conversation-correctness plan is complete.

Personal Agent fake Widget coverage is not product acceptance. The optional real
`personal-agent` suite currently attests only implemented vertical slices:
`PERSONALAGENT-E2E-001` enable/binding, `PERSONALAGENT-E2E-002` CLI message plus runtime
result, and `PERSONALAGENT-E2E-004` UI revoke plus exact User Service/daemon
convergence. `PERSONALAGENT-E2E-003` (visible action/draft confirmation) is planned
in the catalog because the supporting action step does not yet have its own
accepted case attestation. Missing provider/configuration or any non-attested
runnable case remains failed/not-run, never passed.

## Maintenance Rules

- Add ordinary logic, provider, and widget coverage to `tests/unit/`.
- Add user-flow and platform smoke coverage to `tests/e2e/`.
- Keep root `integration_test/` as shim-only.
- Do not keep skipped, deferred, historical, or dry-run-only business scenarios
  in the active test tree.
- Keep `suite_manifest.json`, `case_catalog.json`, generated catalog docs and
  runner constants in lockstep; planned cases belong only in the catalog.
- Do not commit local configs, OTPs, tokens, generated workspaces, or E2E
  reports.
- A failed real E2E must be classified as product regression, test bug,
  account/OTP problem, backend deployment problem, runner/device problem, or
  unknown. Do not hide a failure by only increasing timeout.
