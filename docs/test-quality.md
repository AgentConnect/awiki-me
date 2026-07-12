# AWiki Me test quality baseline

## Reproducible unit quality gate

```bash
dart run tests/unit/runner.dart --branch-coverage
dart run tool/test_coverage_gate.dart
```

Baseline established on 2026-07-10: 972 passed; overall line coverage 76.95%
(23986/31171), branch coverage 62.28% (6468/10385). The checked-in policy in
`tests/quality/coverage_baseline.json` also protects these critical files:

- `chat_provider.dart`: send/retry/local echo/dedupe/replay state;
- `conversation_provider.dart`: canonical rows, unread/read presentation and patch repair;
- `friends_provider.dart`: relationship interaction/convergence;
- `message_sync_service.dart` and `relationship_application_service.dart`.

The thresholds are a no-regression floor. They do not claim that unlisted
onboarding/profile/group-role/mobile/runtime-provider behaviors have product
E2E coverage; those boundaries are explicit in the generated
[case catalog](test-case-catalog.md).

## Fault/mutation proof

Temporary mutations were applied one at a time, the focused test was run, and
the source was restored before any commit:

| Weak implementation | Result |
|---|---|
| App read watermark always assigns the latest call, allowing a lower replay to roll state back | Existing tests initially stayed green. Added `lower read watermark replay cannot reopen a covered message`; the mutation then failed with unread `1` instead of `0`. |
| E2E runner accepts skipped/not-run case evidence | `tests/unit/e2e_harness/e2e_case_attestation_test.dart` and runner contract tests fail closed. |
| Catalog/report accepts missing, duplicate, unknown or reordered IDs | `test_catalog_test.dart` negative cases fail closed. |

The first probe is important: branch coverage alone had executed both sides of
the monotonic comparison but did not prove the semantic outcome. The new test
therefore stays even though the numeric percentage did not increase.

Cross-repo probes in `awiki-system-test/docs/test-quality.md` additionally kill
set-collapsed duplicate IDs, weakened exact-one matching and required-skip-as-pass.

## Current remote evidence

The final integrated `awiki.info` Direct run is still a product failure, not a
test failure or pass: identity preflight succeeded and total unread increased
by one. The stricter conversation oracle observed `candidate_rows=1` and
`semantic_matches=1`, but `canonical_matches=0` for the expected conversation
ID. `AUTH-E2E-001` passed; `MSG-E2E-001`, `MSG-E2E-002` and `MSG-REG-001`
remained not-run. Remote resources remain explicitly `residual` because there
is no public delete API.

## Maintainability

Responsibility-based split boundaries for the four largest unit/support files
are tracked in [test-maintenance-backlog.md](test-maintenance-backlog.md). No
mechanical split was combined with this quality change because concurrent
conversation projection work would make semantic parity review ambiguous.
