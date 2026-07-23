# Planned multi-device cases

This file is a non-executable catalog anchor. It does not register tests, provide
test fixtures, or claim remote pass evidence.

The following cases are intentionally planned for Step 3 or a later version:

- `ROOT-TRANSFER-E2E-001`: root-key transfer and management-readiness completion.
- `ROOT-TRANSFER-E2E-002`: root-key transfer retry and idempotent readiness.
- `DEVICE-REVOKE-E2E-001`: permanent exact-device revocation after readiness.
- `MLS-MULTI-DEVICE-E2E-001`: same-DID multi-device MLS lifecycle.
- `MLS-MULTI-DEVICE-E2E-002`: exact-device MLS removal convergence.

Their previous executable Dart implementations depended on the retired
direct-admin Join flow and have been deleted. A future implementation must use
the accepted Step 3 or later contracts and must be registered in the suite
manifest before any of these cases can become active.
