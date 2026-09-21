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

Keep the ignored file owner-only when using the Release packaging worker:

```bash
chmod 600 android/emas.properties
```

The Push SDK does not consume `appRsaSecret`. It remains only in the ignored
local file for future EMAS APM or remote-log integration and is not packaged by
the current Gradle configuration.

Each build type has an independent `enabled`, `appKey`, and `appSecret` entry.
Release remains disabled unless release credentials are explicitly configured.

## GitHub Actions Release configuration

`scripts/package_app.sh` dispatches an immutable GitHub Actions build; it does
not upload a developer's ignored `android/emas.properties`. The
`app-packaging` GitHub Environment must therefore define these Environment
Secrets:

```text
AWIKI_ANDROID_EMAS_APP_KEY
AWIKI_ANDROID_EMAS_APP_SECRET
```

For the `android-arm64` matrix entry, the workflow uses only those two values
to generate a temporary owner-only Release configuration. Debug/Profile
credentials and `appRsaSecret` are not copied into CI. The Android Release
worker validates that `release.enabled=true`, both credentials are real rather
than placeholders, and the file is not group/world-readable before starting
the expensive native build. Missing or invalid configuration fails the package
instead of silently producing an EMAS-disabled APK.

The workflow removes `android/emas.properties`, `android/key.properties`, and
the temporary upload keystore in an `always()` cleanup step. Credentials must
never be passed as `workflow_dispatch` inputs or written to package metadata,
logs, caches, or uploaded artifacts.

The package workflow controller runs from the repository default branch. A
change to `.github/workflows/package-app.yml` does not affect packaging until
that workflow change is present on the default branch, even when `app_ref`
points at a `release/*` commit.

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

## Delivery diagnostics

### Local physical-device build

Use a local Android Debug build for development diagnostics, not the release
packaging workflow. `tool/run_android_notify_diagnostic.dart` runs the real App
bootstrap with a separate `notify-diagnostic` directory inside the development
App's support directory. It retains the normal platform secret store and real
EMAS, authentication, sync, and navigation adapters. It refuses non-Android,
non-Debug, or `AWIKI_E2E` builds; it does not import an identity or fake events.
Existing development state and the production application's data remain separate.

```sh
flutter build apk --debug --target-platform android-arm64 \
  --target tool/run_android_notify_diagnostic.dart
```

Provision ignored `android/emas.properties` with the existing **debug** EMAS
application configuration, and prepare the matching Android Core library using
the repository's development dependency setup. Compare the APK's package and
signing certificate with an installed development App before an authorized
in-place installation. A signing mismatch is a blocker, not permission to
uninstall or reset app data. The isolated directory requires normal user login
or device join before account-backed push can be tested. Keep that authorization
separate from building/installing the diagnostic APK.

This manual diagnostic entry point is not a product E2E test or release artifact.

### Urgent channel preflight (development only)

`UrgentNotificationChannel` and `ForegroundUrgentCueController` implement the
Android platform portion of the text Notify proposal. They are **not yet wired
to incoming messages or account settings**. The caller must authorize a committed
Core message and enforce account preference, freshness, rate limits and durable
message-level deduplication before invoking the controller. No Push payload or
text keyword is authority to start it.

The channel is `awiki_me_notify_urgent_v1`, created only by explicit setup. Existing
channel choices are preserved. Foreground sound uses the channel's notification
sound and notification audio usage, not a ringtone/call/alarm fallback. Permission
denial, missing/disabled/downgraded channels and background lifecycle suppress the
cue. DND (including priority mode) conservatively suppresses sound and vibration.
Silent mode suppresses both; vibrate mode suppresses sound. An active cue rechecks
system choices every 250 ms and never restarts sound when a restriction is lifted.
The caller stops it on pause, close, navigation, logout and account/preference
changes. A monotonic 60-second ceiling and single active window prevent a second
start from extending a current cue. This window is not the durable message
presentation ledger; that integration remains required.

Debug builds alone contain `push.UrgentNotificationProbeActivity`, opened manually
with ADB. It creates the channel and exposes explicit buttons for foreground
cue/stop, one local notification, updating that same notification, and the system
channel settings. It has no account access and does not send or synthesize IM
messages. Its fixed test notification ID with `onlyAlertOnce` tests **App-owned**
Android notifications only; it proves nothing about EMAS NOTICE retries or vendor
offline delivery. Profile/Release do not contain this Activity or manifest entry.

```sh
adb -s <authorized-device> shell am start \
  -n ai.awiki.awikime.dev/ai.awiki.awikime.push.UrgentNotificationProbeActivity
```

Run `:app:testDebugUnitTest` for policy/deadline coverage. Physical acceptance must
separately report foreground lifecycle, local system channel, EMAS channel mapping,
actual sound and actual vibration. A successful start or platform submission is
not proof the user heard/felt it. Use the real authorized device; do not change its
mute/DND/volume settings silently to obtain a pass.

The EMAS 3.10.1 `MessageReceiver.hookNotificationBuild` callback now adds
`FLAG_ONLY_ALERT_ONCE` only to notifications on `awiki_me_notify_urgent_v1`.
This retains EMAS as the single background presenter and leaves ordinary
notifications unchanged. The server must send a stable
`AndroidNotificationNotifyId` to update the same active notification. This flag
does not prevent another alert after dismissal, reboot, or an offline vendor
path that does not invoke the receiver; durable presentation receipts and
provider-outcome reconciliation remain required before enabling urgent Notify.

M153 preflight on 2026-09-21 confirmed a real EMAS NOTICE used the requested
urgent channel. The initial SDK notification lacked `ONLY_ALERT_ONCE`; the
updated Debug build exposed that flag on the actual provider-created notification.
Physical sound/vibration remained unverified while the device was silent.
The test sent explicitly labelled channel probes directly to the registered
development installation, without deploying a new service or changing account
notification policy. It is transport evidence, not an end-to-end Notify pass.

Push diagnostics distinguish pending processing counts from typed Core failures.
Local incoming-message recovery now maps Core exceptions through the existing
message-sync error mapper instead of losing that classification. Logs contain
only counts, exception type and sanitized stable error code, not message bodies,
credentials or identifiers. This diagnostic change is not a fix for notification
navigation: M153 still reproduced `invalid_input` during warm-session processing,
while restarting later recovered the already committed message and its route.

### Bounded event tracing

The native bridge and App coordinator emit bounded `[remote-push]` stages for
incoming/opened events, Flutter attachment, sync disposition, reference recovery
counts, and whether the opened message matched a committed conversation. These
records never include titles, message bodies, DIDs, tokens, provider device IDs,
or raw exceptions. A delivered Android broadcast alone does not prove that sync
or navigation completed; correlate these stages with an actual notification tap.

For device acceptance, start outside the destination conversation (for example,
on the Me page), background the App, send a new message, and tap its actual system
notification. Confirm the exact conversation and message, including after a normal
Back exit. For lock-screen acceptance, verify the keyguard is already showing
before sending; a notification arriving while the phone is transitioning to sleep
is not sufficient. Record provider connectivity and Android process-freeze events
separately from service outbox completion.

### OEM lock-screen networking

On the M153 (Nubia P0110, Android 16), AWiki Me's per-app battery settings can
independently select `后台联网设置 → 锁屏断网`. Notification permission, an allowed
background AppOp, an active standby bucket, or a live process does not override
this setting. Inspect the visible setting before attributing lock-screen failures
to the server or SDK. With the user's authorization, select `永不断网` for AWiki Me
and read the value back; do not change global battery policy or unrelated apps.

The 2026-09-20 device investigation reproduced EMAS going offline under the
original setting. After this single setting changed, a new message sent after
confirmed keyguard activation produced a system notification and visible
lock-screen text. A subsequent longer locked interval triggered OEM process
freezing again and the provider went offline; the network setting alone did not
resolve the failure. Check per-app background execution policy separately. This
is bounded device evidence, not a guarantee after process termination or prolonged idle. Preserve the original setting and timing in the
acceptance record, and verify notification-tap routing separately.


A subsequent M153 check enabled AWiki Me's `允许后台高耗电运行` while retaining
`永不断网` (autostart and associated-start switches remained off). The App stayed
connected for 320 seconds of confirmed screen-off/keyguard state; a newly sent
message then appeared in Android's active notifications and the lock-screen UI.
This per-app setting may increase battery use. Record its state and the actual
idle interval; overnight idle and killed-process delivery remain unverified.


### Debug C0: continuous cue and automatic presentation

The approved urgent experience is now up to 60 seconds of looping sound and
repeated vibration, with view/dismiss stopping immediately. A remote alert should
show a heads-up notification while unlocked and a full-screen presentation while
locked, when the user/system permits it. These requirements are **not yet wired
to authoritative IM metadata, account preferences, or conversation routing**.

The Debug source set contains two explicit experiments:

- `ContinuousUrgentNotificationProbe`: a local system-owned `FLAG_INSISTENT`
  notification with `setTimeoutAfter(60000)` and a dismiss PendingIntent. It does
  not combine repeated notification updates with `ONLY_ALERT_ONCE`, which can
  stop ongoing alerting. M153 looped audio but rendered only one short OEM
  vibration; this path does not satisfy repeated-vibration requirements.
- `ContinuousUrgentProbeService` and `ContinuousUrgentProbeActivity`: an
  explicitly armed, five-minute diagnostic window accepts one matching EMAS
  MESSAGE test token, consumes it before attempting a non-sticky `shortService`,
  and ignores duplicates. The service uses one foreground cue owner, a 60-second
  monotonic deadline, bounded CPU wake lock, visible stop action, and cleanup on
  stop/destroy/system timeout. Full-screen intent opens the Debug visual surface;
  an Activity launch alone does not restart or stop the cue. View/close/back stop
  the service; timeout closes the visual surface. The prototype's view action
  opens the App, not an asserted real conversation.

Only the Debug manifest replaces the ordinary receiver with its subclass,
declares the short service and full-screen intent permission, and exposes the
manual arming page. Profile/Release retain the ordinary receiver and contain no
probe service, full-screen Activity, or test-message handler. A locally armed
token is a test control, **not** production sender authority or a durable
message-scoped presentation receipt.

M153 background start succeeded with `SYSTEM_ALLOW_LISTED` under the existing
per-app battery whitelist. Do not generalize this result to devices without a
valid background-start exemption or to vendor offline channels. Check EMAS
registration/online status after an APK replacement: opening only the native
probe page initializes the SDK but does not execute the existing Flutter-driven
registration flow. An earlier attempt without a registration/online precheck was accepted by the
provider but produced no receiver/service evidence; registration became ready
afterward. It was not treated as device delivery.

Automatic unlocked heads-up and locked full-screen presentation were observed
through actual remote MESSAGE delivery. The locked test began after confirmed
screen-off/keyguard, and full-screen permission was read back as allowed. The
user had returned the device to silent mode for this stage; that validates silent
suppression, not audible/tactile continuity. Record actual 60-second completion,
manual stopping, duplicate rejection and physical sound/vibration separately.
Do not bypass FSI restrictions or battery policy with ADB grants in acceptance.


The locked silent-mode experiment kept one active notification/service and the
full-screen UI at 3/30/50 seconds. A duplicate remote delivery after about 34.7
seconds was rejected without reposting. The service stopped itself after
60,005 ms; at 65 seconds the notification/service/UI were gone and keyguard
remained enabled. Manual stopping was separately observed on the preceding
unlocked run. These are Debug platform results, not a completed IM feature.

## Text Notify v1: device-local controls (development candidate)

`TextNotifyPresentation` consumes a typed EMAS MESSAGE for the original plaintext message. The marker is intent, not server-issued consent. Core retains `notify_level`; Dart suppresses a second ordinary Android notification. Opening still resolves the original message through Core.

Settings are stored on this installation, separately for each opaque receiving DID. Master defaults on, urgent defaults off. They load/save without HTTP or a User Service update. Account switch/logout stops the active reminder; another account cannot inherit consent. Switching back restores that account's local choices. No preferences, mute set, capability or version is uploaded with installation registration. Old server-authority preference storage is not imported as local consent.

The native receiver reads current local controls and mirrored Direct mutes while Dart is absent. Turning urgent off downgrades future urgent requests to ordinary presentation; turning master off suppresses all typed Notify alerts while messages remain available. The canonical mute remains the App ProductLocalStore overlay. On Android session activation, the App reads all muted canonical conversation IDs and resolves Direct peers through Core registry pages, including hidden conversations. It atomically replaces the native opaque-identity snapshot before enabling presentation. Missing/unresolved routes fail closed instead of guessing a DID from a thread ID. Older installations without the readiness marker suppress typed Notify until this first hydration completes.

Mute edits invalidate the native snapshot before saving the canonical overlay, then replace the complete snapshot. Account and monotonically increasing sync-revision checks reject stale writes; the App serializes hydration and edits. Failed mirror writes retain the canonical change and keep alerts paused. Foreground resume retries incomplete hydration; Settings shows the paused state and offers an explicit retry. No mute or consent data is sent to User Service.

One short foreground service owns the call-like heads-up/full-screen UI and sound/vibration, bounded to 60 seconds. View/Close stop the matching session; timeout leaves a silent openable notification. System mute/DND/channel/background/full-screen restrictions remain authoritative. Persistent per-account target+message receipts (24h, 1024 unexpired maximum) deduplicate retries; one active presenter and a 60-second device interval prevent overlap or extension. While a cue is active or its service is starting, each additional accepted message gets its own silent system notification (target + peer + message tag), separate from the foreground-service slot. There is no queued re-ringing. Unique PendingIntent data preserves the correct message even on hash collisions. Mute, master-off and account switch remove the appropriate Notify slots without cancelling unrelated chat notifications.

Message Service only carries the marker through existing storage/projection and provider transport. Its existing retries may redeliver; no new delivery ledger or User Service authorization endpoint is required. New App support is required for Notify MESSAGE presentation; older clients can read the text but are not guaranteed a Notify system alert. Ordinary unmarked chat NOTICE behavior remains unchanged.

No offline provider queue is enabled for Notify. The server expiry stays 120 seconds. Native acceptance allows at most 30 additional seconds in the future to tolerate a lagging device clock; an expiry at or before device now is always rejected, and duplicate receipts still last 24 hours. This is bounded clock tolerance, not a renewal of the service expiry or the 60-second cue deadline. Full task-to-phone E2E and real-device upgrade/multi-message acceptance remain separate gates. The Debug probe is not the product path. Development changes do not authorize release or deployment.
