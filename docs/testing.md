# Testing AWiki Me

AWiki Me uses Flutter and Dart tooling only. Tests are organized into three
parallel domains so unit, integration, and end-to-end concerns do not drift into
one another:

```text
tests/unit_test/          # fast unit/widget/provider tests with fakes
tests/integration_test/   # Flutter engine, platform binding, and native smoke tests
tests/e2e_test/           # real App + CLI peer/backend harnesses, configs, reports
```

Root files under `integration_test/` are Flutter-tooling shims. Keep the real
implementation under `tests/integration_test/` unless a test must be a root
entrypoint for `flutter test -d <device>`.

## Unit tests

`tests/unit_test/` contains deterministic tests that do not require a real
device, real backend, or real `awiki-cli` subprocess. This includes pure Dart
logic, application/data services with fakes, widget/provider tests, and pure E2E
harness parser/planning tests.

Run:

```bash
flutter test tests/unit_test
```

Focused group mention composer checks:

```bash
flutter test tests/unit_test --name mention
flutter test tests/unit_test --name "chat mention"
```

These cover the group-only `@` trigger, fixed selector/member candidates,
displayName/handle/DID search, unknown `subjectType` disabling for single-member
targets, draft range invalidation, and Unicode code point offsets needed by ANP
P9 payloads.

Unit fakes live under `tests/unit_test/support/` and
`tests/unit_test/test_support.dart`. Integration-only bootstraps live under
`tests/integration_test/support/`. Keep production code free of test-only mocks.

## Integration tests

`tests/integration_test/` contains Flutter integration smoke test
implementations. These may run against a desktop target such as macOS or Linux,
but they should not implement a real multi-client backend E2E flow.

Current groups:

- `tests/integration_test/app/` - App shell smoke with fake bootstrap.
- `tests/integration_test/native/` - native SDK/plugin smoke such as
  `AwikiImCore.open`.
- `tests/integration_test/agent_im/` - Agent IM App bootstrap smoke.
- `tests/integration_test/support/` - integration-only helpers.

macOS examples using the root shims:

```bash
flutter test integration_test/app_smoke_test.dart -d macos
flutter test integration_test/im_core_open_smoke_test.dart -d macos
flutter test integration_test/agent_im_delegated_message_e2e_test.dart -d macos
```

Linux desktop integration is supported through the `linux/` runner. Ubuntu
hosts need Flutter Linux desktop prerequisites and an X server; CI and servers
without a real desktop should use `xvfb-run`:

```bash
sudo apt update
sudo apt install -y \
  clang cmake ninja-build pkg-config libgtk-3-dev liblzma-dev \
  libsecret-1-dev xvfb dbus-x11
flutter config --enable-linux-desktop
flutter devices
```

Fast Linux desktop smoke:

```bash
xvfb-run -a flutter test integration_test/app_smoke_test.dart -d linux
```

This uses fake App bootstrap and proves the Linux runner, Flutter shell,
platform binding, App shell, onboarding shell, authenticated shell, and basic
profile/settings navigation can start under Xvfb. It does not test real login,
networking, secure storage, User Service, Message Service, or CLI peer behavior.

Linux native SDK smoke:

```bash
xvfb-run -a flutter test integration_test/im_core_open_smoke_test.dart -d linux
```

This opens the real `awiki_im_core` Linux native backend and validates isolated
SDK paths. Build the Linux native library from the sibling SDK repo first:

```bash
cd ../awiki-cli-rs2
scripts/flutter/build-sdk-native.sh --linux-only
```

The implementation plan and execution evidence for the Linux Desktop runner,
Linux native `awiki_im_core` support, and App + CLI peer E2E topology are in
[e2e/linux-desktop-cli-peer-e2e/plan.md](e2e/linux-desktop-cli-peer-e2e/plan.md).

## End-to-end tests

`tests/e2e_test/` contains end-to-end harnesses, example configs, mobile Maestro
flows, and desktop scenario planning. E2E may use the real App,
`awiki-cli-rs2` as a CLI peer, and a reachable non-production backend.

Structure:

```text
tests/e2e_test/
  harness/
    desktop_e2e_runner.dart    # shared desktop runner: macOS/Linux platform arg
    mobile_e2e_runner.dart     # iOS/Android Maestro runner
  configs/
    agent_im_delegated.example.yaml
    mobile.example.yaml
  mobile/maestro/
  scenarios/
```

### Deferred Desktop Agent IM scenario

The desktop runner is shared by macOS and Linux. It reuses one architecture for
service config, CLI build, CLI peer workspace, timing reports, and App
dart-defines. Only the platform adapter differs:

- macOS: checks `xcrun`, runs `flutter test -d macos`.
- Linux: checks Linux desktop tooling and runs through `xvfb-run`.

The Agent IM delegated-message scenario remains in the repository as prior
scenario infrastructure and historical evidence. It is not part of the current
basic AWiki Me E2E regression baseline. In the baseline matrix it is tracked as
`AGENT-SKIP-001`: keep the entry, but do not run it, promote it, or require
validation evidence in PR, nightly, or release gates until a separate Agent IM
plan explicitly reactivates it.

Agent IM delegated-message dry-run:

```bash
dart run tests/e2e_test/harness/desktop_e2e_runner.dart \
  --platform=linux \
  --scenario=agent-im-delegated-message \
  --config tests/e2e_test/configs/agent_im_delegated.example.yaml \
  --dry-run
```

The checked-in config contains placeholders and environment variable names only.
The runner writes redacted `scenario-plan.json`, `cli-peer-plan.json`, and
`agent-im-scenario-result.json` reports. Copy the example config to an ignored
local config only when executing the standalone Agent IM plan. Do not commit
local configs, generated CLI workspaces, reports, OTP values, tokens, private
keys, or remote log captures.

Historical real Agent IM delegated-message runs required both local App evidence
and remote daemon evidence:

- the App sent `awiki.daemon.bootstrap.v1` through the real IM payload path;
- the CLI peer from `awiki-cli-rs2` sent an ordinary message to the App user;
- remote evidence observed `daemon_bootstrap_received`,
  `delegated_key_imported`, `hermes_agent_ready`, `cli_message_received`,
  `hermes_runtime_finished`, and `summary_return_sent`;
- the App received hidden, non-renderable `awiki.message.sync.v1`
  `runtime_status` / `runtime_final` payloads instead of normal chat bubbles.

Latest verified P0 run on `awiki.info`: `20260614T024413341Z`, message
`msg_agent_im_20260614T024413341Z`, with `AIM-E2E-001`, `AIM-E2E-002`, and
`AIM-E2E-006` passing. Follow-up scenarios for daemon restart/cursor recovery,
E2EE opaque boundaries, delegated DID revoke behavior, and unknown payload
negative injection remain P1/P2 and must not be described as completed by that
historical run or by the current basic E2E baseline.

Agent IM bootstrap is intentionally behind a temporary App-side feature flag.
Normal App builds default to disabled (`AWIKI_AGENT_IM_ENABLED=false`), so
`DefaultAgentControlService.ensureMessageAgentBootstrap` becomes a no-op and the
App does not send delegated-key bootstrap payloads. To reopen the feature for
manual App testing, build/run with `--dart-define=AWIKI_AGENT_IM_ENABLED=true`.
The dedicated E2E probe/scenario enables the flag explicitly so the P0 gate can
still be run without deleting or reworking Agent IM code.

Standalone macOS run for future Agent IM work:

```bash
dart run tests/e2e_test/harness/desktop_e2e_runner.dart \
  --platform=macos \
  --scenario=agent-im-delegated-message \
  --config tests/e2e_test/configs/agent_im_delegated.local.yaml
```

For compatibility, the old wrapper remains available:

```bash
dart run tool/macos_e2e_runner.dart --dry-run
```

Reports are written under `.e2e/<platform>/reports/<runId>/`. The OTP variables
are detected for later live auth flows but are not printed or persisted by the
runner. These reports are not baseline gate evidence while `AGENT-SKIP-001`
remains skipped.

### Desktop App + CLI Peer E2E

`integration_test/desktop_cli_peer_smoke_test.dart` is the full manual/nightly
Desktop App + CLI peer smoke. It starts the real App bootstrap, prepares or uses
a real App test identity, uses `awiki-cli-rs2` as the peer client, and runs the
direct message, group message, and attachment flows with a unique run id.

The same implementation is split into focused scenario entrypoints so local
debugging and release triage do not have to run the full suite:

| Scenario | Flutter entrypoint | Runner case |
| --- | --- | --- |
| Full regression | `integration_test/desktop_cli_peer_smoke_test.dart` | `--case full` |
| Direct message only | `integration_test/desktop_cli_peer_direct_test.dart` | `--case direct` |
| Group message only | `integration_test/desktop_cli_peer_group_test.dart` | `--case group` |
| Direct attachment only | `integration_test/desktop_cli_peer_attachment_test.dart` | `--case attachment` |

The test is skipped unless `AWIKI_E2E=true`, so this command is safe as a
build/smoke check without backend credentials:

```bash
xvfb-run -a flutter test integration_test/desktop_cli_peer_smoke_test.dart -d linux
```

Run the real E2E through the runner so CLI workspace, CLI `HOME`, App state,
reports, and secrets stay isolated and redacted:

```bash
DEV_OTP_PHONE="$DEV_OTP_PHONE" \
DEV_OTP_CODE="$DEV_OTP_CODE" \
AWIKI_CLI_BIN="../awiki-cli-rs2/target/release/awiki-cli" \
AWIKI_USER_SERVICE_URL="$AWIKI_USER_SERVICE_URL" \
AWIKI_MESSAGE_SERVICE_URL="$AWIKI_MESSAGE_SERVICE_URL" \
dart run tool/desktop_cli_peer_e2e_runner.dart \
  --platform linux \
  --service-base-url "$AWIKI_SERVICE_BASE_URL" \
  --did-domain "$AWIKI_DID_DOMAIN"
```

To run a smaller slice, add `--case direct`, `--case group`, or
`--case attachment`. Without `--case`, the runner keeps using the full
regression entrypoint for compatibility.

Use the same test on macOS:

```bash
flutter test integration_test/desktop_cli_peer_smoke_test.dart -d macos
```

The real Desktop App+CLI peer E2E requires non-production User Service,
Message Service, DID domain, OTP credentials, a built `awiki-cli`, and two
isolated identities. If User Service and Message Service have different base
URLs, set both `AWIKI_USER_SERVICE_URL` and `AWIKI_MESSAGE_SERVICE_URL`; local
legacy `molt-message` on port 9898 does not expose the v2 `/im/rpc` endpoint.

Do not put the real backend + OTP Desktop E2E in the ordinary PR required gate.
Keep it in manual, nightly, or release gates until the services, account pool,
and runner environment are stable.

### Mobile E2E

Mobile E2E is driven by `tests/e2e_test/harness/mobile_e2e_runner.dart` and
Maestro flows under `tests/e2e_test/mobile/maestro/`. It covers the real
two-device smoke path for iOS/Android.

Dry-run:

```bash
dart run tests/e2e_test/harness/mobile_e2e_runner.dart \
  --config tests/e2e_test/configs/mobile.example.yaml \
  --dry-run
```

The dry-run writes `.e2e/reports/<runId>/timings.json` with the
`mobile-two-device` scenario, `MOBILE-E2E-001`, platform/app metadata, account
handles, configured device summary, planned A_TO_B / B_TO_A messages, and
`caseStatus: skipped`. This means the harness and command plan are valid, but
real device preparation, installation, login, and Maestro flows were not run.
Report paths and device IDs are redacted, service URLs are stored without query
strings, and command logs redact phone, OTP, token, JWT, private, and secret
values.

For compatibility, the old wrapper remains available:

```bash
dart run tool/e2e_runner.dart \
  --config tests/e2e_test/configs/mobile.example.yaml \
  --dry-run
```

Real mobile E2E requires a local config, two devices/simulators, Maestro, and a
reachable non-production backend. Never commit local configs, `.e2e/`, real
credentials, generated local state, or device-specific reports.

## Recommended local gate

```bash
PUB_HOSTED_URL=https://mirrors.tuna.tsinghua.edu.cn/dart-pub flutter pub get
dart analyze
flutter test tests/unit_test
dart run tests/e2e_test/harness/mobile_e2e_runner.dart \
  --config tests/e2e_test/configs/mobile.example.yaml \
  --dry-run
dart run tests/e2e_test/harness/desktop_e2e_runner.dart \
  --platform=linux \
  --dry-run \
  --skip-cli-build \
  --skip-flutter-smoke
xvfb-run -a flutter test integration_test/app_smoke_test.dart -d linux
xvfb-run -a flutter test integration_test/im_core_open_smoke_test.dart -d linux
```

## CI gate

The quick CI gate should stay deterministic and not depend on real devices,
OTP, SSH, or a live backend:

```bash
flutter pub get
dart analyze
flutter test tests/unit_test
dart run tests/e2e_test/harness/mobile_e2e_runner.dart \
  --config tests/e2e_test/configs/mobile.example.yaml \
  --dry-run
dart run tests/e2e_test/harness/desktop_e2e_runner.dart \
  --platform=linux \
  --dry-run \
  --skip-cli-build \
  --skip-flutter-smoke
xvfb-run -a flutter test integration_test/app_smoke_test.dart -d linux
xvfb-run -a flutter test integration_test/im_core_open_smoke_test.dart -d linux
```

The checked-in GitHub Actions workflow runs this shape on Ubuntu. It checks out
`awiki-cli-rs2` beside this repo because `pubspec.yaml` uses
`../awiki-cli-rs2/packages/awiki_im_core`; set `AWIKI_CLI_RS2_REF` when CI must
use a non-default SDK branch, and set `AWIKI_CI_READ_TOKEN` if the sibling repo
requires a token. Linux desktop app/native smoke is deterministic after Linux
desktop dependencies, Xvfb, SQLite source, and the sibling native SDK build are
available.

This gate intentionally does not run real backend + OTP Desktop App+CLI peer
E2E, real Agent IM scenarios, or real-device mobile E2E.

## E2E gate policy

| Gate | Default trigger | Required environment | Must run | Must not run |
|---|---|---|---|---|
| PR required | Every pull request and push to `main` | Ubuntu CI, Flutter, Rust, Linux desktop deps, sibling `awiki-cli-rs2` checkout. | `dart analyze`, `flutter test tests/unit_test`, mobile dry-run, desktop dry-run, Linux app smoke, Linux native SDK smoke. | Real OTP, real service accounts, Desktop App+CLI real E2E, Agent IM real E2E, mobile devices, SSH remote evidence. |
| PR optional desktop | Developer or self-hosted runner with desktop support | macOS or Linux desktop runner; Linux uses `xvfb-run`. | `integration_test/app_smoke_test.dart` and `integration_test/im_core_open_smoke_test.dart` on the available desktop platform. | Any test that needs a non-production account pool or real message service. |
| Nightly desktop | Scheduled or manual workflow on a prepared runner | Non-production User Service/Message Service/DID domain, OTP env, built `awiki-cli`, isolated App and CLI state. | Desktop App+CLI peer direct message, history/inbox/refresh, group text, small attachment send/receive, report redaction scan. | `AGENT-SKIP-001`, `E2EE-SKIP-001`, and any scenario without a maintained owner. |
| Nightly mobile | Scheduled or manual workflow on a device runner | iOS or Android device pair, Maestro, `mobile.local.yaml` from CI secrets, non-production account pool. | `MOBILE-E2E-001` real two-device direct message with logs/screenshots/report retained as private artifacts. | Desktop-only scenarios and any mobile run without two independent devices. |
| Release | Release candidate validation | Stable nightly environment plus release owner review. | P0/P1 regression subset: desktop smoke, native SDK smoke, Desktop App+CLI direct/group/attachment basics, mobile two-device when device pool is available. | New `feature` cases that have not been promoted, skipped Agent-as-IM-handler and E2EE专项 cases. |
| Manual | Developer or QA runbook | Local or remote environment prepared by the runner. | Any focused case needed for debugging or release evidence, with command, runId, platform, service endpoints, and report path recorded. | Manual results presented as automatic PR gate evidence. |

Real E2E reports must record `runId`, platform, scenario, case IDs,
pass/fail/skipped status, skipped reason when applicable, and a redaction scan
result. Keep `.e2e/`, `*.local.yaml`, OTP values, JWTs, private keys, CLI
workspaces, App state roots, remote logs, screenshots, and device state out of
Git.

## Nightly and release runbook

Desktop nightly, Linux example:

```bash
DEV_OTP_PHONE="$DEV_OTP_PHONE" \
DEV_OTP_CODE="$DEV_OTP_CODE" \
AWIKI_CLI_BIN="../awiki-cli-rs2/target/release/awiki-cli" \
AWIKI_USER_SERVICE_URL="$AWIKI_USER_SERVICE_URL" \
AWIKI_MESSAGE_SERVICE_URL="$AWIKI_MESSAGE_SERVICE_URL" \
dart run tool/desktop_cli_peer_e2e_runner.dart \
  --platform linux \
  --service-base-url "$AWIKI_SERVICE_BASE_URL" \
  --did-domain "$AWIKI_DID_DOMAIN"
```

Mobile nightly:

```bash
dart run tests/e2e_test/harness/mobile_e2e_runner.dart \
  --config tests/e2e_test/configs/mobile.local.yaml
```

Before release, collect the private report paths from the desktop and mobile
runs, confirm `AGENT-SKIP-001` and `E2EE-SKIP-001` remain skipped with no gate
requirement, and record any release-owner waiver for unavailable devices,
accounts, or backend incidents.

## Flake and maintenance policy

- A failed real E2E must be classified as product regression, test bug,
  account/OTP problem, backend deployment problem, runner/device problem, or
  unknown. Do not hide a failure by only increasing timeout.
- A `feature` case may become `regression` after it passes in the target
  nightly environment three consecutive times and has stable redacted evidence.
- A `regression` case that repeatedly flakes must be fixed, quarantined to
  manual/nightly with a tracking issue, or explicitly waived by the release
  owner. It must not remain a silent required gate.
- Each new user-facing messaging, group, attachment, profile/settings, or
  onboarding feature should add or update one unit/widget test and decide
  whether an existing E2E case needs a new assertion or a new `feature` case.
- Keep skipped scenarios in the matrix. `AGENT-SKIP-001` and `E2EE-SKIP-001`
  are not implemented, not run, not added to PR/nightly/release gates, and do
  not require validation evidence in this E2E baseline.
