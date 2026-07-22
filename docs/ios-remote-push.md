# iOS Remote Push

AWiki Me integrates the official Aliyun EMAS iOS Push SDK through the same
provider-neutral Dart client and MethodChannel used by Android. The iOS runner
initializes CloudPushSDK, requests notification authorization, registers the
APNs device token with EMAS, exposes the EMAS DeviceId, and normalizes
foreground, background, cold-start, message, and notification-open callbacks.

The native queue retains at most 32 unacknowledged `message_received` or
`notification_opened` events for 24 hours. It persists only a provider message
ID and the allowlisted opaque AWiki envelope fields; notification title, body,
URL, credentials, DID, and message content are not persisted.

## Local configuration

The iOS EMAS AppKey and AppSecret belong to the iOS application and are not the
same credentials as the Android application. Copy the tracked template for the
configuration being built:

```bash
cp ios/Flutter/Emas.xcconfig.example ios/Flutter/Emas.Debug.xcconfig
```

Then set:

```text
AWIKI_EMAS_ENABLED = YES
AWIKI_EMAS_APP_KEY = YOUR_IOS_EMAS_APP_KEY
AWIKI_EMAS_APP_SECRET = YOUR_IOS_EMAS_APP_SECRET
AWIKI_EMAS_LOG_DEVICE_ID = NO
```

Use `Emas.Profile.xcconfig` and `Emas.Release.xcconfig` for those build
configurations. All three local files are ignored by Git. Debug/Profile use the
APNs development environment; Release uses production.

The EMAS application bundle must match the build configuration:

| Configuration | iOS bundle identifier | APNs environment |
| --- | --- | --- |
| Debug / Profile | `ai.awiki.awikime.dev` | development |
| Release | `ai.awiki.awikime` | production |

Upload the matching APNs authentication key or certificate to the corresponding
EMAS iOS application. An Android AppKey, mismatched bundle identifier, wrong
APNs environment, expired certificate, or unsigned Push Notifications
entitlement prevents delivery even when CloudPushSDK initialization succeeds.

## CocoaPods and signing

The Podfile uses `AlicloudPush >= 3.2.4, < 4.0` from the Aliyun specs repository
and adds the SDK-required `-ObjC` linker flag. On a macOS build host run:

```bash
cd ios
pod install --repo-update
```

Open `Runner.xcworkspace`, not `Runner.xcodeproj`. The checked-in Runner
entitlements declare `aps-environment`, and the Info.plist enables background
remote notifications. The provisioning profile must contain the matching Push
Notifications capability.

## Device validation

Set `AWIKI_EMAS_LOG_DEVICE_ID = YES` only in a local Debug configuration when a
full DeviceId is required for console testing. Launch on a signed physical iOS
device, grant notifications, and inspect the Xcode console for:

```text
AWikiRemotePush: EMAS DeviceId: ...
```

Send an iOS `NOTICE` to that DeviceId from the EMAS console. Validate foreground
display, background delivery, notification opening, terminated-process launch,
and replay after Flutter attaches. Disable full DeviceId logging again after the
test.

## Current boundary

This implementation supplies the iOS client transport and the shared server
provider accepts iOS targets. Automatic installation upsert/revocation from the
App is still not wired, matching the current Android boundary. The release E2E
gate `PUSH-IOS-E2E-001` therefore remains a physical-device follow-up owned by
`awiki-me-notifications`; it must cover APNs registration, User Service
installation ownership, Message Service outbox delivery, and notification-open
replay before production push can be claimed end to end.
