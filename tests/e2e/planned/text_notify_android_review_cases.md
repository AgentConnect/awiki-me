# Text Notify Android review regression acceptance

Status: planned; no new real-device attestation in this review-fix batch.
Owner: AWiki Me Android product E2E. Existing System Test
`tests_v2/message_service/test_text_notify.py` owns service annotation,
replay/history/offline-sync checks; native display is not its oracle.

Use the same authorized M153 and local Debug build, real Skill/CLI send path,
and existing test identities. Record exact App/CLI SHAs and system permission
state. Each message gets its own event/message identity; do not resend an
uncertain event. Do not use Debug probe as product evidence.

1. Start one urgent cue, then deliver one normal and one different urgent text.
   Require one unchanged cue deadline and two separate silent notification-list
   entries. Open each and verify its original message. Redeliver the same
   provider message during and after the cue: no duplicate entry or later ring.
2. Upgrade without clearing App data from a build with a muted Direct (also
   hidden in recents). After login, send normal and urgent texts to that peer:
   chat content remains available, no native cue/banner. Unmute through UI;
   subsequent authorized messages may alert. Simulate mirror failure, require a
   visible paused state, preserved canonical mute and successful explicit retry.
3. Switch A → B while hydration is pending, then back to A. No old callback may
   activate B's presentation or remove A's mute. Consent remains per account.
4. With a bounded test clock offset, use server expiry 120 seconds and a device
   clock five seconds behind, one-second transport delay: fresh message alerts.
   Expired and >30-second future-tolerance-bound messages must not start a cue.
   Restore clock and settings after the test.
5. During the active cue verify mute, master-off, View, Close and 60-second stop.
   Notify passive slots are removed for muted peers/master-off/account switch;
   unrelated chat notifications remain. Preserve message history.

The native Robolectric and Dart tests cover deterministic decisions and
persistence/concurrency behavior. They do not attest M153 display, vibration,
sound, background survival or the real server-to-device transport.
