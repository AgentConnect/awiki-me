# Getting Started with AWiki Me

[English](getting-started.md) | [简体中文](getting-started.zh-CN.md)

This guide is for early users who want to install and try AWiki Me and for developers who need to run the client from source.

## 1. Current availability

Current release and validation priorities:

- macOS arm64 and x64
- Android arm64

iOS supports development builds, but the default packaging flow does not produce an iOS release. Web is currently unavailable because the `awiki_im_core` Web entry point is a runtime stub.

## 2. Installing a release

The repository can package macOS DMGs and an Android arm64 APK. The public README must link only official artifacts that have been verified, remain available, and have a clearly documented signing status.

Release owners should use this structure after confirming the URLs:

```markdown
- [Download for macOS Apple Silicon](<official-url>)
- [Download for macOS Intel](<official-url>)
- [Download the Android arm64 APK](<official-url>)
- [Read the release notes](<release-notes-url>)
```

Do not link:

- temporary GitHub Actions artifacts;
- unsigned or ad-hoc-signed macOS release packages;
- development test APKs; or
- internal URLs and downloads that require organization access.

## 3. Running from source

### 3.1 Requirements

- Flutter 3.41.0 or newer
- Dart 3.8.0 or newer
- A sibling `awiki-cli-rs2` checkout compatible with the current app version
- CocoaPods for iOS and macOS development
- Android SDK and a working device or emulator for Android development
- System SQLite and desktop dependencies for Linux desktop/E2E runners; Linux is not currently a public AWiki Me product target

Check the environment first:

```bash
flutter doctor -v
dart --version
```

### 3.2 Directory layout

```text
workspace/
├── awiki-cli-rs2/
└── awiki-me/
```

`awiki-me/pubspec.yaml` loads the SDK through this relative path:

```text
../awiki-cli-rs2/packages/awiki_im_core
```

The repositories therefore cannot be placed in unrelated directories or use incompatible branches or commits.

### 3.3 macOS

```bash
cd awiki-cli-rs2
scripts/flutter/build-sdk-native.sh --macos-only

cd ../awiki-me
flutter pub get
dart analyze
dart run tests/unit/runner.dart
dart run tests/e2e/runner.dart --case smoke
flutter run --debug -d macos
```

To use Xcode:

```bash
scripts/prepare_macos_build.sh
open macos/Runner.xcworkspace
```

Open `Runner.xcworkspace`, not `Runner.xcodeproj`.

### 3.4 Android

```bash
cd awiki-cli-rs2
scripts/flutter/build-sdk-native.sh --android-only

cd ../awiki-me
flutter pub get
flutter devices
flutter run -d <android-device-id>
```

The current release artifact targets Android arm64. Confirm the device architecture and Android SDK configuration locally.

### 3.5 iOS

```bash
cd awiki-cli-rs2
scripts/flutter/build-sdk-native.sh --ios-only

cd ../awiki-me
flutter pub get
cd ios && pod install && cd ..
flutter build ios --simulator --debug
open -a Simulator
flutter devices
flutter run --debug -d <ios-simulator-id>
```

To use Xcode:

```bash
open ios/Runner.xcworkspace
```

Open `Runner.xcworkspace`, not `Runner.xcodeproj`. Simulator builds do not require Apple Developer signing. To run on a physical device, select your Team for the Runner target in Xcode and keep automatic signing enabled.

Describe iOS as a development target, not a verified public release platform. The project supports iOS 13+, iPhone and iPad, the `UIScene` lifecycle, Debug/Profile/Release CocoaPods configurations, and `awiki_im_core` arm64 device plus arm64/x86_64 simulator slices. A release still requires physical-device networking, background behavior, secure-storage, and distribution validation.

### 3.6 Optional dependency mirror

When dependency access is restricted, the repository recommends:

```bash
PUB_HOSTED_URL=https://mirrors.tuna.tsinghua.edu.cn/dart-pub flutter pub get
```

Public documentation must also keep the standard `flutter pub get` path that does not depend on a regional mirror.

## 4. First launch

1. Start the app.
2. Use the default AWiki tenant on the login screen, or open the secondary tenant switcher.
3. Register a new identity or sign in with an existing one.
4. Wait for Storage Scope, SecretVault, and active-identity validation to complete.
5. Open the Messages page.

Debug/Profile and installed Release apps use different application identities, local data roots, and Keychain services. Development builds must not read or modify production data.

## 5. First meaningful success

Use two test identities, or one app identity and one CLI peer:

1. Open Contacts in AWiki Me.
2. Enter the peer's complete handle or DID.
3. Open a Direct conversation.
4. Send a text message.
5. Confirm that delivery state, conversation preview, and timeline update immediately.
6. Reply from the peer.
7. Confirm that unread/read state and realtime/sync recovery behave correctly.

Then validate, as needed:

- sending a file or image attachment;
- creating or joining a group;
- using an `@` mention in a group message; and
- opening the Agent page to inspect Daemon or Agent status.

## 6. Custom tenants

Each tenant has:

- a display name;
- a backend base URL;
- a DID host; and
- an immutable `storage_scope_id`.

The tenant display name, backend URL, and DID host are not local secure-storage locators. An immutable UUID scope isolates each tenant's local paths, SecretVault, and Core runtime.

Important boundaries:

- Changing the DID host should create a new tenant and scope.
- Do not rewrite backend routing in place after local data exists.
- Fully release the old realtime, Core, and SQLite runtime before switching tenants.
- Agent/Daemon features are currently enabled only for an exact realm allowlist.

## 7. Troubleshooting

### `awiki_im_core` cannot be found

Confirm that the sibling directory exists:

```bash
ls ../awiki-cli-rs2/packages/awiki_im_core/pubspec.yaml
```

Also confirm that both repositories use compatible versions.

### macOS CocoaPods files are missing

```bash
scripts/prepare_macos_build.sh
open macos/Runner.xcworkspace
```

### The native SDK has not been generated

Run the target platform build in `awiki-cli-rs2`:

```bash
scripts/flutter/build-sdk-native.sh --macos-only
# or --android-only / --ios-only / --linux-only
```

### The app starts, but self-hosted Agent features do not work

Basic tenant connectivity and Agent/Daemon features have separate boundaries. The current Agent realm allowlist is:

- `awiki.ai`
- `awiki.info`
- `anpclaw.com`

Other domains fail closed and do not call Agent backend APIs. See [Compatibility](compatibility.md).

### The Web build succeeds but fails at runtime

The current Flutter Web entry point in `awiki_im_core` is a stub that throws `UnsupportedError`. Do not interpret a successful Web build as product availability.
