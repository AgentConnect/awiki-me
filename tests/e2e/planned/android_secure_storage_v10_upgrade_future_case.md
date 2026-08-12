# Android Secure Storage v10 Upgrade E2E

`ANDROID-SECURE-STORAGE-UPGRADE-E2E-001` is the release gate for the Android
`flutter_secure_storage` 9.2.4 to 10.x cutover. It cannot be replaced by a Dart
fake, a fresh install, or a device whose App data was cleared.

The source artifact must be an attested AWiki Me build that still uses 9.2.4.
The operator uses a dedicated Android test profile and an isolated
non-production identity, records only hashes/opaque IDs for the existing
Storage Scope, DID/vault root, and one non-secret App-state sentinel, then
force-stops the App. The candidate is installed with overwrite flags that
preserve App data; uninstall and `pm clear` are prohibited.

The first candidate launch must migrate the exact Scope account and App-state
key into two distinct fixed v10 `storageNamespace` targets. The report must
prove target-first read, exact v9 source read, target write, and target read-back
equality in that order without recording secret values. The first compatibility
release must retain the encrypted source key because same-process read-back is
not cross-process durability evidence. A malformed source, failed target write, or read-back mismatch must
leave the source intact and block startup. A successful target with failed
future cleanup is reported as retained encrypted residue, not data loss.

After a force-stop, the second candidate launch must reopen the same Scope and
identity/session projection from the target without registration, OTP, local
data recovery, root-key generation, or v9 source access. Unrelated legacy keys
and global KeyStore material must remain untouched until an explicitly approved
full local-data deletion.

This case is currently `UNVERIFIED` until run on a dedicated Android profile
with both attested artifacts. Unit coverage owns the deterministic migration
state machine and failure injection. No cross-service system test is required
because the migration has no server RPC or database effect; User Service and
Message Service must receive zero calls during this gate.
