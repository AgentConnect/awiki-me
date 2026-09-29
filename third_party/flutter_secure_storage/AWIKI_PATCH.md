# Pinned Android namespace correction

Source: the published `flutter_secure_storage` 10.3.1 package. Included runtime
files (`lib/`, `android/`, pubspec and license) are unchanged except for four
lines in `android/src/main/java/com/it_nomads/fluttersecurestorage/FlutterSecureStorage.java`.
Other platforms continue using the same federated packages from pubspec.lock.
Upstream development-only analysis configuration is omitted; its unneeded
`very_good_analysis` dev dependency is not added to the App dependency graph.

Each backup-migration branch must open wrapped-key preferences using
`config.getEffectiveKeyStoragePrefsName()`, as the cipher implementations already
do. The upstream literal `FlutterSecureKeyStorage` wrongly deletes legacy
wrapped AES keys when a fresh, unrelated namespace is initialized.

Keep `resetOnError=false`, verified copy-on-read and the existing namespace
names. Do not edit the user's global pub cache, clear old preferences, disable
encryption or regenerate Scope secrets as a workaround.

The 2026-09-28 Android 16 reproduction covers v9.2.4 CBC App state plus ESP Scope
storage. The unpatched v10.3.1 upgrade preserves old ciphertext but replaces its
wrapped AES key and fails with BAD_DECRYPT. With this correction, the old key
and ciphertext survive and both migrated values remain readable after restart.
The runtime's non-biometric branch is exercised; biometric migration branches
are corrected consistently but are not used by AWiki's current options.

This local copy makes the fix part of a reproducible build. Remove it only after
pinning an upstream release that includes the namespace correction and passes
the same upgrade and existing-damage regression tests. Do not publish this copy
as an upstream package.
