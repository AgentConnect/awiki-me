# Android secure-storage upgrade regression

Owning layer: focused Android native E2E, separate from backend/account suites.
Run only in a disposable emulator and the package `ai.awiki.forensics.storage_lab`.
Both entrypoints reject other package IDs before reading or writing storage.
The fixture contains synthetic identity/root bytes; never copy real App data.

## Fixture builds

Create a disposable Flutter Android project with the package ID above and copy
`fixture.dart` plus the selected entrypoint as `lib/main.dart`. Keep the same
debug signing key/package for each APK, and increase its build number for updates.

- Seed: `seed_v9.dart`, `flutter_secure_storage: 9.2.4`,
  `package_info_plus: 9.0.1` and Flutter. Start once on a fresh fixture installation;
  expect `AWIKI_STORAGE_FIXTURE` with `phase=seed-v9` and `ok=true`.
- Fixed: `verify_fixed.dart`, a path dependency on this App checkout and
  `package_info_plus`. This uses the App's real storage/selection/Scope adapters
  and vendored native plugin, not copied implementations.

Use `flutter build apk --debug --target-platform android-arm64` for each fixture.
Install with `adb -s <explicit-emulator-serial> install -r <apk>`; never use the
attached real phone for these fixtures. Clear/reseed only the disposable fixture
between independent cases. Force-stop/start for each cold restart; do not clear
the fixture in the middle of an upgrade case.

## Required cases

1. **Healthy upgrade**: seed v9 → fixed. Expect initial selection `matches`,
   Scope envelope equality and persisted selection; repeat after cold restart.
2. **Existing damage**: seed v9 → known unpatched 10.3.1 reproduction → fixed.
   The negative control must show `BAD_DECRYPT` reading the old selection while
   the Scope value migrates. Fixed must initially return `absent`, then verify
   explicit selection storage; cold restart must return `matches`.
3. Compare legacy wrapped-key and per-value ciphertext digests before/after the
   fixed update. Fixed reads/writes must preserve the old material. Capture
   digests in memory via `run-as` on the debug fixture; do not log plaintext.

The negative control uses the previous non-recovering migration flow with the
published, unpatched 10.3.1 plugin. Retain its source and APK hash in the run
receipt so a patched control cannot accidentally claim to reproduce the defect.

This probe validates Android migration and state persistence, not real-account
authentication, existing vault/message integrity or other platform keychains.
Those boundaries are covered by the owning unit tests and manual in-place update
of the signed product APK. Never replace a failed vault open with a fresh key.
