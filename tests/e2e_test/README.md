# E2E Test Domain

`tests/e2e_test/` contains end-to-end harnesses, scenarios, configs, and mobile flow
files. E2E tests may use the real App, `awiki-cli-rs2` as a CLI peer, and a real
non-production backend. Keep secrets and generated state out of Git.

Structure:

- `harness/`: desktop/mobile runners and shared E2E orchestration code.
- `configs/`: checked-in example configs only; local configs are ignored.
- `mobile/maestro/`: Maestro flows used by mobile E2E.
- `scenarios/`: reusable E2E scenario code. Agent IM delegated-message code is
  retained as deferred scenario infrastructure, not as a current baseline gate.

Desktop dry-run:

```bash
dart run tests/e2e_test/harness/desktop_e2e_runner.dart --platform=macos --dry-run
```

Group-only App + CLI peer desktop E2E:

```bash
dart run tool/desktop_cli_peer_e2e_runner.dart \
  --platform macos \
  --case group \
  --service-base-url https://awiki.info \
  --did-domain awiki.info
```

Use `--case group` when validating group chat regressions without paying the
direct-message and attachment portions of the full desktop smoke. The runner
maps this to `integration_test/desktop_cli_peer_group_test.dart`; `--case full`
continues to use `integration_test/desktop_cli_peer_smoke_test.dart`. Both
shims run the real App integration test and `awiki-cli-rs2` peer against the
configured backend.

Deferred Agent IM delegated-message dry-run:

```bash
dart run tests/e2e_test/harness/desktop_e2e_runner.dart \
  --platform=macos \
  --scenario=agent-im-delegated-message \
  --config tests/e2e_test/configs/agent_im_delegated.example.yaml \
  --dry-run
```

The Agent IM scenario config records environment variable names only. The App
bootstrap scenario hook lives in
`tests/e2e_test/scenarios/agent_im_delegated_message/` and is exercised by
`integration_test/agent_im_delegated_message_e2e_test.dart`. This scenario is
tracked as `AGENT-SKIP-001` in the current AWiki Me basic E2E baseline: keep the
entry and implementation available for a future standalone Agent IM plan, but do
not run it or add it to PR/nightly/release gates while it is skipped. Local
configs, generated CLI workspaces, and `.e2e/` reports remain ignored.

Mobile dry-run:

```bash
dart run tests/e2e_test/harness/mobile_e2e_runner.dart \
  --config tests/e2e_test/configs/mobile.example.yaml \
  --dry-run
```

Mobile dry-run reports are written under `.e2e/reports/<runId>/timings.json`.
They record scenario `mobile-two-device`, case `MOBILE-E2E-001`, dry-run skip
reason, configured devices, account handles, planned message IDs, and redacted
service/report paths. A dry-run `success` only proves the runner plan; the case
status remains `skipped` until a real iOS or Android two-device run completes.

Gate usage:

- PR required: runner dry-runs only. Use mobile dry-run and desktop dry-run with
  `--skip-cli-build --skip-flutter-smoke`; do not require OTP, real devices, or
  a live backend.
- PR optional desktop: Linux/macOS App/native smoke only. Linux must run through
  `xvfb-run`.
- Nightly desktop: real Desktop App+CLI peer direct/group/attachment basics with
  isolated `.e2e/<platform>/` state and private redacted reports.
- Nightly mobile: real `MOBILE-E2E-001` with two independent iOS or Android
  devices and an ignored `tests/e2e_test/configs/mobile.local.yaml`.
- Release: stable P0/P1 regression subset only; new feature cases need nightly
  stability before promotion.

Every real run should record runId, platform, scenario, case IDs,
pass/fail/skipped status, skipped reason, report path, and redaction result.
Classify failures as product regression, test bug, account/OTP issue, backend
deployment issue, runner/device issue, or unknown before changing timeouts.
`AGENT-SKIP-001` and `E2EE-SKIP-001` remain skipped in this baseline: do not
implement them, run them, or add them to PR/nightly/release gates.

Historical Agent IM reports write `agent-im-scenario-result.json`, which
summarizes AIM-E2E case statuses (`pass` / `fail` / `skipped`), skipped reasons,
and redaction scan results. The prior P0 happy path was verified on `awiki.info`
with runId `20260614T024413341Z`: `AIM-E2E-001`, `AIM-E2E-002`, and
`AIM-E2E-006` passed; the App received hidden `awiki.message.sync.v1`
`runtime_final` evidence for the CLI peer message. Treat that as historical
evidence only; it does not reactivate Agent IM in the current basic baseline.
