/// Planned real-product acceptance contract for AWiki Me multi-device Join.
///
/// These cases are intentionally not registered in `suite_manifest.json` yet.
/// They require two independent Core data roots, a real AWiki Me process, a
/// CLI peer, and the `awiki.info` multi-device capability. Promoting them to an
/// executable `--case multi-device` suite must add scenario-owned assertions
/// and case attestations; a fake-backed Widget test must never mark them passed.
const plannedMultiDeviceJoinCaseIds = <String>[
  'DEVICE-JOIN-E2E-001',
  'DEVICE-JOIN-E2E-002',
  'DEVICE-JOIN-E2E-003',
];
