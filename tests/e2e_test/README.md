# E2E Test Domain

`tests/e2e_test/` contains end-to-end harnesses, scenarios, configs, and mobile flow
files. E2E tests may use the real App, `awiki-cli-rs2` as a CLI peer, and a real
non-production backend. Keep secrets and generated state out of Git.

Structure:

- `harness/`: desktop/mobile runners and shared E2E orchestration code.
- `configs/`: checked-in example configs only; local configs are ignored.
- `mobile/maestro/`: Maestro flows used by mobile E2E.
- `scenarios/`: reusable E2E scenario code. Agent IM provides the delegated-message
  App bootstrap, CLI peer send, App return wait, and remote evidence gate.

Desktop dry-run:

```bash
dart run tests/e2e_test/harness/desktop_e2e_runner.dart --platform=macos --dry-run
```

Agent IM delegated-message dry-run:

```bash
dart run tests/e2e_test/harness/desktop_e2e_runner.dart \
  --platform=macos \
  --scenario=agent-im-delegated-message \
  --config tests/e2e_test/configs/agent_im_delegated.example.yaml \
  --dry-run
```

The Agent IM scenario config records environment variable names only. The App bootstrap scenario hook lives in `tests/e2e_test/scenarios/agent_im_delegated_message/` and is exercised by `integration_test/agent_im_delegated_message_e2e_test.dart`. Copy the
example to `tests/e2e_test/configs/agent_im_delegated.local.yaml` for real local
runs. Dry-run reports include `cli-peer-plan.json`, which lists the configured
`awiki-cli-rs2` peer workspace and ordinary `msg send` command without secret
values. For real runs, keep `cliPeer.workspaceRoot` on a persistent ignored path
such as `.e2e/agent-im/cli-peer`: the harness first tries `id refresh-token` and
`id status` for that existing peer identity, and only falls back to OTP-based
`id recover` / `id register` when the reusable identity is not available. The CLI subprocess uses
`<cliPeer.workspaceRoot>/home` as `HOME`, which prevents the latest
`awiki-cli-rs2` from importing legacy `awiki-agent-id-message` state from the
developer's real home directory. Non-dry-run remote evidence collection writes
`remote-evidence-result.json` and `remote-*.log` files with redacted `ssh ali`
summaries filtered by runId. For the P0 Agent IM gate,
`remote-evidence-result.json` must pass all required stages:
`daemon_bootstrap_received`, `delegated_key_imported`, `hermes_agent_ready`,
`cli_message_received`, `hermes_runtime_finished`, and `summary_return_sent`.
Local configs, generated CLI workspaces, and `.e2e/` reports remain ignored.

Mobile dry-run:

```bash
dart run tests/e2e_test/harness/mobile_e2e_runner.dart \
  --config tests/e2e_test/configs/mobile.example.yaml \
  --dry-run
```


Agent IM scenario dry-run and real runs also write `agent-im-scenario-result.json`.
That file summarizes AIM-E2E case statuses (`pass` / `fail` / `skipped`),
records skipped reasons for non-P0 follow-ups, and includes the local redaction
scan result. The current P0 happy path was verified on `awiki.info` with runId
`20260614T024413341Z`: `AIM-E2E-001`, `AIM-E2E-002`, and `AIM-E2E-006` passed;
the App received hidden `awiki.message.sync.v1` `runtime_final` evidence for the
CLI peer message. Daemon restart/cursor recovery, E2EE opaque boundaries,
delegated DID revoke behavior, and unknown payload negative injection are still
P1/P2 follow-ups and may remain `skipped` without invalidating the P0 gate.
