# AWiki Me

AWiki Me is a standalone Flutter client extracted and adapted from the upstream project [AgentConnect/awiki-agent-id-message](https://github.com/AgentConnect/awiki-agent-id-message).

This repository keeps the Flutter app as an independent mobile/web codebase while removing the original Python skill runtime, listener tooling, and service-side helper scripts from the main development workflow.

## Upstream Relationship

- Upstream project: [AgentConnect/awiki-agent-id-message](https://github.com/AgentConnect/awiki-agent-id-message)
- This repository is based on the Flutter client portion of that project.
- The app still targets the same AWiki service family and protocol-facing APIs.
- Python CLI tools, listener deployment templates, and skill packaging docs are intentionally not carried forward as part of this repository.

## Technical Scope

AWiki Me currently includes these client-side capabilities:

- DID session bootstrap and session restore
- Handle / profile retrieval and profile editing
- Direct message and group message retrieval through RPC APIs
- Relationship APIs such as follow / follower / following queries
- WebSocket-based realtime message updates
- Local message and group cache backed by SQLite
- Credential import / export as ZIP bundles
- Platform-specific DID registration bridge:
  - Android: native `MethodChannel` implementation
  - iOS: Dart-side registration facade
- Pluggable E2EE integration surface, with the current default implementation kept as a no-op fallback unless a native plugin is wired in

## Architecture

The app is structured in a layered way:

- `lib/src/domain/`
  - Entities, repository contracts, and service abstractions
- `lib/src/data/`
  - RPC gateway, realtime gateway, local cache, credential archive, platform bridges
- `lib/src/presentation/`
  - App shell, onboarding, chat, profile, groups, settings, and shared UI system
- `lib/src/app/`
  - Bootstrap and dependency wiring

The main application flow is assembled in [`lib/src/app/bootstrap.dart`](/Users/tyy/Documents/GitHub/awiki-me/lib/src/app/bootstrap.dart), where the gateway, realtime service, notification facade, E2EE facade, and controller are created and injected.

## Key Runtime Components

- [`lib/src/data/gateways/awiki_rpc_gateway.dart`](/Users/tyy/Documents/GitHub/awiki-me/lib/src/data/gateways/awiki_rpc_gateway.dart)
  - Main RPC integration layer for auth, profile, messaging, groups, and relationships
- [`lib/src/data/services/awiki_ws_realtime_gateway.dart`](/Users/tyy/Documents/GitHub/awiki-me/lib/src/data/services/awiki_ws_realtime_gateway.dart)
  - WebSocket connection management with reconnect logic
- [`lib/src/data/services/awiki_local_cache.dart`](/Users/tyy/Documents/GitHub/awiki-me/lib/src/data/services/awiki_local_cache.dart)
  - SQLite-backed cache for threads, messages, and groups
- [`lib/src/data/services/credential_archive_service.dart`](/Users/tyy/Documents/GitHub/awiki-me/lib/src/data/services/credential_archive_service.dart)
  - ZIP import/export format for portable credential bundles

## Runtime Configuration

The app reads the following compile-time configuration values:

- `AWIKI_USER_SERVICE_URL`
- `AWIKI_MESSAGE_SERVICE_URL`
- `AWIKI_WS_URL`
- `AWIKI_CREDENTIALS_DIR`
- `AWIKI_SETUP_IDENTITY_SCRIPT`

Default service endpoints fall back to `https://awiki.ai` when not overridden.

## Platforms

- Android
  - Native document picker channel
  - Native DID registration channel
- iOS
  - Native document picker bridge
  - Dart-based DID registration facade
- Web
  - Flutter web runner is included, but some mobile-oriented platform integrations may require adaptation

## Development

### Requirements

- Flutter 3.24.0 or newer
- Dart 3.5.0 or newer

### Local Commands

```bash
flutter pub get
flutter analyze
flutter test
flutter run
```

### Asset Tooling

Regenerate app icons:

```bash
dart run flutter_launcher_icons
```

Regenerate splash screen:

```bash
dart run flutter_native_splash:create
```

Logo source:

- `assets/branding/awiki-me-logo.png`

## Repository Layout

- `lib/`: application source
- `assets/`: bundled branding and SVG assets
- `test/`: widget and unit tests
- `android/`, `ios/`, `web/`: platform projects

## Notes and Limitations

- This repository focuses on the client application, not the original skill packaging/runtime model.
- Some AWiki-facing class names and protocol names remain intentionally unchanged to preserve compatibility with the upstream service APIs.
- E2EE is designed as an integration surface, but the default fallback implementation is still disabled unless a native plugin is provided.
