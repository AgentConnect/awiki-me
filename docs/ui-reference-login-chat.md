# Login and chat reference UI

The September 2026 UI update follows `new-awiki-me-ui/awiki-me-login.html`
and `new-awiki-me-ui/awiki-me-chat-window.html` in the shared workspace.
The other HTML variants are not implementation targets. Native window controls
remain owned by the platform; prototype accounts and simulated desktop chrome
are not App data or widgets.

## Login layout and entry state

The reference login layout is shared across phone, tablet and desktop windows.
Above 700px it uses a 296px brand column and a form capped at 336px. At 700px
and below the brand and tenant switcher occupy a compact header. The form
scrolls independently when height, the keyboard or enlarged text requires it.
The language action remains outside that scroll area. Platform safe areas and
the existing Android system-navigation clearance remain applied.

The two entry segments show either the capability-driven registration form or
the local identity list. They use `OnboardingState.entryMode` and the existing
`setEntryMode` transition, including its OTP/email target invalidation rules.
The UI does not maintain a parallel identity/login state. A committed
registration requiring a local activation retry can therefore still select
the local identity entry through the existing provider transition.

Phone, Handle and email text controllers remain owned by `OnboardingPage`;
switching visible entry or responsive layout does not recreate their values.
Busy entry segments and authentication methods cannot be switched. Empty local
identity lists show the localized empty state. Local login and deletion retain
the existing callbacks, confirmation, busy state and legacy-upgrade handling.
The reference's placeholder import/rescan controls are not exposed as working
features without an owning product implementation.

## Chat navigation and list

The desktop rail uses a nominal width of 68, icon buttons of 44 and icons of 22.
Labels remain in tooltips and semantics; the existing E2E identifiers continue
to select navigation controls. Lists use nominal widths of 264, or 240 at
window widths up to 920. These chat dimensions still use the established
display-scale preference, whose normal effective factor is 0.954.

List hover and selected surfaces are flat. Narrow status badges are constrained
within their title row. Conversation identity, selection, search, unread state,
message data and persistence continue to use the existing providers/Core
ownership; no new protocol or storage behavior is introduced.

Both conversation lists offer All, Unread, Agents and Groups. The filter and
search query intersect before presentation sorting. Unread uses the projected
count; agent membership uses the existing peer classifier, and group membership
uses the canonical conversation kind. Filters never remove base conversations
or change their read state. A desktop detail remains selected when its list row
is hidden by a filter. The filter is transient local view state.

Desktop chat uses a 48-unit header and a flat composer separated by a top
hairline. Its tools, text field and text-labelled send action occupy separate
rows; the empty composer has a nominal minimum height of 148. Existing keyboard,
IME, mention, emoji, screenshot and attachment callbacks retain their owners.
Phone and desktop message bubbles use symmetric 12/8-unit insets, 6-unit rounded
corners and 1.6 line height. Incoming text uses the reference's light neutral
surface, while outgoing messages retain the brand blue. Attachments retain
their own content sizing and interaction boundaries.

The phone composer keeps a 44-unit minimum touch height and a rounded capsule
input that grows to four lines. Focus uses the accent border, and the send action
has a localized text label and remains visible, disabled when there is no
sendable content. Attachment and emoji tools stay on the left even while a
draft is present. Group conversations also offer a mention tool that inserts
the existing `@` trigger and opens real roster candidates; direct conversations
do not offer it. Keyboard, clipboard and IME composition guards remain active. A pending
attachment continues to render above the input. The shared login field forwards
whole-field taps to its owned focus node, retaining focus through IME resizing.

## Appearance

Display & window settings offers Follow system, Light and Dark. Android and iOS
expose the same page through Appearance in Settings; mobile titles omit window
terminology and the desktop window-placement action is hidden. The device-wide
preference uses the existing bootstrap preference store, loads before the tenant
App is built, and survives tenant runtime recreation. Follow system removes the
explicit override and responds to platform brightness changes. Invalid or
unavailable stored appearance falls back to the system; a failed save retains
the previous selection and uses the existing UI error feedback. Writes are
serialized so rapid selections cannot persist in the wrong order.

Both Material and Cupertino themes, semantic typography, navigation, login,
chat, composer, overlays and Flutter system-bar styles use the resolved
appearance. The dark palette is the sRGB conversion of the approved HTML's
graphite OKLCH colors. Theme caching includes brightness and preserves the
Windows font policy. The login mark uses the existing transparent SVG asset.
Native desktop window chrome remains owned by the operating system; platform
runner title-bar configuration is unchanged.

## Verification ownership

- `tests/unit/onboarding_page_test.dart` checks geometry, entry switching,
  retained input, local identity actions, capability states, and 1.8x text
  across phone, short/narrow desktop and tablet windows. It also checks long
  local identity lists, deletion confirmation/failure and keyboard clearance.
- `tests/unit/onboarding_otp_lifecycle_test.dart`,
  `onboarding_session_transition_test.dart` and
  `onboarding_recovery_lookup_test.dart` retain authentication lifecycle oracles.
- `tests/unit/conversation_workspace_test.dart` covers navigation, tooltips,
  selection, unread state, drafts across breakpoints, and reference viewports.
- `tests/e2e/flutter/app/ui_visual_verification_test.dart` owns real Flutter
  rendering with isolated fake bootstrap. Its screenshots are visual evidence,
  not remote-backend or native secret-provider attestation.
- Its `reference matrix renders login and chat in both appearances` case covers
  all nine reference viewports in light and dark, capturing login, conversation
  list and selected chat, plus multiline phone composer states. It asserts the
  actual rendered theme and no layout exceptions. Generate with
  `--update-goldens`, inspect the resulting images, then compare without that
  flag; generation alone does not establish acceptance.
  Phone captures also cover a 300px keyboard inset, and assert the empty send
  action remains visible/disabled and the attachment tool stays on the left.
- `tests/unit/app_appearance_test.dart` checks reload, system reset, invalid/read
  failure fallback, failed-write selection, and serialized rapid choices.
  `awiki_me_app_localization_test.dart` exercises the settings controls against
  the actual App, platform brightness changes and system-bar style.
  `awiki_me_design_test.dart` checks dark text contrast and per-platform theme
  caching/font behavior; `chat_page_test.dart` covers capsule growth, focus,
  send, attachments and IME composition.
- `shared_widgets_test.dart` checks the shared shell/header title against the
  dark text palette; `dark_navigation_surfaces_test.dart` checks reachable
  contacts and Agent inbox surfaces and text. Existing friends/Agent layout
  tests remain the interaction oracles for those semantic-color-only changes.
- Generic cross-service oracles remain in `awiki-system-test`. These layout
  changes introduce no server/persistence contract gap; real-backend evidence
  remains a separate gate and must not be inferred from widget passes.

Final screenshot/independent review acceptance remains separate from
implementation and focused tests. See the workspace task run
`.tfd/runs/AWIKI-ME-UI-20260928/` for current evidence and remaining scope.
