# Android Remote Push

AWiki Me currently integrates the Android Aliyun EMAS Push transport. This
slice initializes the official Android SDK, obtains the EMAS DeviceId, creates
the message notification channel, normalizes native callbacks, and persists up
to 32 minimal sync/open events while the Flutter engine is unavailable.

The equivalent iOS transport is documented in
[`ios-remote-push.md`](ios-remote-push.md); both platforms share the same Dart
client contract while keeping their native SDK lifecycle and credentials
separate.

## Local configuration

Copy `android/emas.properties.example` to `android/emas.properties` and set:

```properties
debug.enabled=true
debug.appKey=YOUR_ANDROID_DEBUG_EMAS_APP_KEY
debug.appSecret=YOUR_ANDROID_DEBUG_EMAS_APP_SECRET
debug.logDeviceId=false

profile.enabled=false
release.enabled=false
appRsaSecret=YOUR_EMAS_APP_RSA_SECRET
```

`android/emas.properties` is ignored by Git. `appKey` and `appSecret` are
compiled into the Android application because the mobile SDK must initialize
before Flutter starts. Treat them as mobile application credentials, not as
server credentials.

The Push SDK does not consume `appRsaSecret`. It remains only in the ignored
local file for future EMAS APM or remote-log integration and is not packaged by
the current Gradle configuration.

Each build type has an independent `enabled`, `appKey`, and `appSecret` entry.
Release remains disabled unless release credentials are explicitly configured.

The EMAS application package must match the build variant:

| Variant | Android application ID |
| --- | --- |
| Debug / Profile | `ai.awiki.awikime.dev` |
| Release | `ai.awiki.awikime` |

An AppKey configured for the other package can fail registration with
`304 / INVALID_PACKAGE`.

## Transport validation

The routine Dart log prints only the DeviceId suffix. For a local console test,
set `debug.logDeviceId=true` and inspect Android Debug logs for:

```text
AWikiRemotePush: EMAS DeviceId: ...
```

Use that DeviceId in the EMAS console to send an Android `NOTICE`. Configure
the notification channel as:

```text
awiki_me_messages
```

The debug log records callback kinds without logging notification payloads.
Notification-open callbacks are stored natively when Flutter is unavailable
and delivered after the process-level MethodChannel is attached. The native
queue retains only the event kind, message ID, and allowlisted envelope fields,
expires entries after 24 hours, and never persists notification text or URLs.
Events remain queued under a stable delivery ID until the tenant-aware
coordinator completes Core sync and any required routing, then explicitly
acknowledges successful handling.

When a core-channel notification callback arrives while the device is
non-interactive, the Android receiver takes a three-second screen wake lock so
the lock screen can present the high-importance notification. It does not use a
full-screen intent: chat messages are not calls or alarms, and Android reserves
that intrusive presentation for urgent time-sensitive use cases. Device and
channel lock-screen settings remain authoritative.

## Authenticated installation lifecycle

An active authenticated App session owns exactly one accepted Android Push
installation. After session activation, AWiki Me initializes the native
transport and calls the authenticated public RPC endpoint:

```text
POST /user-service/v1/push/rpc
```

The adapter uses `upsert_installation` with only these safe binding fields:

- `provider` (`aliyun_emas`);
- `provider_device_id`;
- `platform` (`android`);
- optional `logical_device_id`; and
- optional Android `app_id` (the EMAS AppKey).

The response must echo the bound values and return an
`installation_id` with status `active`; a mismatched response fails closed.
The App never sends an EMAS AppSecret, Alibaba Cloud RAM AccessKeyId, or
AccessKeySecret to this endpoint. On logout, account deletion, authentication
revocation, or identity replacement, the old installation is made locally
inactive before asynchronous work can complete. When valid authorization is
still available, `disable_installation(installation_id)` is attempted as
best-effort cleanup. Authentication revocation can make that remote cleanup
impossible; the next authenticated identity therefore reassigns the same
provider DeviceId through the owner-aware unique upsert. Registration changes
and App resume refresh the current binding. Session generation and tenant
fences prevent a delayed bind or disable from being accepted by another
identity.

## Message delivery and acknowledgement

Remote Push is a dirty hint, not a message payload or a second message source of
truth. A message callback, notification callback, or notification open requests
the same `MessageSyncCoordinator` Core sync used by other reliable triggers.
Only Core-committed messages may update the conversation list, timeline,
unread state, or navigation.

For Push-triggered sync, EMAS `NOTICE` is the sole Android presentation owner.
AWiki Me suppresses its normal message-system-notification path for the entire
coalesced sync, including queued work and automatic retry. Projection, normal
message deduplication, and Coding Agent terminal deduplication still run. This
keeps foreground delivery silent and prevents a WebSocket plus Push race from
creating a second App-owned notification.

The App acknowledges native delivery IDs only after Core sync succeeds, local
conversation/Join/timeline refresh completes, and any notification-open routing
finishes for the same active session. Offline, failed, stale-session, or
stale-tenant work remains pending. A later real trigger such as activation,
resume, another Push event, or registration refresh retries it; the coordinator
does not busy-loop.

## Safe notification-open matching

Notification-open routing reads only `extraMap.mid` and `extraMap.exp`.
`mid` must be the versioned opaque message reference produced from a safe
logical, remote, or local message ID; it is not a raw message ID,
conversation ID, DID, URL, title, or body. `exp` is mandatory and must be a
valid future Unix timestamp.

After Core sync commits, the App independently derives the opaque reference
from the committed message identifiers. A match may open that committed
message's canonical conversation. An absent, malformed, expired, unmatched, or
ambiguous hint falls back to the conversation list. All other provider payload
metadata is ignored for navigation. SessionEpoch and tenant checks run before
and after asynchronous list/open work; stale routing fails without
acknowledging the event.

## Supported scope and remaining limitations

This implementation supports authenticated one-to-one direct-message dirty
hints, successful-sync acknowledgement, exact-conversation notification-open
routing, and WebSocket/Push convergence in the AWiki Me Android client.
Group-message routing, marketing/broadcast notifications, arbitrary deep links,
and Push-carried chat content are outside this contract.

The implementation and deterministic regressions do not by themselves prove a
production Push. The planned physical-device contracts are
`ANDROID-PUSH-PRODUCT-E2E-001` and `ANDROID-PUSH-NATIVE-E2E-001`; they still
require deployed User Service installation RPC, Message Service outbox/EMAS
delivery, real credentials, and end-to-end evidence on a named physical
Android device.

This Feature includes only the Aliyun core channel. FCM and the Huawei, Honor,
Xiaomi, OPPO, vivo, and other auxiliary channels are deferred. Delivery after
process death or under OEM background restrictions therefore remains outside
the current acceptance boundary.
Notification permission denial must be recovered in Android settings. Android
force-stop suppresses Push until the user launches the App again and is not
supported.

Server-side delivery needs Alibaba Cloud RAM/OpenAPI credentials, owned by the
server deployment. Never put an AccessKeyId or AccessKeySecret in this
application, source control, logs, screenshots, or E2E evidence. AppKey and
AppSecret provisioning, EMAS package/application alignment, outbox deployment,
OEM background policy, permission recovery, and the Nubia P0110 (or explicitly
named equivalent) physical-device run remain release-environment obligations.
