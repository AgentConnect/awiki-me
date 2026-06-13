# Testing AWiki Me

AWiki Me uses Flutter and Dart tooling only. Keep tests close to the feature
under change, and prefer fast deterministic tests before adding device or
backend-dependent coverage.

## Test Layers

### Unit tests

Use unit tests for pure Dart behavior and service boundaries:

- domain entities, formatters, and thread id helpers;
- application services and Riverpod state controllers;
- `lib/src/data/im_core/` adapter and mapper behavior;
- Dart service clients, auth retry, local stores, and error mapping;
- E2E runner config parsing and dry-run command generation.

Run focused unit tests with:

```bash
flutter test test/application test/data test/im_core test/agents
```

### Widget tests

Use widget tests for user-visible App flows with fake services from
`test/test_support.dart` or a small helper under `test/support/`.

Good widget-test targets are onboarding, settings, chat, conversation lists,
friends, groups, profiles, agents, responsive layout, empty states, loading
states, and error states.

Run all unit and widget tests with:

```bash
flutter test
```

### Integration tests

Flutter integration tests live in `integration_test/`. Keep them as smoke tests
for Flutter engine, platform binding, bootstrap, and a few high-value App paths.
Do not use integration tests to reimplement message-service wire validation,
WebSocket internals, E2EE internals, or SDK native ABI checks that belong in
`awiki-cli-rs2` or AWiki system tests.

The existing native `AwikiImCore.open` smoke is macOS-only. The current
`awiki_im_core` plugin declares Android, iOS, and macOS native support; it does
not declare Linux native support. This repository also does not currently have
a `linux/` runner. Do not make Linux desktop integration a required gate until
both the Flutter Linux runner and SDK native support are intentionally added.

Useful commands:

```bash
flutter test integration_test
flutter test integration_test -d macos
```

For future Linux desktop integration on Ubuntu, the host normally needs Flutter
Linux desktop prerequisites and an X server:

```bash
sudo apt update
sudo apt install -y clang cmake ninja-build pkg-config libgtk-3-dev liblzma-dev libsecret-1-dev xvfb
flutter config --enable-linux-desktop
flutter devices
xvfb-run -a flutter test integration_test -d linux
```

Only use the Linux command as a required gate after this repo has a Linux
runner and every integration test in that gate avoids unsupported native SDK
paths or the SDK has Linux native support.

The implementation plan for adding a Linux Desktop runner, Linux native
`awiki_im_core` support, and a real App + CLI peer E2E topology is documented
in [e2e/linux-desktop-cli-peer-e2e/plan.md](e2e/linux-desktop-cli-peer-e2e/plan.md).

### Mobile E2E

Mobile E2E is driven by `tool/e2e_runner.dart` and Maestro flows under
`.maestro/`. It covers the real two-device smoke path:

- build the debug app with `AWIKI_E2E=true`;
- install on two iOS simulators or Android devices/AVDs;
- log in both accounts;
- send A -> B and B -> A messages;
- write a local timing report under `.e2e/reports/`.

Dry-run is the safe CI-friendly check:

```bash
dart run tool/e2e_runner.dart --config awiki_e2e.example.yaml --dry-run
```

Real E2E requires local configuration, two devices or simulators, Maestro, and
a reachable non-production backend:

```bash
# Copy the example first, then edit the local file with two isolated
# non-production accounts and the device IDs/names for your host.
cp awiki_e2e.example.yaml awiki_e2e.local.yaml
dart run tool/e2e_runner.dart --config awiki_e2e.local.yaml
```

Never commit `awiki_e2e.local.yaml`, `.e2e/`, real credentials, generated local
state, or device-specific reports. The example config is documentation only.
The runner writes `timings.json` and Maestro logs under
`.e2e/reports/<runId>/`; record the path in manual/nightly evidence, but keep
the files local.

For Android, configure either two already-running `adb` serials under
`device.android.ids` or two independent AVD names under
`device.android.avdNames`. For iOS, configure two simulator UDIDs under
`device.ios.ids` or two simulator names under `device.ios.names`.
Real-device E2E should remain a manual, nightly, or release gate unless the
project has stable devices, OTP test accounts, Maestro, and backend isolation.

## Recommended Local Gate

Run this before handing off App changes:

```bash
PUB_HOSTED_URL=https://mirrors.tuna.tsinghua.edu.cn/dart-pub flutter pub get
dart analyze
flutter test
dart run tool/e2e_runner.dart --config awiki_e2e.example.yaml --dry-run
```

## CI Gate

The GitHub Actions quick gate mirrors the local required checks:

```bash
flutter pub get
dart analyze
flutter test
dart run tool/e2e_runner.dart --config awiki_e2e.example.yaml --dry-run
```

This gate intentionally does not run Linux desktop integration or real-device
E2E. Linux desktop integration becomes a required CI step only after this repo
adds a `linux/` runner and the native SDK paths used by the integration suite
are supported on Linux. Real Android/iOS E2E belongs in a manual, nightly, or
release gate unless stable devices, Maestro, non-production accounts, and
backend isolation are available.

Run integration and real-device E2E when the platform and devices are available,
and record pass/fail evidence plus any report paths in the handoff or release
notes.
