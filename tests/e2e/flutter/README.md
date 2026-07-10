# Flutter E2E Implementations

`tests/e2e/flutter/` contains Flutter integration smoke tests for App bootstrap,
platform binding, deterministic profile/settings navigation, and native plugin
loading. These tests may run against a Flutter desktop target such as `macos` or
`linux`.

Current groups:

- `app/`: App shell smoke with fake bootstrap, onboarding/authenticated shell,
  basic profile/settings navigation, Message Agent full-UI harness, Codex
  Agent, and Claude Code Agent user-visible reply acceptance.
- `desktop_cli_peer/`: real desktop App + `awiki-cli-rs2` product E2E for
  UI-driven direct/unread/read/retry, group/mention, attachment, and
  follow/contact flows, plus strict read-only App/CLI oracles. The maintained
  remote gate targets `awiki.info`.
- `native/`: native SDK/plugin smoke such as `AwikiImCore.open` and macOS
  secure storage Keychain access.
- `support/`: integration-only helpers.

Run E2E through the repository-level runner:

```bash
dart run tests/e2e/runner.dart --case smoke
dart run tests/e2e/runner.dart --case full
dart run tests/e2e/runner.dart --case performance
dart run tests/e2e/runner.dart --case message-agent
dart run tests/e2e/runner.dart --case codex-agent
dart run tests/e2e/runner.dart --case claude-code-agent
```

When changing macOS signing, entitlements, or platform secure storage, also run
the direct native smoke:

```bash
flutter test --no-pub integration_test/secure_storage_smoke_test.dart -d macos
```

This test exercises `flutter_secure_storage` through the signed macOS runner and
guards against Keychain authorization failures such as OSStatus `-34018`.

`--case performance` is the startup/conversation performance acceptance gate for
the real desktop App + CLI peer + backend flow. It writes product-level metrics
to `.e2e/desktop-cli-peer/<run-id>/reports/timings.json`, including the
separate `toolingTimings`, `appProductTimings`, `dataset`, `budgets`,
`metrics`, `counters`, `hardFailures`, and `softWarnings` sections. The gate is
intended to prove the message-sync performance work with product timings such as
shell visible, first non-empty conversation list, snapshot load, fast local
hydrate, full hydrate, full conversation page scan, App-to-CLI visible latency,
CLI-to-App visible latency, realtime click-open first-paint latency, and thread
initial load. It also gates the AWiki Me message memory cache by writing cache
stats into top-level `metrics` and cumulative cache counters into top-level
`counters`.

The required cache metrics are:

- `cache.raw_thread_state_count`
- `cache.canonical_thread_count`
- `cache.total_retained_messages`
- `cache.active_patch_subscription_count`
- `cache.message_route_entry_count`
- `cache.trimmed_message_count`
- `cache.evicted_thread_count`
- `cache.protected_overflow_count`

The required cache counters are:

- `cache.trimmed_message_count`
- `cache.evicted_thread_count`
- `cache.protected_overflow_count`

These cache fields are count-only evidence. They must not include message body
text, payloads, raw thread ids, tokens, local paths, attachment paths, or full
DIDs. They are used to prove the UI message cache remains bounded; they do not
represent the Rust `im-core` reliable checkpoint or SQLite projection state.

The realtime click-open gate records
`message.cli_send_to_app_open_first_paint_ms` from CLI send to App provider open
first paint, and `thread.realtime_open_first_paint_ms` for the open path itself;
the flow must not satisfy this gate only by calling history or explicit
`syncThreadAfter`. For large datasets the gate must page the conversation list
through `nextCursor`; 500/1000 conversation targets are not satisfied by the
first 100-row page. It fails on missing required metrics, insufficient
configured dataset coverage, missing required dataset/counter evidence, hard
budget overrun, or any full conversation refresh counted during the App
send/receive window. Soft budget overruns remain warnings so local real-backend
variance can be tracked before thresholds are tightened.

`--case full` is the AWiki Me UI-driven product E2E entry for the real backend
App + CLI peer exchange. It must not replace App user actions with direct
application-service calls. `--case performance` is intentionally a
service-driven timing/backend integration diagnostic and does not count as UI
acceptance. Use the two gates for their distinct purposes:

```bash
dart run tests/e2e/runner.dart --case performance
dart run tests/e2e/runner.dart --case full
```

`--case message-agent` is the durable acceptance entry for Message Agent
product behavior. It must exercise the App UI path for selecting a daemon,
enabling the Message Agent, recovering `message.sync` / `runtime_final` /
`app.action` payloads, confirming or rejecting App actions, and the
pause/delete/revoke lifecycle entries. Lower-level probes such as
`tool/daemon_control_probe.dart` and daemon pytest probes may support payload,
security, or backend diagnostics, but they do not replace this full UI E2E gate.
The real-backend branch must also prove the received/returned/content contract:
the App local history contains the exact CLI source message, the daemon records
a sent `runtime_final_outbox` row with a non-null message id and sent timestamp,
and the final text equals the deterministic expected reply.

The Message Agent management surface is currently hidden in the product. The
real-backend scenario is intentionally fail-closed: fake-backed Widget tests,
an outer `flutter test` exit code, a missing config, or a partial lifecycle may
not attest the four Message Agent case IDs. The runner remains red until the
UI and all required phases are restored; lower-level backend coverage continues
to be reported separately and must not be relabeled as full UI acceptance.

Every runner-owned Flutter invocation receives an ignored local attestation
path through dart-defines. Durable scenarios call
`E2eCaseAttestationWriter.markPassed` only after the case's business assertions
complete. Schema-v2 `timings.json` is derived from that scenario-owned evidence:
`dry_run`, `prepared`, missing, duplicate, skipped, or incomplete case results
are never converted to `passed`.

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
