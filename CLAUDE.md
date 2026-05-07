# CLAUDE.md

This file provides guidance to Claude Code when working in the Flutter `awiki-me` repository.

## Documentation Language Policy

All documentation in this repository must be written in English, including Markdown files, code comments, and user-facing developer notes. The only exception is `README_zh.md`.

## Project Overview

`awiki-me` is a Flutter messaging client for AWiki identities, conversations, groups, profiles, local credential import/export, and realtime message updates. The application code lives under `lib/`, tests live under `test/`, and platform runners are in `android/`, `ios/`, and `web/`.

## Source of Truth

For message, identity, and realtime behavior, follow the sibling `../awiki-cli` repository. Do not preserve old `molt-message` or `/message/*` compatibility paths unless the user explicitly requests a migration shim.

Current message-service behavior must match awiki-cli:

- HTTP JSON-RPC endpoint: `/im/rpc`
- WebSocket endpoint: `/im/ws`
- WebSocket authentication: `Authorization: Bearer <jwt>` during upgrade
- Realtime notifications: `direct.incoming`, `group.incoming`, and `group.state_changed`
- Notification payloads use ANP `params.meta`, `params.body`, and optional `params.auth`

## Architecture

- `lib/src/app/`: app bootstrap and Riverpod service wiring.
- `lib/src/domain/`: entities, repository contracts, and service interfaces.
- `lib/src/data/awiki_sdk/`: ANP/message/user service client helpers and wire mappers.
- `lib/src/data/gateways/`: app-facing gateway implementations.
- `lib/src/data/services/`: local cache, WebSocket realtime, credential archive, DID/E2EE facades, and platform helpers.
- `lib/src/presentation/`: screens and Riverpod providers for onboarding, conversations, chat, groups, friends, profile, and settings.
- `assets/`: bundled branding and icon assets.
- `test/`: unit and widget tests.

## Commands

Run commands from the repository root:

```bash
flutter pub get
flutter analyze
flutter test
flutter test test/awiki_ws_realtime_gateway_test.dart
flutter run
dart run flutter_launcher_icons
dart run flutter_native_splash:create
```

Use `/home/ecs-user/.local/flutter/bin/flutter` or `/home/ecs-user/.local/flutter/bin/dart` if Flutter is not on `PATH`.

## Coding Guidelines

Use Dart 3 and `flutter_lints`. Format Dart changes with `dart format`. Keep filenames in `snake_case.dart`, classes and widgets in `PascalCase`, and variables, methods, and providers in `camelCase`. Keep protocol mapping in `lib/src/data/`, app behavior in providers, and shared contracts in `lib/src/domain/`.

## Testing Guidelines

Use `flutter_test`. Name test files `*_test.dart` and keep tests behavior-focused. Add tests when changing RPC endpoint construction, ANP envelope mapping, WebSocket connection/authentication behavior, local credential persistence, localization, or user-visible widget states.
