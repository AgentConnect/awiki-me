# Integration Test Domain

`tests/integration_test/` contains Flutter integration smoke tests for App bootstrap,
platform binding, deterministic profile/settings navigation, and native plugin
loading. These tests may run against a Flutter desktop target such as `macos` or
`linux`, but they should not create a real multi-client backend E2E flow.

Current groups:

- `app/`: App shell smoke with fake bootstrap, onboarding/authenticated shell,
  and basic profile/settings navigation.
- `agent_im/`: Agent IM App bootstrap smoke; triggers `awiki.daemon.bootstrap.v1` via production App service with fake ports and verifies system payload visibility/redaction.
- `native/`: native SDK/plugin smoke such as `AwikiImCore.open`.
- `support/`: integration-only helpers.

Run macOS smoke via the root Flutter-tooling shims:

```bash
flutter test integration_test/app_smoke_test.dart -d macos
flutter test integration_test/agent_im_delegated_message_e2e_test.dart -d macos
flutter test integration_test/im_core_open_smoke_test.dart -d macos
```

Do not move the implementation back to the root shim directory; Flutter requires
the shim path for plugin detection, while the source-of-truth test code lives here.
