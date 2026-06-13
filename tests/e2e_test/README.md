# E2E Test Domain

`tests/e2e_test/` contains end-to-end harnesses, scenarios, configs, and mobile flow
files. E2E tests may use the real App, `awiki-cli-rs2` as a CLI peer, and a real
non-production backend. Keep secrets and generated state out of Git.

Structure:

- `harness/`: desktop/mobile runners and shared E2E orchestration code.
- `configs/`: checked-in example configs only; local configs are ignored.
- `mobile/maestro/`: Maestro flows used by mobile E2E.
- `scenarios/`: reusable E2E scenario code. Agent IM currently provides an App bootstrap hook used by integration smoke and future full E2E flows.

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
runs. Dry-run reports include `cli-peer-plan.json`, which lists the isolated
`awiki-cli-rs2` peer workspace and ordinary `msg send` command without secret
values. Local configs, generated CLI workspaces, and `.e2e/` reports remain
ignored.

Mobile dry-run:

```bash
dart run tests/e2e_test/harness/mobile_e2e_runner.dart \
  --config tests/e2e_test/configs/mobile.example.yaml \
  --dry-run
```


Agent IM scenario dry-run and real runs also write `agent-im-scenario-result.json`.
That file summarizes AIM-E2E case statuses (`pass` / `fail` / `skipped`),
records skipped reasons for remote-dependent checks, and includes the local
redaction scan result. Real `awiki.info` proof still requires the Step 06 remote
runbook evidence before a full happy-path pass can be claimed.
