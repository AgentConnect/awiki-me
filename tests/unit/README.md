# Unit Test Domain

`tests/unit/` contains fast AWiki Me tests that do not require a real device,
real backend, or real `awiki-cli` subprocess. This includes pure Dart unit
coverage, widget/provider tests with fakes, and pure E2E harness parser/planning
tests.

Run:

```bash
dart run tests/unit/runner.dart
```

Focused Flutter test arguments can be passed through the same entrypoint:

```bash
dart run tests/unit/runner.dart --name mention
```

Coverage quality gate:

```bash
dart run tests/unit/runner.dart --branch-coverage
dart run tool/test_coverage_gate.dart
```

The floor in `tests/quality/coverage_baseline.json` includes critical per-file
line and branch thresholds; lowering it requires an explicit quality review.
