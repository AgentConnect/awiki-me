# Testing AWiki Me

AWiki Me uses Flutter and Dart tooling only. Tests are organized into three
parallel domains so unit, integration, and end-to-end concerns do not drift into
one another:

```text
tests/unit_test/          # fast unit/widget/provider tests with fakes
tests/integration_test/   # Flutter engine, platform binding, and native smoke tests
tests/e2e_test/           # real App + CLI peer/backend harnesses, configs, reports
```

## Unit tests

`tests/unit_test/` contains deterministic tests that do not require a real device,
real backend, or real `awiki-cli` subprocess. This includes pure Dart logic,
application/data services with fakes, widget/provider tests, and pure E2E
harness parser/planning tests.

Run:

```bash
flutter test tests/unit_test
```

Unit fakes live under `tests/unit_test/support/` and `tests/unit_test/test_support.dart`.
Integration-only bootstraps live under `tests/integration_test/support/`. Keep
production code free of test-only mocks.

## Integration tests

`tests/integration_test/` contains Flutter integration smoke test implementations. These may run
against a desktop target such as macOS or Linux, but they should not implement a
real multi-client backend E2E flow. Because Flutter's `integration_test` plugin
only treats root-level `integration_test/` files as device integration entrypoints,
this repo keeps tiny root shims under `integration_test/`; do not put test
implementation there.

Current groups:

- `tests/integration_test/app/` — App shell smoke with fake bootstrap.
- `tests/integration_test/native/` — native SDK/plugin smoke such as
  `AwikiImCore.open`.
- `tests/integration_test/support/` — integration-only helpers.

macOS examples using the Flutter-tooling shims:

```bash
flutter test integration_test/app_smoke_test.dart -d macos
flutter test integration_test/im_core_open_smoke_test.dart -d macos
```

Future Linux examples, after this repo has a Linux runner and
`awiki_im_core` Linux native support:

```bash
xvfb-run -a flutter test integration_test/app_smoke_test.dart -d linux
xvfb-run -a flutter test integration_test/im_core_open_smoke_test.dart -d linux
```

The current `awiki_im_core` plugin declares Android, iOS, and macOS native
support. Linux native integration must remain non-required until the Linux
runner, plugin declaration, loader, and `.so` packaging are intentionally added.

## End-to-end tests

`tests/e2e_test/` contains end-to-end harnesses, example configs, mobile Maestro flows,
and future scenarios. E2E may use the real App, `awiki-cli-rs2` as a CLI peer,
and a reachable non-production backend.

Structure:

```text
tests/e2e_test/
  harness/
    desktop_e2e_runner.dart    # shared desktop runner: macOS/Linux platform arg
    mobile_e2e_runner.dart     # iOS/Android Maestro runner
  configs/
    mobile.example.yaml
  mobile/maestro/
  scenarios/
```

### Desktop E2E

The desktop runner is shared by macOS and Linux. It reuses one architecture for
service config, CLI build, CLI peer workspace, timing reports, and App
dart-defines. Only the platform adapter differs:

- macOS: checks `xcrun`, runs `flutter test -d macos`.
- Linux: checks Linux desktop tooling and runs through `xvfb-run`.

macOS dry-run:

```bash
source .e2e/macos.env
/Users/cs/development/flutter/bin/dart run tests/e2e_test/harness/desktop_e2e_runner.dart \
  --platform=macos \
  --dry-run
```

Agent IM delegated-message dry-run uses the same desktop runner and adds a
scenario/config layer. The checked-in config contains placeholders and
environment variable names only. The runner writes `scenario-plan.json`,
`cli-peer-plan.json`, and `agent-im-scenario-result.json`; the CLI plan shows the
configured `awiki-cli-rs2` peer workspace, refresh/status/recover/register commands, and
ordinary `msg send` command with only environment variable names for phone/OTP:

```bash
dart run tests/e2e_test/harness/desktop_e2e_runner.dart \
  --platform=macos \
  --scenario=agent-im-delegated-message \
  --config tests/e2e_test/configs/agent_im_delegated.example.yaml \
  --dry-run
```


Agent IM App bootstrap integration smoke exercises the App-side bootstrap hook
without a real backend. The implementation lives under `tests/integration_test/`
and the root `integration_test/` file is only a Flutter tooling shim. The smoke
uses the production `DefaultAgentControlService` with fake ports, verifies that
`awiki.daemon.bootstrap.v1` is sent through the App payload path, and writes no
private package, token, OTP, or raw phone values to report-shaped output:

```bash
flutter test integration_test/agent_im_delegated_message_e2e_test.dart -d macos
```

Copy `tests/e2e_test/configs/agent_im_delegated.example.yaml` to
`tests/e2e_test/configs/agent_im_delegated.local.yaml` for local real runs.
Use a persistent ignored `cliPeer.workspaceRoot` such as
`.e2e/agent-im/cli-peer` for the peer account. Real Agent IM CLI peer runs first
reuse that workspace through `id refresh-token` and `id status`; only the first
bootstrap or a broken workspace requires the peer account env vars named by the
local config for OTP-based `id recover` or `id register`. The harness also points the CLI
process `HOME` at `<cliPeer.workspaceRoot>/home` so the latest `awiki-cli-rs2`
does not inspect or import legacy `awiki-agent-id-message` state from the
developer's real home directory. Do not commit local configs, generated CLI
workspaces, reports, OTP values, tokens, private keys, or remote log captures.

When `remote.collectLogs` is enabled in a non-dry-run Agent IM scenario, the
runner also writes `remote-evidence-result.json` plus `remote-*.log` files with
redacted `ssh ali` health/log summaries filtered by runId.

Real Agent IM delegated-message runs are a P0 gate for the App ↔ remote
Daemon/Hermes loop. A pass requires both local App evidence and remote daemon
evidence:

- the App sends `awiki.daemon.bootstrap.v1` through the real IM payload path;
- the CLI peer from `awiki-cli-rs2` sends an ordinary message to the App user;
- remote evidence observes `daemon_bootstrap_received`,
  `delegated_key_imported`, `hermes_agent_ready`, `cli_message_received`,
  `hermes_runtime_finished`, and `summary_return_sent`;
- the App receives hidden, non-renderable `awiki.message.sync.v1`
  `runtime_status` / `runtime_final` payloads instead of normal chat bubbles.

Latest verified P0 run on `awiki.info`: `20260614T024413341Z`, message
`msg_agent_im_20260614T024413341Z`, with `AIM-E2E-001`, `AIM-E2E-002`, and
`AIM-E2E-006` passing. Follow-up scenarios for daemon restart/cursor recovery,
E2EE opaque boundaries, delegated DID revoke behavior, and unknown payload
negative injection remain P1/P2 and must not be described as completed by this
P0 gate.

Agent IM bootstrap is intentionally behind a temporary App-side feature flag.
Normal App builds default to disabled (`AWIKI_AGENT_IM_ENABLED=false`), so
`DefaultAgentControlService.ensureMessageAgentBootstrap` becomes a no-op and the
App does not send delegated-key bootstrap payloads. To reopen the feature for
manual App testing, build/run with `--dart-define=AWIKI_AGENT_IM_ENABLED=true`.
The dedicated E2E probe/scenario enables the flag explicitly so the P0 gate can
still be run without deleting or reworking Agent IM code.

macOS real smoke:

```bash
source .e2e/macos.env
/Users/cs/development/flutter/bin/dart run tests/e2e_test/harness/desktop_e2e_runner.dart \
  --platform=macos
```

For compatibility, the old wrapper remains available:

```bash
/Users/cs/development/flutter/bin/dart run tool/macos_e2e_runner.dart --dry-run
```

Reports are written under `.e2e/<platform>/reports/<runId>/`. The OTP variables
are detected for later live auth flows but are not printed or persisted by the
runner.

### Mobile E2E

Mobile E2E is driven by `tests/e2e_test/harness/mobile_e2e_runner.dart` and Maestro
flows under `tests/e2e_test/mobile/maestro/`. It covers the real two-device smoke path
for iOS/Android.

Dry-run:

```bash
dart run tests/e2e_test/harness/mobile_e2e_runner.dart \
  --config tests/e2e_test/configs/mobile.example.yaml \
  --dry-run
```

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
/Users/cs/development/flutter/bin/dart run tests/e2e_test/harness/desktop_e2e_runner.dart \
  --platform=macos \
  --dry-run
```

## CI gate

The quick CI gate should stay deterministic and not depend on real devices or a
live backend:

```bash
flutter pub get
dart analyze
flutter test tests/unit_test
dart run tests/e2e_test/harness/mobile_e2e_runner.dart \
  --config tests/e2e_test/configs/mobile.example.yaml \
  --dry-run
```

Real desktop/mobile E2E belongs in manual, nightly, or release gates unless the
project has stable devices, backend isolation, OTP test accounts, and Linux
native support available.
