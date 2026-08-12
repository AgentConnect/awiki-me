# Planned multi-device cases

This file is a non-executable catalog anchor. It does not register tests, provide
test fixtures, or claim remote pass evidence.

The following cases remain intentionally planned for a later version:

- `ANDROID-DEVICE-JOIN-E2E-001`: physical Android ordinary Join through
  post-approval local activation with the Group E2EE capability retained.
- `ROOT-TRANSFER-E2E-002`: receiver-local completion recovery after restart.
- `MLS-MULTI-DEVICE-E2E-001`: same-DID multi-device MLS lifecycle.

Their previous executable Dart implementations depended on the retired
direct-admin Join flow and have been deleted. A future implementation must use
the accepted later-version contracts and must be registered in the suite
manifest before any of these cases can become active. In particular,
`ROOT-TRANSFER-E2E-002` may recover only the receiver's persisted local
completion coordinator; it must not reintroduce sender retry, an imported ACK
or Reply, a second user-presence prompt, or public original-message-ID retry
semantics.

`ANDROID-DEVICE-JOIN-E2E-001` requires a named physical Android device and an
independent existing admin device on an approved tenant. It must prove that an
Android native Core compiled with `group-e2ee` leaves the SAS page after remote
approval, restores the exact active member after restart, and retains the
Group E2EE capability while ordinary Direct messages and newly created groups
remain default-plain. A remote `consumed` result, disabling the runtime gate,
an emulator, or clearing App data before activation is not passing evidence.
