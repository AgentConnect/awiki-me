# AWiki Me E2E

This directory contains the Maestro-based two-device E2E smoke test for AWiki
Me. It drives the installed app on iOS simulators or Android emulators in the
same way a user would: login, open chats, send messages, and wait for the peer
device to receive them.

## Layout

```text
e2e/
  README.md
  runner.dart
  config.example.yaml
  config.local.yaml
  maestro/
    login.yaml
    open_chat_and_send.yaml
    open_chat_and_wait.yaml
  reports/
```

`config.local.yaml` and `reports/` are local-only files and are ignored by git.

## Run

Create a local config from the example:

```bash
cp e2e/config.example.yaml e2e/config.local.yaml
```

Run the E2E smoke test:

```bash
dart run e2e/runner.dart --config e2e/config.local.yaml
```

For command/path validation without touching devices:

```bash
dart run e2e/runner.dart --dry-run
```

## Requirements

- Flutter SDK.
- Maestro CLI.
- For iOS: Xcode command line tools and two iOS simulators.
- For Android: Android SDK platform tools and two devices/emulators.

The runner builds the app with `AWIKI_E2E=true`, which enables stable semantic
identifiers in the app for Maestro flows. The app-side helper remains in
`lib/src/app/e2e_semantics.dart` because it is part of the Flutter runtime code,
not the external test runner.
