/// Planned real-product acceptance contract for AWiki Me Handle Recovery.
///
/// These cases are intentionally absent from `suite_manifest.json`. They need
/// two isolated device roots, exact purpose/Handle/domain/Session-bound SMS
/// exchanges, real user presence, a real old admin, durable local activation
/// retry, and deployed recovery cutover convergence on `awiki.info`.
const plannedHandleRecoveryCaseIds = <String>[
  'HANDLE-RECOVERY-E2E-001',
  'HANDLE-RECOVERY-E2E-002',
  'HANDLE-RECOVERY-E2E-003',
];
