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

Run real App + CLI peer flows when a test backend and test OTP are configured:

```bash
dart run tests/e2e/runner.dart --case full
```

The full real-backend E2E runner reads local configuration from
`tests/e2e/configs/e2e.local.yaml` by default. Copy the tracked template first:

```bash
cp tests/e2e/configs/e2e.example.yaml tests/e2e/configs/e2e.local.yaml
```

Required local values:

- `service.baseUrl`: backend root, for example `https://anpclaw.com`.
- `service.didDomain`: DID domain, for example `anpclaw.com`.
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
- `message-agent`: full App UI Message Agent real-backend gate.
- `full`: all App + CLI peer flows.

Message Agent UI changes must keep coverage in both active test domains:

- Focused widget/provider/layout coverage under `tests/unit/`, including Settings entry visibility, daemon readiness, missing bootstrap key, and feature-disabled no-op behavior.
- Durable App flow coverage under `tests/e2e/flutter/app/message_agent_full_ui_test.dart`, with root `integration_test/message_agent_full_ui_test.dart` kept as a thin Flutter shim.
- The fake-backed Message Agent App shim expects `--dart-define=AWIKI_E2E=true` when tests assert semantics identifiers such as `message-agent-settings-entry`.
- The product full chain is owned by `flutter pub run tests/e2e/runner.dart --case message-agent`; `dart run` is acceptable only in environments where native assets can build through the Dart entrypoint. Selected runs must fail fast when backend, daemon, CLI, OTP, or Hermes prerequisites are missing and must not convert the case into a silent skip.
- Product gate evidence must include `MSGAGENT-E2E-001` through `MSGAGENT-E2E-005`, plus report flags for `uiEnabled`, `runtimeFinalReceived`, `draftConfirmed`, `actionResultReturned`, and `authorizationRevoked`.

Run the Message Agent full UI real-backend gate:

```bash
flutter pub run tests/e2e/runner.dart \
  --case message-agent \
  --config tests/e2e/configs/e2e.local.yaml
```

`message-agent` requires the normal backend/OTP/account/CLI values plus:

- `service.messageServiceUrl`
- `service.messageServiceWsUrl`
- `daemon.rustRepo`
- `daemon.binary`
- `daemon.stateRoot`
- `daemon.readyFile`
- `daemon.fakeHermesGatewayCommand`
- `messageAgent.runtimeProvider: hermes`
- `messageAgent.realBackend: true`

When `--case message-agent` is selected, omitted `messageAgent.realBackend`
defaults to true. Setting it to false, omitting any required backend/daemon field,
or using a provider other than `hermes` is a configuration failure. This gate uses
the real Settings / Message Agent UI, isolates the product scenario with the
plain-name `Message Agent full UI drives real backend daemon and recovery`, sends
a CLI peer direct text, waits for daemon `runtime_final`, confirms the App draft
action, checks a redacted `awiki.app.action.result.v1`, and revokes Daemon message
authorization. Focused fake-backed shim tests can diagnose UI behavior, but they
are not sufficient release evidence for the product chain.

All E2E runtime state and reports go under `.e2e/` and must remain untracked.
Local config files named `tests/e2e/configs/*.local.yaml` are also ignored and
must not be committed because they may contain OTP values.

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
