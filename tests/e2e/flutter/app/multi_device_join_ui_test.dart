/// Planned real-product acceptance contract for AWiki Me multi-device Join.
///
/// These cases remain outside the executable `multi-device` suite. That suite
/// currently proves only the local production-bootstrap capability gate. Real
/// Join requires two independent Core data roots, a real AWiki Me process, a
/// CLI admin, a one-time OTP, and the deployed `awiki.info` capability. Each
/// case must add scenario-owned assertions before activation; neither the local
/// gate nor a fake-backed Widget test may mark remote Join/SAS as passed.
const plannedMultiDeviceJoinCaseIds = <String>[
  'DEVICE-JOIN-E2E-001',
  'DEVICE-JOIN-E2E-002',
  'DEVICE-JOIN-E2E-003',
];
