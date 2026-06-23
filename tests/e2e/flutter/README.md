# Flutter E2E Implementations

`tests/e2e/flutter/` contains Flutter integration smoke tests for App bootstrap,
platform binding, deterministic profile/settings navigation, and native plugin
loading. These tests may run against a Flutter desktop target such as `macos` or
`linux`.

Current groups:

- `app/`: App shell smoke with fake bootstrap, onboarding/authenticated shell,
  basic profile/settings navigation, Message Agent full-UI harness, and Codex
  Agent user-visible reply acceptance.
- `desktop_cli_peer/`: real desktop App + `awiki-cli-rs2` peer integration
  implementations for direct, group, attachment, and follow/contact flows.
- `native/`: native SDK/plugin smoke such as `AwikiImCore.open`.
- `support/`: integration-only helpers.

Run E2E through the repository-level runner:

```bash
dart run tests/e2e/runner.dart --case smoke
dart run tests/e2e/runner.dart --case full
dart run tests/e2e/runner.dart --case message-agent
dart run tests/e2e/runner.dart --case codex-agent
```

`--case message-agent` is the durable acceptance entry for Message Agent
product behavior. It must exercise the App UI path for selecting a daemon,
enabling the Message Agent, recovering `message.sync` / `runtime_final` /
`app.action` payloads, confirming or rejecting App actions, and the
pause/delete/revoke lifecycle entries. Lower-level probes such as
`tool/daemon_control_probe.dart` and daemon pytest probes may support payload,
security, or backend diagnostics, but they do not replace this full UI E2E gate.

`--case codex-agent` is the durable acceptance entry for Codex Agent direct-chat
behavior. It must create/select a Codex runtime Agent, send a deterministic
prompt through the App chat UI, require `runtime_run.status = finished` and
`runtime_final_outbox.status = sent`, then verify the App local message history
and visible chat bubble contain the exact Codex reply. Runtime status probes or
Codex CLI output files alone are not sufficient evidence because they do not
prove the user-visible delivery leg.

Root `integration_test/*.dart` files are Flutter tooling shims only. Use them
only for focused debugging of an individual Flutter test implementation:

```bash
flutter test integration_test/app_smoke_test.dart -d macos
flutter test integration_test/message_agent_full_ui_test.dart -d macos
flutter test integration_test/codex_agent_full_ui_test.dart -d macos
flutter test integration_test/desktop_cli_peer_smoke_test.dart -d macos
flutter test integration_test/desktop_cli_peer_group_test.dart -d macos
flutter test integration_test/im_core_open_smoke_test.dart -d macos
```

Do not move the implementation back to the root shim directory; Flutter requires
the shim path for plugin detection, while the source-of-truth test code lives here.
