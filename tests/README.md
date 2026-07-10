# AWiki Me Test Domains

AWiki Me keeps two active test domains. Choose the directory by the boundary
being tested, not by test size alone.

| Directory | Purpose | External dependencies |
| --- | --- | --- |
| `unit/` | Fast deterministic Dart logic, mapper, service-client, provider, widget, and fake-backed E2E harness tests. | No real device, backend, OTP, or CLI subprocess. |
| `e2e/` | E2E runners, configs, Flutter shim implementations, platform smoke, real App + CLI peer/backend/device flows, reports, and redaction rules. | Depends on case: smoke uses local Flutter desktop; full flows may need real non-production services, accounts/OTP, CLI peer, devices/simulators, or Maestro. |

Root `../integration_test/*.dart` files are Flutter-tooling shims. Keep durable
Flutter test implementation under `e2e/flutter/`; keep real E2E orchestration,
configuration, reporting, and scenario contracts under `e2e/`.

`e2e/suite_manifest.json` defines executable suite membership. The separate
`e2e/case_catalog.json` adds exact oracles, negative guards, ownership and
implementation paths, and may contain explicit `planned` gaps. Validate both
plus the generated human catalog with:

```bash
dart run tool/validate_test_catalog.dart
```

## New Feature Rule

Every new feature or behavior change must add or update tests in the same
change:

1. Add focused `unit/` coverage for changed logic, mapping, state, or widget
   behavior.
2. Add `e2e/` Flutter smoke coverage when App startup, navigation, visual
   surfaces, platform bindings, native plugins, or fake-port App bootstrap are
   affected.
3. Add or update `e2e/` runner assets when the behavior requires real backend,
   account/OTP, CLI peer, multi-client messaging, mobile devices, Maestro, or
   report redaction validation.

If a required real E2E case cannot run yet, document the skipped case ID,
blocker, owner, and follow-up in the relevant E2E docs or plan; do not count a
skipped case as passing evidence.


## Message Agent real-backend E2E note

The real-backend `message-agent` flow intentionally waits until the local daemon
has queued a runtime final for the CLI peer message before opening the App chat
conversation. Opening the conversation can mark the message read in the live
`awiki.info` inbox; the daemon currently consumes the delegated inbox as an
unread processing queue, so the test must not mark the source message read before
observing daemon-side processing.

The executable Message Agent IDs are `MSGAGENT-E2E-001`, `002`, and `004`.
`003` is cataloged as planned until a visible confirmation/draft action exists;
it must not be synthesized by the outer runner.
