# AWiki Me Test Domains

AWiki Me keeps three active test domains. Choose the directory by the boundary
being tested, not by test size alone.

| Directory | Purpose | External dependencies |
| --- | --- | --- |
| `unit/` | Fast deterministic Dart logic, mapper, service-client, provider, widget, and fake-backed E2E harness tests. | No real device, backend, OTP, or CLI subprocess. |
| `e2e/` | E2E runners, configs, Flutter shim implementations, platform smoke, real App + CLI peer/backend/device flows, reports, and redaction rules. | Depends on case: smoke uses local Flutter desktop; full flows may need real non-production services, accounts/OTP, CLI peer, devices/simulators, or Maestro. |
| `computer-use/` | Playbooks for a screen-using AI or human: visible clicks, typed input, and on-screen oracles on two real macOS Apps. | Real Debug Apps, awiki.info (or a prompt-selected tenant), local OTP config, and optional published daemon. Not executed by the Dart E2E runner. |

Root `../integration_test/*.dart` files are Flutter-tooling shims. Keep durable
Flutter test implementation under `e2e/flutter/`; keep real E2E orchestration,
configuration, reporting, and scenario contracts under `e2e/`.

`e2e/suite_manifest.json` defines executable suite membership and bounded time
budgets; `timeoutMinutes` must not be shorter than `estimatedMinutes`. The separate
`e2e/case_catalog.json` adds exact oracles, negative guards, ownership and
implementation paths, and may contain explicit `planned` gaps. Validate both
plus the generated human catalog with:

```bash
dart run tool/validate_test_catalog.dart
```

`computer-use/` is a separate operator/AI domain. Its `CU-*` cases live in
`computer-use/cases.md` and are not members of `e2e/suite_manifest.json`.
Start at [`computer-use/README.md`](computer-use/README.md).

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
4. If a `computer-use/` case describes the changed visible click, type, or
   on-screen oracle, update that playbook in the same change. Do not add
   computer-use coverage for backend-only or CLI-oracle-only work.

If a required real E2E case cannot run yet, document the skipped case ID,
blocker, owner, and follow-up in the relevant E2E docs or plan; do not count a
skipped case as passing evidence.


## Personal Agent real-backend E2E note

The real-backend `personal-agent` flow intentionally waits until the local daemon
has queued a runtime final for the CLI peer message before opening the App chat
conversation. Opening the conversation can mark the message read in the live
`awiki.info` inbox; the daemon currently consumes the delegated inbox as an
unread processing queue, so the test must not mark the source message read before
observing daemon-side processing.

The executable Personal Agent IDs are `PERSONALAGENT-E2E-001`, `002`, and `004`.
The flow exercises draft confirmation as a supporting step, but `003` remains
planned until it has its own accepted case attestation; the outer runner must
not synthesize it.
