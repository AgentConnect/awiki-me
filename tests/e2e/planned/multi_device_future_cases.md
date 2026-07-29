# Planned multi-device cases

This file is a non-executable catalog anchor. It does not register tests, provide
test fixtures, or claim remote pass evidence.

The following cases remain intentionally planned for a later version:

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
