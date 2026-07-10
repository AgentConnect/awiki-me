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
```

聊天附件入口需要同时覆盖按钮、桌面拖拽和剪贴板粘贴。拖拽/粘贴入口的
deterministic 覆盖放在 `tests/unit/chat_page_test.dart`，附件来源解析覆盖放在
`tests/unit/attachment_picker_service_test.dart`；真实 App + CLI 附件互通仍由
`dart run tests/e2e/runner.dart --case attachment` 或 `--case full` 验证。

The repository configures `package:sqlite3` to use the system SQLite library
through `hooks.user_defines.sqlite3.source: system`. This keeps the test gates
from downloading a prebuilt SQLite dylib from GitHub during native asset build
hooks. macOS provides SQLite by default. Linux runners need `libsqlite3-dev` or
an equivalent package that exposes `libsqlite3.so`.

## E2E Gate

Run the local desktop smoke E2E:

```bash
dart run tests/e2e/runner.dart --case smoke
```

`smoke` starts real Flutter desktop integration shims for the app shell and
native IM Core smoke. It is the default high-frequency E2E gate for a Mac with a
normal Flutter desktop setup. It does not require test accounts, OTP, a backend,
or `awiki-cli`.

Run real App + CLI peer flows when the `awiki.info` remote test account pool,
test OTP, and CLI peer are configured:

```bash
dart run tests/e2e/runner.dart --case full
```

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
- `contacts`: App and CLI peer follow/contact flow.
- `full`: all App + CLI peer flows.

### UI-driven full acceptance

The required `direct`, `group`, `attachment`, `contacts`, and `full` cases are
product E2E, not service-client scripts. App-side sends, retry, navigation,
follow/unfollow, group creation/member invitation, structured mention, and
attachment staging are performed through `WidgetTester` against visible
controls and E2E semantics. Read-only service and CLI probes may verify the
result, but they must not perform the App user action under test.

The product oracle is fail-closed:

- message checks require one canonical message id, terminal send state, exact
  body, sender and conversation, and remain exact-one after reconnect and App
  restart;
- incoming direct messages require an exact unread baseline increment, matching
  navigation badge and conversation count, read-clear on open, no rebound, and
  a second-message increment;
- the failure/retry slice uses an E2E-only transport fault that emits a failed
  timeline patch, then the visible retry action delegates to the real remote
  messaging service; it does not add a production mock or fallback;
- relationship checks require the exact `none -> following -> friend ->
  follower -> none` state sequence;
- group mentions require one valid structured target DID; attachment checks
  require exact ids, filename, MIME type, size, digest, and downloaded bytes.

`performance` remains a service-driven backend/integration diagnostic because
it directly prepares a large dataset and calls application services to measure
specific timing boundaries. Its results must not be relabeled as required UI
acceptance. Profile editing, directory-wide search, identity switch,
onboarding, group role/remove/leave flows, and secure-trust UI remain roadmap
cases until they receive their own case IDs and vertical slices; `full` does
not imply those features are covered.

All E2E runtime state and reports go under `.e2e/` and must remain untracked.
Local config files named `tests/e2e/configs/*.local.yaml` are also ignored and
must not be committed because they may contain OTP values.

### Identity vault test state

E2E runs pass `AWIKI_E2E_APP_STATE_ROOT` to the Flutter shims. In that explicit
E2E mode, AWiki Me uses `awiki_me_im_core_vault.json` as a private file test
provider for the App-local `im-core` identity vault root key and device id. The
file is created under the E2E App support root with strict JSON reads and
private file permissions on Linux/macOS. It may contain a base64 test root key,
so it is local secret state and must remain untracked with the rest of `.e2e/`.
When the E2E state root is relative, normal test runners resolve it against the
repository working directory. If an E2E-built macOS app is accidentally launched
as a GUI app with `/` as its working directory, AWiki Me resolves that relative
root under the user's Application Support directory instead of trying to create
`/.e2e` on the read-only system volume.

Ordinary `appStateRoot` overrides do not move the vault root key into JSON; they
still use the platform secure-storage provider. Unit coverage for this boundary
lives in:

- `tests/unit/bootstrap_test.dart`
- `tests/unit/data/im_core/awiki_im_core_secret_storage_test.dart`
- `tests/unit/data/im_core/awiki_im_core_runtime_test.dart`
- `tests/unit/application/app_session_service_test.dart`

These tests cover stable namespace-scoped root keys, corrupted root-key
fail-closed behavior, strict file stores refusing to recreate missing root keys
in existing files, `VaultRequired` open options, and activation-time vault
verification before identity switching.

The App-side vault contract, E2E file-provider boundary, and activation-time
verification gate are documented in `docs/identity-secret-storage.md`. The shared
SDK/CLI/daemon design is in
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
| PR required | Every pull request and push to main | Flutter, sibling `awiki-cli-rs2`, deterministic local dependencies. | `dart analyze`, `dart run tests/unit/runner.dart`, smoke E2E. | Real OTP, real service accounts, live backend, mobile devices, SSH evidence. |
| Optional desktop | Developer or self-hosted runner with desktop support | macOS or Linux desktop runner. | App shell and native SDK smoke on the available desktop platform. | Non-production account pool or real message service. |
| Nightly desktop | Prepared runner | Non-production services, OTP, built `awiki-cli`, isolated App and CLI state. | Direct message, contacts, group, attachment basics, report redaction scan. | Scenarios without owner or maintained environment. |
| Nightly mobile | Prepared device runner | iOS or Android device pair, Maestro, local config from secrets. | Real two-device direct message when device pool is available. | Desktop-only scenarios. |
| Release | Release candidate validation | Stable nightly environment plus release owner review. | P0/P1 regression subset for desktop smoke, native SDK smoke, App + CLI basics, mobile when available. | New feature cases that have not been promoted. |
| Manual | Developer or QA runbook | Local or remote environment prepared by the runner. | Any focused case needed for debugging or evidence, with command, runId, platform, endpoints, and report path recorded. | Manual results presented as automatic PR gate evidence. |

Real E2E reports must record `runId`, platform, scenario, case IDs,
pass/fail/skipped status, skipped reason when applicable, and a redaction scan
result. Keep `.e2e/`, `*.local.yaml`, OTP values, JWTs, private keys, CLI
workspaces, App state roots, remote logs, screenshots, and device state out of
Git.

### Case-level attestation and fail-closed reports

Runner reports use schema v2. `status=passed` is valid only when the Flutter
scenario itself writes a schema-v1 `case_attestation.json` and every expected
case ID has one unique `status=passed` result with non-empty phases and
timestamps. The outer Flutter process exit code is necessary but is not enough.

The runner reports `dry_run` and `prepared` as distinct non-passing suite and
case states. Missing, duplicate, unknown, skipped, failed, corrupt, wrong-run,
or wrong-scenario attestation results make a real run `failed`. The report keeps
the expected IDs in `caseIds`, actual successful IDs in `passedCaseIds`, and one
entry per expected case in `caseResults`. Attestation and workspace paths remain
redacted; the scenario file stores only case IDs, phase names, status, and
timestamps.

Message Agent daemon management UI is currently hidden. Therefore its fake
Widget coverage is not product acceptance, and `--case message-agent` must not
report `passed` until the real UI scenario can attest all of
`MSGAGENT-E2E-001..004`. A missing/disabled real-backend config, the hidden UI,
or an unimplemented action-confirmation/lifecycle phase is an explicit failing
gate rather than a skipped or successful result.

## Maintenance Rules

- Add ordinary logic, provider, and widget coverage to `tests/unit/`.
- Add user-flow and platform smoke coverage to `tests/e2e/`.
- Keep root `integration_test/` as shim-only.
- Do not keep skipped, deferred, historical, or dry-run-only business scenarios
  in the active test tree.
- Do not commit local configs, OTPs, tokens, generated workspaces, or E2E
  reports.
- A failed real E2E must be classified as product regression, test bug,
  account/OTP problem, backend deployment problem, runner/device problem, or
  unknown. Do not hide a failure by only increasing timeout.
