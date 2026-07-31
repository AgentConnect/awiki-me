# Android EMAS Direct-Message MVP Design

## Goal

Complete the Android Aliyun EMAS product loop for:

- one-to-one incoming AWiki messages; and
- Coding Agent replies that arrive as ordinary one-to-one messages.

The MVP must bind the Android EMAS installation to the active authenticated
AWiki identity, use remote Push only as a wake-up hint for reliable Core sync,
avoid duplicate presentation, and retain unacknowledged Push events until Core
sync succeeds.

## Scope

### Included

- Android Debug/Profile and Release EMAS registration metadata.
- Authenticated User Service installation upsert and disable.
- Session-, tenant-, and DID-fenced installation ownership.
- Live, background-open, and cold-start remote Push event handling.
- Reliable V2 message sync through the existing `MessageSyncCoordinator`.
- Successful-sync acknowledgement of the native pending-event queue.
- Suppression of a second App-generated notification when EMAS `NOTICE`
  already owns Android system presentation.
- Deterministic unit, provider, widget/bootstrap, native-configuration, and
  planned real-device E2E coverage.

### Excluded

- Group messages.
- Account/system notifications.
- Structured Coding Agent terminal-status payloads.
- Huawei, Honor, Xiaomi, OPPO, vivo, Meizu, FCM, or other auxiliary channels.
- Production deployment, secret provisioning, EMAS console configuration, and
  live provider sends.
- Changes to iOS, macOS, Windows, web, generated platform registrants, or Rust
  IM Core.

## Existing Foundation

The Android runner already initializes `alicloud-android-push:3.10.1`, creates
the `awiki_me_messages` notification channel, exposes the EMAS DeviceId, emits
normalized callbacks, and retains up to 32 minimal `notification_opened` or
`message_received` events for 24 hours.

The current App initializes the remote Push client globally, but it only logs
the registration suffix and event kind. It does not bind the DeviceId to an
authenticated identity, trigger reliable sync, or acknowledge pending events.

User Service `release/0714` already owns authenticated installation
`upsert_installation` and `disable_installation` RPC methods plus internal
delivery-target resolution. Message Service `release/0714` already owns the
Android EMAS `NOTICE` provider and outbox retry/dead-letter behavior.

## Considered Approaches

### 1. Put all behavior in `TenantAwareAwikiMeApp`

This minimizes new types but couples platform Push, tenant runtime creation,
authentication, reliable sync, and navigation to one widget. It also makes
session fencing and deterministic tests difficult.

### 2. Application coordinators with Riverpod lifecycle integration

This keeps the platform client provider-neutral, puts installation ownership
behind a User Service port, and lets the authenticated App runtime own
session-sensitive activation and teardown. A presentation adapter delegates
remote wake-up to the existing reliable sync coordinator.

This is the selected approach.

### 3. Move Push ownership into Rust IM Core

This would make mobile platform credentials and lifecycle part of the
cross-platform correctness core. It conflicts with the current boundary in
which Core owns committed message truth while the App runtime owns platform
Push and presentation.

## Architecture

### Remote Push registration

`RemotePushRegistration` will contain:

- provider name;
- provider DeviceId;
- platform;
- EMAS AppKey as `appId`; and
- optional logical AWiki device ID when the active session exposes one.

The Android MethodChannel will expose the configured AppKey without exposing
the AppSecret. The AppKey is required by User Service so Message Service can
select the correct EMAS Android application for each installation.

### Installation lifecycle coordinator

`RemotePushInstallationCoordinator` will depend on:

- `RemotePushClient`; and
- a `PushInstallationPort` implemented by an authenticated User Service
  adapter.

It will serialize lifecycle mutations and provide:

- `bindActiveSession()`: initialize Push and upsert the current registration;
- `refreshActiveSession()`: re-upsert after `registration_changed`; and
- `disableActiveInstallation()`: disable the last successful installation.

The coordinator stores only the server installation ID in memory. It does not
persist bearer tokens, DeviceIds, AppSecrets, or provider payloads.

The App runtime will bind only after the session epoch is active. It will make
a best-effort disable before normal logout, identity replacement, tenant
replacement, or credential deletion clears authenticated state. Installation
failures must not block login or logout.

If authorization has already been revoked, remote disable may be impossible.
The App must still fence the local session and stop processing events. A later
successful login reassigns the provider DeviceId through User Service's unique
provider/device upsert. EMAS notification content remains generic and contains
no message body.

### Remote Push sync coordinator

`RemotePushMessageSyncCoordinator` will consume:

- the `RemotePushClient` event stream and pending-event snapshot; and
- a typed remote-Push sync request exposed by the existing
  `MessageSyncCoordinator`.

It reacts only to:

- `message_received`;
- `notification_received`;
- `notification_received_in_app`; and
- `notification_opened`.

Registration changes refresh the active installation instead of triggering
message sync. Notification removals do nothing.

For each accepted event batch, the coordinator requests immediate reliable
sync with reason `remote_push`. It acknowledges the corresponding delivery IDs
only when the session-fenced Core sync finishes in `idle` or `changed` status
and the App projection refresh completes. Retryable failure, recovery-required,
auth-revoked, stale-session, or thrown-error outcomes retain the events.

Pending events are drained after a session becomes active and again when the
App resumes. Operations are serialized so a live callback and a cold-start
drain cannot acknowledge each other incorrectly.

### Reliable sync and presentation

The existing `MessageSyncCoordinator` remains the single owner of:

- Core V2 message sync;
- session fencing;
- conversation projection refresh;
- committed incoming-message identity deduplication; and
- local notification presentation.

It will expose a typed remote-Push request that reports whether the full sync
and projection refresh succeeded. Remote-Push requests also carry a
presentation-suppression flag.

For a remote-Push-triggered sync:

- committed message identities are still recorded in the existing bounded
  deduplicator;
- conversation and chat projections are refreshed normally; and
- App-generated banners/system notifications are suppressed for that sync
  because EMAS `NOTICE` already owns Android system presentation.

Suppression is combined with logical OR when requests coalesce. This favors
avoiding a duplicate notification. A normal WebSocket or periodic sync that
does not coalesce with remote Push keeps the existing presentation behavior.

### Notification opening

Tapping an EMAS notification launches AWiki Me and triggers session-fenced
reliable sync. The `notification_opened` event supplies only the allowlisted
opaque `mid` message reference already produced by Message Service.

After Core commit, the presentation coordinator computes the same
`awiki-push-envelope-v1` opaque message reference for each committed incoming
logical, remote, and local message ID. An exact match yields the committed
message's local conversation ID. The App opens that conversation only while the
captured session epoch, owner DID, and tenant storage scope remain current.

If the opened reference is absent, expired, malformed, or not present in the
sync result, the App safely lands on the authenticated conversation list. No
raw DID, conversation ID, URL, token, or message body is added to the Push
payload.

## Data Flow

1. Android starts and initializes the EMAS SDK before Flutter.
2. Flutter obtains `providerDeviceId`, platform, and AppKey.
3. App session activation completes and establishes the current session epoch.
4. Installation coordinator upserts the registration through authenticated
   User Service RPC.
5. Message Service commits an incoming direct message and its existing outbox
   worker sends a generic Android EMAS `NOTICE`.
6. Android displays the EMAS notification and forwards a normalized event when
   the process is available or later opened.
7. Remote Push sync coordinator requests immediate reliable Core sync with
   notification presentation suppressed.
8. Core commits the authoritative message; App projections refresh, record
   notification identities, and resolve an opened opaque message reference to
   a local conversation when possible.
9. Only after successful projection refresh and session-fenced navigation does
   the App acknowledge the native delivery IDs.
10. Logout or identity/tenant replacement disables the active installation
    best-effort before clearing authenticated state.

## Error and Security Semantics

- Push payloads are dirty hints, never message truth.
- A provider callback cannot write directly to conversation or chat state.
- A failed or non-terminal sync never acknowledges pending events.
- Stale-session completions cannot mutate or acknowledge the new session.
- Installation RPC failure is non-fatal to authentication and is retried on
  resume or registration change.
- Full DeviceIds, notification text, URLs, bearer tokens, AppSecrets, RAM
  credentials, and User Service internal tokens are not logged.
- The server RAM AccessKey and AccessKeySecret never enter the App repository,
  APK, tests, or documentation examples.
- Android force-stop remains unsupported until the user manually launches the
  App again.

## Testing and Acceptance

### Deterministic repository tests

- Platform registration includes Android AppKey but never AppSecret.
- Installation upsert uses the authenticated User Service RPC and exact
  provider/platform/app identifiers.
- Login binds once; registration change refreshes; logout disables before
  session clear.
- Installation failures do not fail login/logout.
- Accepted Push events request immediate `remote_push` sync.
- A successful sync acknowledges exactly the handled delivery IDs.
- Retryable, recovery-required, auth-revoked, stale-session, and thrown-error
  outcomes do not acknowledge.
- Cold-start pending events drain once and live duplicates do not re-run.
- Remote-Push sync refreshes projections without an App-generated notification.
- An exact opened opaque message reference navigates to the committed local
  conversation; missing, malformed, or stale references fall back to the
  conversation list.
- Existing WebSocket and normal reliable-sync notification behavior remains
  unchanged.
- Android configuration, event normalization, and 24-hour bounded persistence
  tests stay green.

### Cross-service system coverage

`awiki-system-test` must cover authenticated upsert, disable, owner isolation,
internal resolve, and inactive-installation exclusion. If that repository is
not locally available during implementation, the App change remains
`UNVERIFIED` at the cross-service layer and must not be represented as complete.

### Physical Nubia P0110 acceptance

The real-device gate requires one non-production account and records:

- EMAS SDK registration and a non-sensitive DeviceId suffix;
- foreground receipt with silent App refresh;
- background notification with no duplicate App notification;
- terminated-process notification followed by launch and message sync;
- offline/retry recovery without event loss;
- WebSocket plus Push convergence to one committed message;
- logout followed by proof that the disabled installation is no longer
  resolved for the old DID; and
- notification permission denial and recovery through Android settings.

Provider acceptance, an EMAS console send, or a server outbox `done` state does
not by itself pass the product gate. The phone must display the notification
and the App must project the corresponding committed message exactly once.

## Delivery Boundaries

The implementation branch starts from current `origin/release/0714` in the
isolated `codex/android-emas-mvp` worktree. It will not modify or merge the
existing PR #3 branch, the dirty iOS Push prototype, or any local Pod lock
changes.

Commit, push, PR creation, deployment, secret configuration, and live provider
testing remain separate delivery actions. This design authorizes only the
repository implementation and deterministic local verification until the user
explicitly approves a later external action.
