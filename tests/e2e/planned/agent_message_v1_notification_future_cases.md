# Agent Message v1 notification acceptance cases

Status: planned; no device, provider, account, or remote target was authorized for this change.

- `ANOT-APP-E2E-001`: trusted, opted-in `alert + urgent` foreground path while another conversation is visible commits one Core message, shows one App-internal full-screen urgent overlay, and records one bounded sound/vibration receipt; the already-visible target conversation receives the cue and card without a second overlay or tray notification.
- `ANOT-APP-E2E-002`: background provider-first, WebSocket/Core-first, and simultaneous arrival each commit one event and show exactly one provider NOTICE; the WebSocket/Core-first order records `deferredProvider` and never submits an App-owned native notification or cue. Resume and restart replay create no duplicate card, cue, or native identity.
- `ANOT-APP-E2E-003`: untrusted, muted, opted-out, expired, rate-limited, permission-denied, and stale-session paths retain the card but suppress/downgrade presentation exactly as the PRD matrix states.
- `ANOT-APP-E2E-004`: Android background and killed-process provider delivery remains generic normal on `awiki_me_messages_v2`, with default importance, provider notify type `NONE`, no vibration, and no screen wake; trusted urgent/mute consistency when killed is `BLOCKER` until recipient-bound offline trust exists.

The overlay is not Android full-screen intent or VoIP: it must not wake the screen, bypass DND, claim critical-alert semantics, or make the payload select a channel, sound, vibration, or priority. Required real evidence: named Android target, permission state, notification-channel settings, provider receipt, Core committed message identity, visible card/overlay, click route, and replay assertion. Fake facades and widget tests are not E2E evidence.
