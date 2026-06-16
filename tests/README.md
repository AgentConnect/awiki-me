# AWiki Me Test Domains

AWiki Me keeps three parallel test domains. Choose the directory by the
boundary being tested, not by test size alone.

| Directory | Purpose | External dependencies |
| --- | --- | --- |
| `unit_test/` | Fast deterministic Dart logic, mapper, service-client, provider, widget, and fake-backed E2E harness tests. | No real device, backend, OTP, or CLI subprocess. |
| `integration_test/` | Flutter App/platform integration smoke: App bootstrap, shell navigation, screenshot-visible UI, native SDK/plugin loading, and fake-port App service wiring. | Flutter runner such as macOS/Linux/iOS/Android; usually no real backend. |
| `e2e_test/` | Real end-to-end orchestration: App + CLI peer/backend/device flows, configs, scenarios, Maestro flows, reports, and redaction rules. | Real non-production services, accounts/OTP, CLI peer, devices/simulators, or Maestro as required by the case. |

Root `../integration_test/*.dart` files are Flutter-tooling shims. Keep durable
test implementation under `integration_test/`; keep real E2E orchestration,
configuration, reporting, and scenario contracts under `e2e_test/`.

## New feature rule

Every new feature or behavior change must add or update tests in the same
change:

1. Add focused `unit_test/` coverage for changed logic, mapping, state, or
   widget behavior.
2. Add `integration_test/` coverage when App startup, navigation, visual
   surfaces, platform bindings, native plugins, or fake-port App bootstrap are
   affected.
3. Add or update `e2e_test/` assets when the behavior requires real backend,
   account/OTP, CLI peer, multi-client messaging, mobile devices, Maestro, or
   report redaction validation.

If a required real E2E case cannot run yet, document the skipped case ID,
blocker, owner, and follow-up in the relevant E2E docs or plan; do not count a
skipped case as passing evidence.
