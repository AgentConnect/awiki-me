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
Events remain queued under a stable delivery ID until a future tenant-aware
coordinator explicitly acknowledges successful handling.

## Current boundary

This phase proves the Android client transport only. It does not yet provide:

- automatic push for AWiki chat messages;
- DeviceId registration or revocation in User Service;
- message-service outbox delivery, retry, or audit;
- identity-aware notification routing or conversation navigation;
- WebSocket/push notification deduplication;
- Huawei, Honor, Xiaomi, OPPO, vivo, or FCM vendor channels.

Only the Aliyun core channel is configured. Better delivery after process death
or under OEM background restrictions requires the corresponding vendor
credentials and channel adapters. Android's user force-stop state suppresses
push delivery until the user launches the App again and is not supported.

Server-side delivery also needs Alibaba Cloud RAM/OpenAPI credentials. Never
put an AccessKeyId or AccessKeySecret in this application. A later server phase
should keep installation/subscription ownership in User Service and extend the
existing Message Service outbox for provider delivery.
