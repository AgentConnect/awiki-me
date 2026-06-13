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
for Flutter engine, platform binding, bootstrap, native SDK loading, and a few
high-value App paths. Do not use integration tests to reimplement
message-service wire validation, WebSocket internals, E2EE internals, or SDK
native ABI checks that belong in `awiki-cli-rs2` or AWiki system tests.

Useful macOS commands:

```bash
flutter test integration_test
flutter test integration_test -d macos
```

Linux desktop integration is supported through the `linux/` runner. Ubuntu
hosts need Flutter Linux desktop prerequisites and an X server; CI and servers
without a real desktop should use `xvfb-run`:

```bash
sudo apt update
sudo apt install -y clang cmake ninja-build pkg-config libgtk-3-dev liblzma-dev libsecret-1-dev xvfb
flutter config --enable-linux-desktop
flutter devices
```

Fast Linux desktop smoke:

```bash
xvfb-run -a flutter test integration_test/app_smoke_test.dart -d linux
```

This uses fake App bootstrap and proves the Linux runner, Flutter shell,
platform binding, App shell, onboarding shell, and basic widget tree can start
under Xvfb. It does not test real login, real native SDK state, networking,
secure storage, User Service, Message Service, or CLI peer behavior.

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

### Desktop App + CLI Peer E2E

`integration_test/desktop_cli_peer_smoke_test.dart` is the one Desktop
App+CLI peer smoke. It starts the real App bootstrap, prepares or uses a real
App test identity, uses `awiki-cli-rs2` as the peer client, and checks one
App -> CLI message plus one CLI -> App message with a unique run id.

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

Use the same test on macOS:

```bash
flutter test integration_test/desktop_cli_peer_smoke_test.dart -d macos
```

Use this Linux headless command when the runner starts Flutter:

```bash
xvfb-run -a flutter test integration_test/desktop_cli_peer_smoke_test.dart -d linux
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
xvfb-run -a flutter test integration_test/app_smoke_test.dart -d linux
xvfb-run -a flutter test integration_test/im_core_open_smoke_test.dart -d linux
```

## CI Gate

The GitHub Actions quick gate mirrors the local required checks:

```bash
flutter pub get
dart analyze
flutter test
dart run tool/e2e_runner.dart --config awiki_e2e.example.yaml --dry-run
xvfb-run -a flutter test integration_test/app_smoke_test.dart -d linux
xvfb-run -a flutter test integration_test/im_core_open_smoke_test.dart -d linux
```

This gate intentionally does not run real backend + OTP Desktop App+CLI peer
E2E or real-device E2E. Linux desktop app/native smoke is deterministic and can
run in PR CI after Linux desktop dependencies and the sibling
`awiki-cli-rs2` SDK repo are available. The workflow checks out
`awiki-cli-rs2` beside this repo because `pubspec.yaml` uses
`../awiki-cli-rs2/packages/awiki_im_core`; set `AWIKI_CLI_RS2_REF` when CI must
use a non-default SDK branch, and set `AWIKI_CI_READ_TOKEN` if the sibling repo
requires a token. That SDK ref must include Linux native SDK support and the
Desktop CLI peer endpoint config support used by the manual E2E runner.
Real Desktop App+CLI peer E2E and real Android/iOS E2E belong in manual,
nightly, or release gates unless stable devices, Maestro, non-production
accounts, and backend isolation are available.

Run integration and real-device E2E when the platform and devices are available,
and record pass/fail evidence plus any report paths in the handoff or release
notes.
