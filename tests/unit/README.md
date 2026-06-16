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
