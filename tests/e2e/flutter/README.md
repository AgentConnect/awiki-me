# Flutter E2E Implementations

`tests/e2e/flutter/` contains Flutter integration smoke tests for App bootstrap,
platform binding, deterministic profile/settings navigation, and native plugin
loading. These tests may run against a Flutter desktop target such as `macos` or
`linux`.

Current groups:

- `app/`: App shell smoke with fake bootstrap, onboarding/authenticated shell,
  and basic profile/settings navigation.
- `desktop_cli_peer/`: real desktop App + `awiki-cli-rs2` peer integration
  implementations for direct, group, attachment, and follow/contact flows.
- `native/`: native SDK/plugin smoke such as `AwikiImCore.open`.
- `support/`: integration-only helpers.

Run E2E through the repository-level runner:

```bash
dart run tests/e2e/runner.dart --case smoke
dart run tests/e2e/runner.dart --case full
```

Root `integration_test/*.dart` files are Flutter tooling shims only. Use them
only for focused debugging of an individual Flutter test implementation:

```bash
flutter test integration_test/app_smoke_test.dart -d macos
flutter test integration_test/desktop_cli_peer_smoke_test.dart -d macos
flutter test integration_test/desktop_cli_peer_group_test.dart -d macos
flutter test integration_test/im_core_open_smoke_test.dart -d macos
```

Do not move the implementation back to the root shim directory; Flutter requires
the shim path for plugin detection, while the source-of-truth test code lives here.
