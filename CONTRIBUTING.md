# Contributing to AWiki Me

[English](CONTRIBUTING.md) | [简体中文](CONTRIBUTING.zh-CN.md)

Thank you for helping improve AWiki Me. The project spans Flutter product experience, the shared IM Core, platform secure storage, and cross-client message semantics. Keep contributions focused and behavior verifiable.

## Before you start

- Search existing issues and pull requests first.
- For substantial features, protocol changes, or platform metadata changes, open an issue describing the goal, user value, and boundaries.
- Do not mix unrelated formatting, generated Xcode/Gradle files, or sibling SDK refactors into one pull request.
- Changes to `awiki_im_core` or `awiki-im-core` behavior should update the corresponding design and tests in that repository.

## Environment

```bash
cd ../awiki-cli-rs2
scripts/flutter/build-sdk-native.sh --macos-only

cd ../awiki-me
flutter pub get
```

Replace the native SDK build option for the target platform.

## Pre-submit gates

```bash
dart analyze
dart run tests/unit/runner.dart
dart run tests/e2e/runner.dart --case smoke
```

For critical state machines or coverage baseline changes:

```bash
dart run tests/unit/runner.dart --branch-coverage
dart run tool/test_coverage_gate.dart
```

Run real-backend, CLI-peer, OTP, mobile-device, or release-signing tests only after preparing the environment. Record the configuration context and results in the pull request.

## Testing requirements

- Cover Domain, Mapper, Provider, Service, and Widget changes in `tests/unit/` first.
- Add a `tests/e2e/` smoke case for app startup, navigation, platform bridges, or screenshot-visible UI changes.
- Add the corresponding E2E runner assets for cross-App/CLI/service, attachment, group, and device behavior.
- If an expensive E2E case cannot run, record its case, owner, blocker, and follow-up. Never report a skipped case as passing.

## Architecture rules

- Flutter calls high-level `awiki_im_core` APIs.
- Do not rebuild raw RPC, WebSocket, DID proof, reliable sync checkpoints, or private E2EE state in the app.
- Core is the source of truth for messages, conversations, read state, outbox, sync, and the identity vault.
- The app may keep short-lived pending UI and product overlays, but they must not override persisted Core facts.
- Change platform runners, signing, entitlements, Bundle IDs, or Pod/Gradle metadata only when the task requires it.

## Security and privacy

Never commit:

- private keys, JWTs, bearer tokens, or OTPs;
- `.p12` or `.pfx` files, signing identities, or private Team ID configuration;
- local E2E YAML, account pools, reports, or generated state;
- real DIDs, phone numbers, email addresses, or messages;
- absolute paths or internal service addresses; or
- SecretVault envelopes, root keys, or raw secure DTO dumps.

Report security issues privately according to [SECURITY.md](SECURITY.md).

## Suggested pull request description

```text
What changed
Why it matters to users
Affected platforms
Affected protocol/core boundaries
Tests run
Screenshots or recordings
Known limitations / follow-up
```

Include a screenshot from the running app for UI changes and confirm whether the README assets also need an update.
