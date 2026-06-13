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
flutter test tests/unit_test
flutter run
```

## Testing

The testing strategy is documented in [docs/testing.md](docs/testing.md).

Recommended local gate:

```bash
PUB_HOSTED_URL=https://mirrors.tuna.tsinghua.edu.cn/dart-pub flutter pub get
dart analyze
flutter test tests/unit_test
dart run tests/e2e_test/harness/mobile_e2e_runner.dart --config tests/e2e_test/configs/mobile.example.yaml --dry-run
dart run tests/e2e_test/harness/desktop_e2e_runner.dart --platform=macos --dry-run
```

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
- `tests/unit_test/`: Dart unit, widget, provider, and harness unit tests
- `tests/integration_test/`: Flutter app/native/platform smoke tests
- `tests/e2e_test/`: end-to-end harnesses, configs, scenarios, and Maestro flows
- `android/`, `ios/`, `macos/`, `web/`: platform runners

## App Icons

```bash
dart run flutter_launcher_icons
```

The icon source lives at `assets/branding/awiki-me-logo.png`.
