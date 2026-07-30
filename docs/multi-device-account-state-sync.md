# Multi-device account-state synchronization

AWiki Me treats User Service as the authority for four account-scoped domains:

- Profile
- Agent Inventory
- Agent Status
- Device Registry display state

These domains are deliberately separate from ordinary-message synchronization.
Message Service does not carry their payloads.

## Availability

After a deployment enables multi-device support, ordinary message sync and
account-state reconciliation are default-on for every authenticated account and
valid device. AWiki Me does not select an account allowlist, device cohort, or
percentage rollout. `AWIKI_SYNC_V2_READ=false` is reserved for a global
emergency rollback; the separate Direct/Group E2EE flags remain default-off and
do not control this plain synchronization path.

Operator-only recovery fault injection, cleanup, and OTP tooling may still use
dedicated test-account allowlists. Those controls protect destructive test
actions and are not product entitlements.

## Reconciliation contract

For an authenticated session with a typed Core binding, the App captures one
immutable fence:

```text
owner_identity_id + account_id + current_did + session generation
```

It then performs:

```text
manifest M1
  -> fetch changed domains in parallel
  -> atomically replace each successful domain cache
  -> manifest M2
  -> refetch only domains whose M2 version is greater than M1
  -> publish committed cache projections
```

Versions remain canonical decimal strings throughout Dart and native Core.
They are never converted through JavaScript numbers or Dart `int` at the
account-state boundary.

One domain failure does not discard another domain's committed cache. Requests
are coalesced behind one active reconciliation, failures are retried with
backoff, and every await is fenced before a projection can be published.

The normal triggers are authenticated startup, foreground resume, realtime
reconnect, foreground catch-up, manual refresh, and successful local
Profile/Agent/Device mutations.

## Local projection ownership

The product SQLite cache is keyed by stable `owner_identity_id + account_id`.
DID and Handle are not cache owners.

- The Agent provider uses that same stable account key for its loaded/cache
  owner. Applying an authoritative Agent Inventory snapshot marks that exact
  account owner and session operation as loaded, so an Agent creation can add
  its short-lived pending intent immediately instead of starting a second
  remote Inventory read. Handle/DID cache keys remain only for legacy sessions
  that do not yet have a typed account binding.
- Agent Inventory and Agent Status retain independent versions. Archived or
  inactive Agents remain in the durable Inventory cache but are filtered from
  the visible Agent list.
- The visible Agent projection merges authoritative topology, remote status,
  and Core-owned control overlays in that order.
- Profile UI reads the committed Profile cache.
- Device UI may display the newer of the account cache and a fresh Core
  Registry read, comparing arbitrary-precision string versions.

The one-way legacy Agent bridge can seed the first frame from DID-keyed rows.
That seed is explicitly marked non-authoritative, so even a server manifest at
version `0` forces an authoritative Inventory fetch and can remove stale rows.

## Device security boundary

Account-state Registry data is display-only. Device authorization, Join,
revoke, root transfer, and management-readiness decisions always use a fresh
Registry obtained through the public IM Core SDK.

Production composition loads Registry through
`DeviceManagementCorePort.identityDeviceRegistry`. The HTTP account-state
adapter owns Manifest, Agent, and Profile RPC parsing; it does not bypass the
Core Registry DTO chain in production.

Account-state RPCs accept only the device-bound bearer obtained from IM Core's
active messaging session. There is no ordinary account-JWT fallback.

## Non-goals

This contract does not add message edit, recall, delete, tombstone, Push, or
E2EE/MLS multi-device synchronization. Friends and Groups retain their existing
refresh paths.
