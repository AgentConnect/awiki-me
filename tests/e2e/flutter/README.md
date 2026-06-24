# Flutter E2E Implementations

`tests/e2e/flutter/` contains Flutter integration smoke tests for App bootstrap,
platform binding, deterministic profile/settings navigation, and native plugin
loading. These tests may run against a Flutter desktop target such as `macos` or
`linux`.

Current groups:

- `app/`: App shell smoke with fake bootstrap, onboarding/authenticated shell,
  basic profile/settings navigation, Message Agent full-UI harness, Codex
  Agent, and Claude Code Agent user-visible reply acceptance.
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
dart run tests/e2e/runner.dart --case claude-code-agent
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
prove the user-visible delivery leg. The runner gives this case a longer
Flutter timeout than the smoke tests and fails immediately with the daemon
`cli_driver_run` / final-output diagnostic if the CLI run reaches a failed
state before the expected reply.

`--case claude-code-agent` is the equivalent durable acceptance entry for Claude
Code Agent direct-chat behavior. It must create/select a Claude Code runtime
Agent, send a deterministic prompt through the App chat UI, require
`runtime_run.status = finished` and `runtime_final_outbox.status = sent`, then
verify the App local message history and visible chat bubble contain the exact
Claude Code reply. CLI install/version probes or raw Claude Code output alone
are not sufficient evidence because they do not prove the daemon-to-App
delivery leg. Claude Code can be slower than Codex on a cold profile, so the
runner gives this case a longer Flutter timeout and keeps the temporary daemon
alive long enough for the daemon-side runtime timeout to produce a deterministic
success or failure record instead of leaving the test stuck in `pending`.

When a real Claude Code or Codex CLI requires environment values that are
available in an interactive shell but not in a daemon process, point the local
E2E config at a local-only daemon env file:

```yaml
daemon:
  envFile: .e2e/agent-cli.env
```

The file is loaded only into the temporary E2E daemon process. Keep it outside
git and use `AWIKI_DAEMON_CLI_ENV_PASSTHROUGH` to explicitly allow the values
that the CLI child process may inherit, for example
`AWIKI_DAEMON_CLI_ENV_PASSTHROUGH=ANTHROPIC_*,CLAUDE_CODEX_MODEL`. Test logs and
reports must never include the env file's secret values.

Root `integration_test/*.dart` files are Flutter tooling shims only. Use them
only for focused debugging of an individual Flutter test implementation:

```bash
flutter test --dart-define=AWIKI_E2E=true integration_test/app_smoke_test.dart -d macos
flutter test --dart-define=AWIKI_E2E=true integration_test/message_agent_full_ui_test.dart -d macos
flutter test --dart-define=AWIKI_E2E=true integration_test/codex_agent_full_ui_test.dart -d macos
flutter test --dart-define=AWIKI_E2E=true integration_test/claude_code_agent_full_ui_test.dart -d macos
flutter test --dart-define=AWIKI_E2E=true integration_test/desktop_cli_peer_smoke_test.dart -d macos
flutter test --dart-define=AWIKI_E2E=true integration_test/desktop_cli_peer_group_test.dart -d macos
flutter test --dart-define=AWIKI_E2E=true integration_test/im_core_open_smoke_test.dart -d macos
```

Do not move the implementation back to the root shim directory; Flutter requires
the shim path for plugin detection, while the source-of-truth test code lives here.
