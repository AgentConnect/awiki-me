# AWiki Me Flutter App

AWiki Me is a Dart-only Flutter messaging client built on the ANP Dart SDK.
Account creation, DID-WBA authentication, User Service calls, IM, and message
proof generation all run through Dart code.

## Requirements

- Flutter 3.24.0 or newer with Dart 3.8.0 or newer

## Getting Started

```bash
PUB_HOSTED_URL=https://mirrors.tuna.tsinghua.edu.cn/dart-pub flutter pub get
dart analyze
dart run tests/unit/runner.dart
flutter run
```

## Testing

The testing strategy is documented in [docs/testing.md](docs/testing.md).

Recommended local gate:

```bash
PUB_HOSTED_URL=https://mirrors.tuna.tsinghua.edu.cn/dart-pub flutter pub get
dart analyze
dart run tests/unit/runner.dart
dart run tests/e2e/runner.dart --case smoke
```

The test gates use the operating system SQLite library through Dart native
asset hooks, so they do not need to download a prebuilt SQLite dylib from
GitHub. macOS includes SQLite. Linux machines should install `libsqlite3-dev`
or the equivalent system package.

Full real-backend E2E uses `tests/e2e/configs/e2e.local.yaml` by default:

```bash
cp tests/e2e/configs/e2e.example.yaml tests/e2e/configs/e2e.local.yaml
dart run tests/e2e/runner.dart --case full
```

The local YAML is ignored by Git and should hold the test backend URL, DID
domain, OTP, App/CLI peer handles, and `awiki-cli` binary path.

## Backend Environment

The app reads a single backend root from `AWIKI_BASE_URL` and derives the
default user-service, message-service, mail-service, DID domain, ANP endpoint,
and daemon download root from it.

```bash
flutter run --dart-define=AWIKI_BASE_URL=https://awiki.info
```

Production defaults to `https://awiki.info`. Future online test builds can switch
to:

```bash
flutter run --dart-define=AWIKI_BASE_URL=https://anpclaw.com
```

Advanced overrides are available when a service needs to be split from the main
domain:

```text
AWIKI_USER_SERVICE_URL
AWIKI_MESSAGE_SERVICE_URL
AWIKI_MAIL_SERVICE_URL
AWIKI_DID_DOMAIN
AWIKI_ANP_SERVICE_URL
AWIKI_ANP_SERVICE_DID
AWIKI_DAEMON_DOWNLOAD_BASE_URL
```

## Message Sync

AWiki Me keeps message views local-first and delegates reliable recovery to the
Flutter SDK / Rust `im-core` boundary. `MessageSyncCoordinator` schedules
`syncDelta` on startup, foreground resume, reconnect, and realtime dirty/gap
signals, then refreshes local projections after a successful SDK sync. Chat
opening is memory/local-first: it renders the in-memory tail or recent local
projection before backgrounding `syncThreadAfter` with a thread-local
`afterServerSeq`. The performance E2E gate records both CLI-to-App open
first-paint latency and the later thread-after/history reconcile timings so the
click path cannot be proven only by a remote history query.

The App must not read or write the global reliable checkpoint, pass
`since_event_seq`, manually advance `next_event_seq`, build raw `/im/rpc`
`sync.*` payloads, or treat realtime `sync` hints as checkpoint commits. Those
remain `im-core` Rust/SQLite responsibilities.

## Building on macOS with Xcode

Before opening the project in Xcode, generate the CocoaPods support files:

```bash
scripts/bootstrap_macos.sh
open macos/Runner.xcworkspace
```

Use `Runner.xcworkspace`, not `Runner.xcodeproj`. If Xcode reports
`Unable to load contents of file list: '/Target Support Files/Pods-Runner/...'`,
the generated `macos/Pods` support files are missing or CocoaPods is not on
`PATH`; rerun the bootstrap script.

Local macOS debug/profile builds are usually ad-hoc signed. To avoid a
successful backend registration surfacing as a registration failure because a
Keychain write failed, debug/profile builds store account credentials in
`awiki_me_credentials.json` under the app support directory; release builds still
use platform secure storage.

## Project Structure

- `lib/`: application, domain, data, and presentation code
- `assets/`: bundled branding and UI assets
- `tests/unit/`: unit, widget, provider, and pure Dart tests
- `tests/e2e/`: desktop E2E runner, Flutter platform test implementations, and support code
- `integration_test/`: Flutter tooling shims only
- `android/`, `ios/`, `macos/`, `web/`: platform runners

## App Icons

```bash
dart run flutter_launcher_icons
```

The icon source lives at `assets/branding/awiki-me-logo.png`.
