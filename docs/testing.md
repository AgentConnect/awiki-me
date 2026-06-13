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
service config, CLI build, CLI isolated workspace, timing reports, and App
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
environment variable names only:

```bash
dart run tests/e2e_test/harness/desktop_e2e_runner.dart \
  --platform=macos \
  --scenario=agent-im-delegated-message \
  --config tests/e2e_test/configs/agent_im_delegated.example.yaml \
  --dry-run
```

Copy `tests/e2e_test/configs/agent_im_delegated.example.yaml` to
`tests/e2e_test/configs/agent_im_delegated.local.yaml` for local real runs.
Do not commit local configs, generated CLI workspaces, reports, OTP values,
tokens, private keys, or remote log captures.

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
