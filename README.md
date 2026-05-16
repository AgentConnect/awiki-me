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
flutter test
flutter run
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
- `test/`: Dart unit and widget tests
- `android/`, `ios/`, `macos/`, `web/`: platform runners

## App Icons

```bash
dart run flutter_launcher_icons
```

The icon source lives at `assets/branding/awiki-me-logo.png`.
