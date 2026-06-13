# E2E Test Domain

`tests/e2e_test/` contains end-to-end harnesses, scenarios, configs, and mobile flow
files. E2E tests may use the real App, `awiki-cli-rs2` as a CLI peer, and a real
non-production backend. Keep secrets and generated state out of Git.

Structure:

- `harness/`: desktop/mobile runners and shared E2E orchestration code.
- `configs/`: checked-in example configs only; local configs are ignored.
- `mobile/maestro/`: Maestro flows used by mobile E2E.
- `scenarios/`: future reusable E2E scenario tests.

Desktop dry-run:

```bash
dart run tests/e2e_test/harness/desktop_e2e_runner.dart --platform=macos --dry-run
```

Mobile dry-run:

```bash
dart run tests/e2e_test/harness/mobile_e2e_runner.dart \
  --config tests/e2e_test/configs/mobile.example.yaml \
  --dry-run
```
