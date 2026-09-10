# Unit Test Support

Place reusable fakes and builders that are only needed by `tests/unit/` here.
Cross-domain helpers should be kept small and documented at their call site.

`app_shell_ready.dart` waits for the update-policy gate, runtime initialization,
expected session state, and the rendered onboarding/authenticated surface. Use it
before AppShell assertions that require startup to finish; a single `pump()` is
not a readiness contract. It deliberately avoids `pumpAndSettle`, since a valid
connection or recovery indicator may animate continuously.
