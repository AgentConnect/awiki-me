# Foreground Message Banner

## Visual source

- Selected ImageGen direction: `foreground-message-banner-option-3.png`.
- Ardot file: `cocraft://localhost/file/709816693934731?node_id=104%3A1`.
- Editable Ardot section: `108:3` (`Section 13 · Foreground Message Banner`).
- Reusable component: `108:9` (`Component · Foreground Message Banner`).
- Editable Android screen: `108:18` (`Editable Screen 29 · Foreground Message Banner`).

The implementation follows the approved context-capsule direction: a 72 dp
top banner with a 48 dp avatar, optional group badge, authoritative
conversation title, relative time, one-line committed preview, and a visible
auto-dismiss progress indicator.

## Presentation contract

| App/message state | Presentation |
| --- | --- |
| Foreground, same conversation is visibly open | No global banner or system notification. The timeline and existing in-chat new-message affordance own presentation. |
| Foreground, another conversation/page | Show one top in-app banner. |
| Background, locked, unfocused, or target/session mismatch | Preserve the native EMAS `NOTICE` path. |
| Group system event, Agent control payload, or opaque E2EE/MLS content | Do not show the in-app message banner. |

The banner is not suppressed by WebSocket presence. A new eligible message
replaces the current banner and restarts its four-second lifetime. The entire
card opens the committed conversation; an upward swipe dismisses it
immediately. Reduced-motion mode removes the slide transition.

## Content and privacy

- Direct conversations show the conversation/sender label and one-line
  committed preview.
- Group conversations show the localized group badge, an authoritative group
  name, and `sender: preview`.
- If an authoritative group name is missing or resembles a raw Group DID,
  group ID, or canonical opaque identifier, the title falls back to the
  localized `Group chat` label.
- Raw full DIDs and opaque encrypted content must never be synthesized into
  banner copy.

## Accessibility

- The full 72 dp card is one semantic button with a localized announcement.
- Tap target height exceeds 48 dp.
- Long titles and previews truncate to one line without changing the hit area.
- Auto-dismiss, replacement, upward-swipe dismissal, and tap navigation are
  covered by focused tests.
