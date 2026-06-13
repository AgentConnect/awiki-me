# Unit Test Domain

`tests/unit_test/` contains fast AWiki Me tests that do not require a real device,
real backend, or real `awiki-cli` subprocess. This includes pure Dart unit
coverage, widget/provider tests with fakes, and pure E2E harness parser/planning
tests.

Run:

```bash
flutter test tests/unit_test
```
