# Repository Guidelines

## Project Structure & Module Organization
`lib/` contains the Flutter application. Core app wiring lives in `lib/src/app/`, domain models and repository contracts in `lib/src/domain/`, data gateways and services in `lib/src/data/`, and screens/providers in `lib/src/presentation/`. Localization files live under `lib/l10n/` and `lib/src/l10n/`. Tests are in `test/` and should mirror the behavior under test, for example `test/awiki_ws_realtime_gateway_test.dart`. Bundled images and icons live in `assets/`; platform runners live in `android/`, `ios/`, and `web/`.

## AWiki Me Source of Truth
For message, identity, and realtime behavior, use the sibling `../awiki-cli` repository as the reference implementation. Do not preserve old `molt-message` or `/message/*` compatibility paths unless explicitly requested. Message-service integration should follow awiki-cli's current v2 behavior: `/im/rpc`, `/im/ws`, Bearer-authenticated WebSocket upgrades, and ANP notification methods such as `direct.incoming`, `group.incoming`, and `group.state_changed`.

## Build, Test, and Development Commands
- `flutter pub get` installs Dart and Flutter dependencies.
- `flutter analyze` runs static analysis using `analysis_options.yaml`.
- `flutter test` runs all unit and widget tests.
- `flutter test test/awiki_ws_realtime_gateway_test.dart` runs a focused realtime gateway suite.
- `flutter run` starts the app on the selected device or emulator.
- `dart run flutter_launcher_icons` regenerates app icons from `assets/branding/awiki-me-logo.png`.
- `dart run flutter_native_splash:create` regenerates the splash screen.

## Coding Style & Naming Conventions
Use Dart 3 with `flutter_lints`. Format changed Dart files with `dart format`. Use 2-space indentation, `PascalCase` for classes and widgets, `camelCase` for methods, variables, and providers, and `snake_case.dart` filenames. Keep UI state in Riverpod providers, domain contracts in `lib/src/domain/`, and service-specific protocol logic in `lib/src/data/`.

## Testing Guidelines
Use `flutter_test` for unit and widget coverage. Name test files `*_test.dart` and write behavior-focused test names, such as `maps direct.incoming meta body envelope`. Add or update focused tests when changing RPC mapping, WebSocket connection behavior, local credential handling, localization, or user-visible UI states.

## Commit & Pull Request Guidelines
Recent history uses concise imperative subjects, often with conventional prefixes such as `feat:` and `fix:`. Keep each commit scoped to one behavior change. Pull requests should describe the user-facing change, note protocol or configuration changes, link related issues, include screenshots for UI changes, and list verification commands such as `flutter analyze` and `flutter test`.

## Security & Configuration Tips
Do not commit local credentials, build outputs, or device-specific files. Configure service endpoints with compile-time environment values such as `AWIKI_MESSAGE_SERVICE_URL`; keep secrets out of source and test fixtures.
