# AWiki Me test maintenance backlog

This backlog turns the current high-conflict test files into bounded refactors.
It does not change case semantics and is not a substitute for the audited case
catalog or coverage gate.

## Split candidates

| Current file (2026-07-10) | Safe responsibility slices | Owner | Completion proof |
|---|---|---|---|
| `tests/unit/chat_provider_open_test.dart` (6643 lines) | open/hydrate; pending/send lifecycle; dedupe/replay; attachment/agent payload; read projection | `awiki-me-messaging` | before/after test-name set identical; full unit + coverage floors pass |
| `tests/unit/chat_page_test.dart` (5380 lines) | composer/send; failure/retry; attachment pick/drop/paste; mention UI; timeline/read/scroll; responsive states | `awiki-me-ui` | widget test-name parity; targeted golden/layout review; no shared mutable fixture ordering |
| `tests/unit/agents/agents_provider_test.dart` (3522 lines) | inventory/load; daemon actions; Message Agent binding/recovery; runtime lifecycle; error/idempotency | `awiki-me-agents` | provider test-name parity; optional E2E case IDs unchanged |
| `tests/unit/test_support.dart` (3902 lines) | account/session fakes; messaging/conversation fakes; group/relationship fakes; agent/runtime fakes; widget harness builders | `awiki-me-test-infra` | no circular imports; fake ownership documented; full unit count/IDs unchanged |

## Rules for each split

1. Move one responsibility slice per commit; do not combine behavior changes.
2. Capture `flutter test --reporter=json tests/unit` test names before and after,
   then compare the sorted names, not only the final count.
3. Run `dart run tests/unit/runner.dart --branch-coverage` and
   `dart run tool/test_coverage_gate.dart`; no threshold may be lowered to make
   a split green.
4. Keep reusable fakes narrow. A fake must expose calls/state needed by its
   owning behavior, not become another global service implementation.
5. Run the relevant no-service smoke if a moved test owns App-shell/bootstrap
   behavior. Live product verification, when required, targets only
   `awiki.info`.

## Current decision

No large file was mechanically split in the quality-baseline change. The same
workspace had concurrent conversation projection work, and splitting these
high-conflict files would make semantic review and mutation evidence ambiguous.
The catalog, coverage gate and this responsibility plan are the safe first
checkpoint.
