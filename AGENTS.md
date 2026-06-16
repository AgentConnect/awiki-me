# Repository Guidelines

## Project Structure & Module Organization
`lib/` contains the Flutter application. Domain contracts live in
`lib/src/domain/`, Dart service clients and persistence live in
`lib/src/data/`, and UI/providers live in `lib/src/presentation/`.
`tests/unit_test/` contains fast Dart logic, widget, provider, and fake-backed
harness tests. `tests/integration_test/` contains Flutter app/native/platform
smoke implementations that prove the App can start and integrate with the
Flutter engine or native plugins, but should not own real multi-client backend
flows. `tests/e2e_test/` contains end-to-end harnesses, configs, scenarios, and
Maestro flows for real App + CLI peer/backend/device validation. Root
`integration_test/*.dart` files are Flutter-tooling shims only. Platform runners live under
`android/`, `ios/`, `macos/`, and `web/`. Static assets live in `assets/`.

## Build, Test, and Development Commands
Use Flutter/Dart tooling only. When installing dependencies, prefer the
Tsinghua pub mirror:

```bash
PUB_HOSTED_URL=https://mirrors.tuna.tsinghua.edu.cn/dart-pub flutter pub get
dart analyze
flutter test tests/unit_test
flutter run
```

## Coding Style & Naming Conventions
Target Dart 3.8+ and Flutter 3.24+. Follow the repository lint rules in
`analysis_options.yaml`. Keep files and functions in `snake_case`, classes in
`PascalCase`, constants in `lowerCamelCase` or `SCREAMING_CAPS` only when that
matches the surrounding code. Keep widgets focused and move reusable business
logic into `lib/src/data/` or `lib/src/domain/`.

## Testing Guidelines
Tests use `flutter_test`. Name test files `*_test.dart` and keep tests in the
correct parallel test domain:

- `tests/unit_test/`: fast deterministic checks for Dart logic, mappers,
  application/data services, providers, widgets, and pure E2E harness planning
  with fakes. These must not require real devices, real services, OTP, or CLI
  subprocesses.
- `tests/integration_test/`: Flutter App/platform smoke checks for App
  bootstrap, shell navigation, visual screenshot smoke, native SDK/plugin
  loading, and fake-port integration on macOS/Linux/iOS/Android runners. These
  should not own real multi-client backend E2E orchestration.
- `tests/e2e_test/`: real end-to-end orchestration assets for App + CLI
  peer/backend/device flows, including runner code, local/example configs,
  scenarios, Maestro flows, reports, and redaction rules.

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
