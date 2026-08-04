# Android Remote Push future E2E cases

These cases are non-executable catalog anchors. They remain `planned` until a
physical-device runner can produce a complete case attestation. Neither case is
registered in an executable suite.

## `ANDROID-PUSH-PRODUCT-E2E-001`

- Status: planned; no automated physical-device case attestation exists yet.
- Owners: `awiki-me+user-service+message-service`.
- Device: a named physical Android device on an approved tenant.
- Scope: authenticated installation lifecycle and one real direct message
  through Message Service outbox, EMAS, Core sync, App projection, Android
  presentation, and exact notification-open routing.

The future runner must attest all of the following in one isolated scenario:

1. Activate an authenticated AWiki Me session, initialize the native EMAS
   bridge more than once, and upsert the Android EMAS installation in User
   Service. Prove that only one native registration and one active installation
   result, with no `PUSH_20110` failure reaching Flutter. Evidence may contain
   only non-sensitive identifiers or suffixes.
2. Send one real direct message through Message Service outbox and EMAS.
3. With the App foregrounded on the same visible conversation, intercept the
   matching-account ordinary `NOTICE`, complete Core sync, project one
   canonical message, and display neither a system notification nor a global
   App toast. Repeat while scrolled away from the bottom and prove that only
   the existing in-chat new-message affordance appears.
4. With the App foregrounded on another conversation or page, intercept the
   matching-account ordinary `NOTICE`, complete Core sync, and display exactly
   one App in-app notification for the committed message.
5. Repeat with a missing or mismatched opaque target and prove that native
   interception fails open to provider presentation without exposing a raw DID
   or conversation identifier.
6. With the App backgrounded, display exactly one EMAS `NOTICE`.
7. Terminate the App process, tap the delivered notification, complete Core
   sync, and open the exact conversation derived from the newly committed
   message.
8. Deliver the same logical message through WebSocket and Push and prove
   convergence to one committed canonical message and one presentation.
9. Repeat while offline: the native event must remain pending and
   unacknowledged. Restore connectivity, complete sync and any required
   routing, then prove that the exact delivery is acknowledged.
10. Log out, prove the active installation is disabled, send again, and prove
   the old-DID installation is excluded from delivery.

Provider API success, Message Service outbox `done`, a fake Push facade,
duplicate messages or notifications, early acknowledgement, wrong-conversation
navigation, or delivery to the disabled old installation cannot satisfy this
case.

## `ANDROID-PUSH-NATIVE-E2E-001`

- Status: planned; no automated native case attestation exists yet.
- Owner: `awiki-me-platform`.
- Device: Nubia P0110, or an explicitly named equivalent physical Android
  device. An emulator is not an equivalent.
- Scope: Android notification authorization, native EMAS registration,
  background delivery, and terminated-process delivery/open.

The future runner must:

1. Deny notification permission and capture the denied state.
2. Recover permission through Android system settings and capture the recovered
   state.
3. Register the production Android transport with EMAS, resume or relaunch the
   App to repeat bridge initialization, and prove that the existing DeviceId is
   reused without a second native registration or a `PUSH_20110` failure.
   Retain only a non-sensitive provider DeviceId suffix as evidence. Full
   provider IDs, AppSecrets, RAM keys, tokens, and payload contents must not be
   recorded.
4. Background the App and prove a visible notification is delivered on the
   named physical device.
5. Terminate the App process, deliver again, and prove both native delivery and
   the notification-tap open path.

Provider API success, Message Service outbox `done`, fake-facade callbacks,
callback-only evidence without a visible notification, emulator-only evidence,
or evidence from an unnamed substitute device cannot be reported as a pass.
