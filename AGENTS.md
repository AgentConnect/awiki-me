# Repository Guidelines

## Project Structure & Module Organization
`lib/` contains the Flutter application. Domain contracts live in
`lib/src/domain/`, Dart service clients and persistence live in
`lib/src/data/`, and UI/providers live in `lib/src/presentation/`.
`tests/unit_test/` contains Dart unit/widget/provider tests. `tests/integration_test/` contains Flutter app/native/platform smoke implementations. `tests/e2e_test/` contains end-to-end harnesses, configs, scenarios, and Maestro flows. Root `integration_test/*.dart` files are Flutter-tooling shims only. Platform runners live under
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
Tests use `flutter_test`. Name test files `*_test.dart` and keep tests in the correct parallel test domain: `tests/unit_test/` for fast fake-backed tests, `tests/integration_test/` for platform/native smoke tests, and `tests/e2e_test/` for real end-to-end harnesses and scenarios. Prefer focused unit tests for account/session storage,
ANP wire mapping, and service clients; use widget tests for onboarding,
settings, and chat flows.

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
