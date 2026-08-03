# Core Seven Mobile UI — Pull Request Scope

## Proposed pull request

- **Title:** `feat: refresh core mobile UI and navigation flows`
- **Head:** `Feature/core-seven-mobile-ui`
- **Base:** `release/0714`
- **Status:** implementation and focused Android validation are complete; branch synchronization, commit, push, and PR creation are intentionally pending.

## Product outcome

This change set establishes one compact mobile UI language across the four primary destinations — Messages, Contacts, Agents, and Me — and closes the navigation and state-consistency defects found during P0110 review.

The visual direction is intentionally restrained: white and warm-neutral surfaces, AWiki blue for primary interaction, red only for unread and destructive states, 16sp compact mobile titles, consistent line icons, 44–48dp minimum touch targets, and predictable Android back behavior.

## Page and flow inventory

| Area | Pages / states in this pull request | Main outcome |
| --- | --- | --- |
| Startup and authentication | Runtime-gated splash; login / registration | Cold start no longer flashes the login page before restoring a saved session. |
| App shell | Messages; Contacts; Agents; Me | Four destinations share a consistent bottom bar, 16sp top titles, and no redundant top-left logo. |
| Messages | Conversation list; search; unread badges; anchored quick-actions menu | Header actions are consistent with Contacts and open from the top-right anchor instead of a bottom sheet. |
| Chat | Direct / group / agent conversations; unified bubble contour; composer; attachment actions | Incoming and outgoing messages show avatars; bubble tails use one continuous outline without the former vertical seam. |
| Chat information | Chat information; record search; mute; pin; remove from list | The top-right ellipsis opens a dedicated chat-information page; destructive actions remain visually separated. |
| Identity from chat | User information; My information | Tapping the peer avatar opens User Information; tapping the current user's avatar opens My Information; system back returns to the chat. |
| Contacts | All; Following; Followers; Groups | Four equal-width tabs replace the previous mixed hierarchy; search follows the selected category. |
| Contact and group navigation | Contact profile; group list; group chat; relationship lists | Group and chat routes remain inside the originating workspace, and Android back restores the correct source page. |
| Contact relationship state | Follow / unfollow / friend presentation | Contact profile merges the local following list with the relation status so an already-followed user cannot be followed twice. |
| Agents | Agent list; Daemon / Runtime hierarchy; agent detail | List density, hierarchy, empty states, and detail presentation align with the compact mobile system. |
| Me | Profile; DID; homepage; identity card; Following / Followers entry points | Profile details use full-width expandable rows; relationship counters navigate to 16sp-titled lists. |
| Settings | Account and devices; personal agent; version; update; language; security | Settings are grouped by purpose, trailing values are vertically centered, and destructive actions remain in a dedicated lower section. |

## Implementation map

### Navigation and runtime gating

- `lib/src/app/app_router.dart`
- `lib/src/app/tenant_aware_awiki_me_app.dart`
- `lib/src/presentation/app_shell/app_shell.dart`
- `lib/src/presentation/app_shell/providers/navigation_provider.dart`
- `lib/src/presentation/app_shell/providers/message_sync_coordinator_provider.dart`
- `lib/src/presentation/shared/startup_splash.dart`

### Messages and chat

- `lib/src/presentation/conversation_list/conversation_list_page.dart`
- `lib/src/presentation/conversation_list/conversation_workspace_page.dart`
- `lib/src/presentation/chat/chat_page.dart`
- `lib/src/presentation/chat/parts/chat_header_part.dart`
- `lib/src/presentation/chat/parts/chat_information_part.dart`
- `lib/src/presentation/chat/parts/chat_message_part.dart`
- `lib/src/presentation/chat/parts/chat_peer_info_part.dart`
- `lib/src/presentation/group/group_chat_navigation.dart`

### Contacts, profile, agents, and settings

- `lib/src/presentation/friends/friends_navigation_provider.dart`
- `lib/src/presentation/friends/friends_page.dart`
- `lib/src/presentation/friends/friends_workspace_page.dart`
- `lib/src/presentation/profile/peer_profile_page.dart`
- `lib/src/presentation/profile/peer_profile_provider.dart`
- `lib/src/presentation/profile/profile_page.dart`
- `lib/src/presentation/profile/profile_workspace_page.dart`
- `lib/src/presentation/agents/parts/agents_list_part.dart`
- `lib/src/presentation/settings/settings_page.dart`

### Shared UI and localization

- `lib/src/presentation/shared/awiki_me_semantic_icon.dart`
- `lib/src/presentation/shared/awiki_me_top_bar.dart`
- `lib/src/presentation/shared/copyable_did_line.dart`
- `lib/src/presentation/shared/identity_flow.dart`
- `lib/src/presentation/shared/identity_profile_surface.dart`
- `lib/src/presentation/shared/quick_actions.dart`
- `lib/l10n/app_en.arb`
- `lib/l10n/app_zh.arb`
- generated localization outputs under `lib/l10n/`

## Automated coverage

The change set adds or extends focused coverage for:

- app shell and destination navigation;
- cold-start session restoration and splash behavior;
- direct, group, and agent chat layouts;
- bubble contours, avatars, chat information, and avatar-to-profile routes;
- top-right anchored quick actions;
- contact tabs, group navigation, Android back handling, and relationship state;
- profile expansion, relationship list navigation, and 16sp titles;
- agent hierarchy and settings layout;
- compact and expanded visual baselines.

Current pre-PR validation, together with the focused runs recorded in `design-qa.md`, includes:

- current pre-PR unit/widget sweep across 11 affected suites: `368/368` passed;
- chat and profile regression: `126/126` passed;
- chat and message-sync regression: `147/147` passed;
- core seven suite: `256/256` passed;
- visual baseline suites: passing for their recorded target sets;
- current full `flutter analyze`: no issues;
- `git diff --check`: passed.

## P0110 acceptance evidence

The latest data-preserving install was verified on P0110 with:

- package: `ai.awiki.awikime.dev`;
- version: `0.1.14+25`;
- last recorded install time: `2026-08-02 15:05:15`;
- latest recorded APK SHA-256: `afe02f68b5284c03a125d049b4469218f50d6aeb1ec47b94503648dd449603b1`.

The accepted device paths include cold-start splash continuity, all four primary tabs, anchored header menus, contact category switching, group-local navigation, contact-to-chat back handling, profile relationship lists, continuous chat bubbles, chat information, User Information, and My Information.

## Pull request inclusion boundary

### Include

- Flutter source and localization changes.
- Unit, widget, smoke, and visual verification tests.
- Visual baseline PNG files required by the verification suite.
- `design-qa.md` and the mobile function-page inventory after a final privacy pass.
- This pull-request scope document.

### Keep local; do not commit

- `.design-references/` — contains raw device screenshots, UI XML, recordings, generated design references, and account-specific runtime data.
- local build artifacts and device-install outputs.

## Known boundaries

- The feature branch is currently one commit behind `origin/release/0714`; synchronize only after the working changes are safely committed or otherwise preserved.
- The macOS native integration host remains unverified because this worktree does not contain the required AwikiImCore macOS XCFramework slice. Widget-based visual verification is not a substitute for that native host.
- Dark mode, largest Dynamic Type, TalkBack / VoiceOver reading order, landscape, additional Android sizes, iOS device behavior, and signed release packaging remain **UNVERIFIED** unless separately exercised before merge.
- Runtime content such as handles, DIDs, contact counts, conversations, and version values can differ from static baselines without indicating a layout regression.

## Ready-to-use pull request body

### Summary

- unify the compact mobile shell around Messages, Contacts, Agents, and Me
- add a runtime-gated splash to prevent login-page flashes during session restoration
- redesign chat bubbles, chat information, avatar profile navigation, and anchored header actions
- reorganize Contacts into All, Following, Followers, and Groups with source-preserving navigation
- refresh profile, relationship lists, agent hierarchy, and settings while keeping existing capabilities
- add regression coverage for Android back behavior, relationship state, startup continuity, and visual baselines

### Validation

- full Flutter analysis passes with no reported issues
- the current pre-PR unit/widget sweep passes `368/368`, including the latest chat, profile, contacts, agents, settings, navigation, and splash coverage
- compact and expanded visual baselines pass for the recorded target sets
- P0110 data-preserving acceptance covers startup, the four primary tabs, chat, contacts, profile, and settings flows
- `git diff --check` passes

### Not verified

- iOS device behavior
- dark mode and maximum dynamic text
- TalkBack / VoiceOver reading order
- landscape and additional device sizes
- signed release packaging
- macOS native integration host
