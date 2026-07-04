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
daemon download root, package channel, update manifest, and release page from
it. For packaging, `scripts/package_app.config` is the single domain switch:
set `AWIKI_DOMAIN="awiki.info"` or `AWIKI_DOMAIN="awiki.ai"` and leave the
advanced overrides empty.

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
AWIKI_STATE_NAMESPACE
AWIKI_ANP_SERVICE_URL
AWIKI_ANP_SERVICE_DID
AWIKI_DAEMON_DOWNLOAD_BASE_URL
AWIKI_PACKAGE_CHANNEL
AWIKI_UPDATE_MANIFEST_URL
AWIKI_RELEASES_URL
```

## Packaging

The installer package entrypoint is:

```bash
scripts/package_app.sh
```

Package settings live in `scripts/package_app.config`. The script accepts no
arguments and does not read package settings from environment variables. For
normal packaging, edit only `AWIKI_DOMAIN`; keep `PACKAGE_CHANNEL="test"` for
installable non-store packages. The script derives `AWIKI_BASE_URL`,
`AWIKI_DID_DOMAIN`, `AWIKI_ANP_SERVICE_URL`,
`AWIKI_DAEMON_DOWNLOAD_BASE_URL`, `AWIKI_UPDATE_MANIFEST_URL`, and
`AWIKI_RELEASES_URL` from that domain unless an advanced override is set. The
channel only separates output directories, file names, and `latest.json`; it
does not control store release status or code signing.

The script always builds release artifacts for Android arm64, macOS arm64, and
macOS x64. It also rebuilds the native SDK artifacts before packaging.

The current checked-in config builds the installable online test package:

```text
PACKAGE_CHANNEL="test"
AWIKI_DOMAIN="awiki.ai"
```

For a future stable distribution track, update the same config file, for
example:

```text
PACKAGE_CHANNEL="stable"
AWIKI_DOMAIN="awiki.info"
```

The script writes artifacts and `latest.json` under:

```text
dist/<channel>/<version>/
dist/<channel>/latest.json
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

Chat presentation is intentionally one-way. `ConversationListProvider` owns the
recent-conversation list and badge state; `ChatThreadsProvider` owns message
threads. `ChatPage` renders the selected thread and may acknowledge a visible
conversation as read, but it must not treat conversation-list summary changes as
a signal to pull thread history. Necessary thread reconciliation is limited to
opening a conversation, thread patch version-gap repair, and thread patch stream
repair/re-subscription. The macOS chat header no longer exposes a manual
conversation refresh button.

The App must not read or write the global reliable checkpoint, pass
`since_event_seq`, manually advance `next_event_seq`, build raw `/im/rpc`
`sync.*` payloads, or treat realtime `sync` hints as checkpoint commits. Those
remain `im-core` Rust/SQLite responsibilities.

## Agent Inventory Refresh

The Agents tab is local-first after the first load. Entering the left-rail
Agents tab calls `ensureLoaded()`, which reuses the in-memory/cache-backed
inventory for the active account instead of forcing a remote `list_agents`
request on every tab re-entry. Explicit retry, session activation, foreground
resume, and realtime reconnect still use the authenticated background refresh
path when fresh inventory is required. Daemon status remains separate: the
manual refresh button sends a status query to the selected daemon, while
realtime agent-control payloads update the page automatically. Lifecycle-triggered
auto-sync start/stop is scheduled outside widget build/dispose so Riverpod state
changes do not occur while Flutter is finalizing the widget tree.

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

The macOS Info.plist intentionally omits `SUPublicEDKey` until release CI owns a
real Sparkle EdDSA public key and matching signed appcast artifacts. Do not ship
an empty `SUPublicEDKey`; Sparkle treats the empty value as an invalid key and
logs `The provided EdDSA key could not be decoded.` The Sparkle feed URL in
`macos/Runner/Configs/AppInfo.xcconfig` uses `$()` between the two slashes so
Xcode does not parse the URL as an xcconfig comment.

Local macOS debug/profile builds are usually ad-hoc signed. To avoid a
successful backend registration surfacing as a registration failure because a
Keychain write failed, debug/profile builds store account credentials in
`awiki_me_credentials.json` under the app support directory; release builds still
use platform secure storage.

The identity vault root key and device id still use encrypted macOS Keychain
storage outside explicit `AWIKI_E2E_APP_STATE_ROOT` runs. Local/debug builds use
the login Keychain rather than the Data Protection Keychain so they can run
without a provisioning profile. New macOS writes go through the AWiki native
Keychain bridge, which stores the item with an ACL that trusts the current
`.app` bundle path; this avoids repeatedly asking for authorization when the
same local debug App path is restarted or incrementally rebuilt. Values that were
written by the older `flutter_secure_storage` path are read as a legacy fallback
and migrated into the native bridge after the user authorizes access once, while
also scheduling a best-effort ACL repair for the old item. The plugin's Data
Protection Keychain mode still requires Keychain Sharing entitlements and a valid
development/release signing identity; if that entitlement is missing, runtime
writes fail with OSStatus `-34018` (`errSecMissingEntitlement`), and if the
entitlement is present without a usable signing profile, local Flutter builds
fail before launch. After changing macOS signing, entitlements, or
secure-storage options, run
`flutter test --no-pub integration_test/secure_storage_smoke_test.dart -d macos`
to prove the signed runner can write, read, and delete a secure-storage value.

## Identity Secret Storage

AWiki Me opens the Flutter SDK / Rust `im-core` boundary with identity
`VaultRequired` options. DID private keys, E2EE static key material, auth/JWT
state, and daemon subkey package persistence are owned by `im-core`; the App
only supplies the no-prompt vault root key and stable host context.

Production and ordinary custom-state-root runs use `SecureAppKeyValueStore`
backed by `flutter_secure_storage` for the App-local vault root key and device
id. The App state namespace owns the vault directory:

```text
<app support>/im-core/<namespace>/identity-vault
vaultWorkspaceId = awiki-me-<namespace>
deviceId = app-device-<stable-random>
```

Only explicit E2E runs with `AWIKI_E2E_APP_STATE_ROOT` use the private file test
provider `awiki_me_im_core_vault.json`; ordinary `appStateRoot` overrides do not
move the vault root key into JSON. The test file may contain a base64 test root
key and must remain local/untracked.

When activating an identity, AWiki Me checks the identity vault before switching
the active SDK client or writing the active session:

```text
identityVaultStatus -> migrateIdentityVault when legacy metadata is absent -> verifyIdentityVault -> switchIdentity -> ensureSession
```

If existing vault metadata is present but cannot be selected/verified, the App
fails closed instead of re-sealing legacy plaintext under a new root key. The
App bootstrap path can still receive a daemon subkey private key plaintext DTO;
that transport exception is temporary and separate from local persistence.

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
