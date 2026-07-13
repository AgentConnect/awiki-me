# Repository Guidelines

## Project Structure & Module Organization
`lib/` contains the Flutter application. Domain contracts live in
`lib/src/domain/`, Dart service clients and persistence live in
`lib/src/data/`, and UI/providers live in `lib/src/presentation/`.
`tests/unit/` contains fast Dart logic, widget, provider, and fake-backed
harness tests. `tests/e2e/` contains E2E runners, configs, Flutter shim
implementations, and App + CLI peer/backend/device validation assets. Root
`integration_test/*.dart` files are Flutter-tooling shims only. Platform runners live under
`android/`, `ios/`, `macos/`, and `web/`. Static assets live in `assets/`.

## Build, Test, and Development Commands
Use Flutter/Dart tooling only. When installing dependencies, prefer the
Tsinghua pub mirror:

```bash
PUB_HOSTED_URL=https://mirrors.tuna.tsinghua.edu.cn/dart-pub flutter pub get
dart analyze
dart run tests/unit/runner.dart
flutter run
```

On the current Intel macOS development machine, routine AWiki Me Debug builds
must build only `x86_64-apple-darwin`, including the sibling
`awiki-cli-rs2/packages/awiki_im_core` native artifact. Do not compile ARM or a
universal macOS XCFramework during debugging unless the user explicitly asks
for ARM, universal, Release, or packaging output. Keep the Flutter App itself
as a Debug incremental build.

## Coding Style & Naming Conventions
Target Dart 3.8+ and Flutter 3.24+. Follow the repository lint rules in
`analysis_options.yaml`. Keep files and functions in `snake_case`, classes in
`PascalCase`, constants in `lowerCamelCase` or `SCREAMING_CAPS` only when that
matches the surrounding code. Keep widgets focused and move reusable business
logic into `lib/src/data/` or `lib/src/domain/`.

## Testing Guidelines
Tests use `flutter_test`. Name test files `*_test.dart` and keep tests in the
correct active test domain:

- `tests/unit/`: fast deterministic checks for Dart logic, mappers,
  application/data services, providers, widgets, and pure E2E harness planning
  with fakes. These must not require real devices, real services, OTP, or CLI
  subprocesses.
- `tests/e2e/`: E2E runners, configs, Flutter shim implementations, platform
  smoke tests, real App + CLI peer/backend/device flows, reports, and redaction
  rules. Root `integration_test/*.dart` files must stay thin Flutter tooling
  shims that import implementations from `tests/e2e/flutter/`.

Every new feature or behavior change must add or update the corresponding test
coverage in the same change. Prefer focused unit/provider/widget tests first;
add or update integration smoke when App bootstrap, routing, platform bindings,
native plugins, or visual surfaces change; add or update E2E scenarios or runner
assertions when the feature spans the real backend, CLI peer, account/OTP,
multi-client messaging, or mobile-device flows. If coverage cannot be added in
the current change, document the reason, skipped case ID, owner, and follow-up
in the relevant test docs or plan before merging.

For development/test OTP flows, use the shared non-production credentials below:

```bash
DEV_OTP_PHONE=+8610022229999
DEV_OTP_CODE=987580
```

## Multi-Platform Safety
AWiki Me supports Android, iOS, macOS, and web. When fixing or changing one
platform, keep the diff scoped to that platform plus shared Dart code that is
strictly required. Do not modify another platform runner, generated registrant,
Pod/Gradle/Xcode metadata, entitlements, bundle IDs, signing settings, or
runtime behavior unless the task explicitly requires it. If a tool regenerates
unrelated platform files, inspect and revert those unrelated changes before
committing.

## ANP SDK Direction
The app is Dart-only. Do not add Python CLI tools, Python dependency manifests,
legacy credential migrations, or old RPC gateway paths. Account creation,
DID-WBA authentication, message proof generation, IM, and User Service calls
must use the Dart ANP SDK and Dart service clients.

## Security & Configuration Tips
Do not commit real credentials, generated local state, signing keys, or custom
runtime configuration. Account credentials are e1 DID-only and stored through
the app's Dart account service and platform secure storage.
