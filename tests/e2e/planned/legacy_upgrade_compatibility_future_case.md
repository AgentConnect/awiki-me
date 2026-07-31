# Published Legacy App Upgrade E2E

`LEGACY-UPGRADE-E2E-001` is a release-only, two-artifact compatibility gate. It is deliberately
not part of ordinary unit or smoke suites because it must install and launch the real published
App and the candidate App against one isolated non-production account.

The source artifact is fixed to AWiki Me `0.1.5+14`, App
`c19a01a5e434ac41ead73915ef7fcbc2a27e3a5a`, Core
`d7c853a986a29e0c0457284a6b2c3d81ec637e10`, and the checked-in release-owner attestation in
`../awiki-system-test/suites/release-artifact-attestations/`.

The release operator uses a clean macOS user data scope, installs the published artifact, creates
one identity, and records non-secret sentinels for the DID, Handle, local identity ID, conversation,
messages, contacts, group membership, unread state, and one attachment. The candidate is then
installed over the old App without deleting Local Application Support or Keychain state.

Passing requires the candidate to complete the Core-owned migration, preserve the same DID/root,
Handle, account and local identity ID, retain every local sentinel and attachment byte, and reopen
normally after a second cold start. The server must expose exactly one ready admin device for the
migrated identity. A retry after a deliberately interrupted first response must converge to that
same device and document; generating a second device key set, losing any local data, changing the
DID, or requiring phone recovery makes the case fail.

Credentials, private keys, access tokens, OTP values, message bodies, and raw database/Vault files
must not enter the report. The detailed operator and artifact provenance rules remain authoritative
in `../awiki-system-test/docs/canonical-conversation-upgrade-system-tests.md`.
