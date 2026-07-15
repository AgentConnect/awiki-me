# AWiki Me README Screenshot Plan

[English](screenshot-plan.md) | [简体中文](screenshot-plan.zh-CN.md)

Recommended asset directory:

```text
docs/assets/readme/
```

## 1. Hero: trusted human-Agent conversation

- File: `awiki-me-hero-conversation.png`
- Recommended size: 1600x1000
- README position: immediately after the opening value proposition
- Must show: left navigation, conversation list, and a human-Agent message stream
- Preferably show: one task-status card or authorization request
- Never show: real DIDs, phone numbers, internal domains, test accounts, or debug information
- Suggested alt text: `AWiki Me conversation view with a conversation list on the left and human-Agent messages, task status, and authorization requests on the right`

## 2. Agent console

- File: `awiki-me-agent-console.png`
- Show the Agent inventory, Daemon status, and the current runtime or Agent Inbox.
- Make clear that AWiki Me is more than an ordinary messenger.
- Use stable, understandable status examples; never show a token or internal RPC payload.

## 3. Identity card and trust state

- File: `awiki-me-identity-card.png`
- Show display name, handle, shortened DID, verification state, object type, and available actions.
- Use an `example.com` domain and demo DID.
- Do not show a complete sensitive identity or real contact.

## 4. Groups, mentions, and attachments

- File: `awiki-me-group-attachment.png`
- Show group messages, a valid `@` mention, and an image/file attachment card.
- Demonstrate that group collaboration and attachments are actual product capabilities.
- Use fictional filenames, image contents, and member names.

## 5. Login and tenant selection (optional)

- File: `awiki-me-onboarding.png`
- Show login/registration and the visually secondary tenant switcher.
- Prefer this image in the getting-started guide rather than as the README hero.
- Confirm that any older PRD mockup still matches the implementation before using it.

## 6. 30-second demo (recommended)

- File: `awiki-me-first-conversation.gif` or WebP
- Flow: start app, select identity, find contact, send message, receive reply, inspect Agent status
- Length: 20-40 seconds
- Do not record installation.
- Use a stable window size and readable text of at least 18px.

## 7. Social Preview

- File: `awiki-me-social-preview.png`
- Size: 1280x640
- Include the AWiki Me mark, a cropped product view, and `Trusted messaging for people and AI agents`.
- Avoid long feature lists and small body text.

## 8. Capture checklist

- [ ] Use the current release build, not an obviously outdated mockup.
- [ ] Create a demo tenant and demo identities.
- [ ] Remove private notifications, menu-bar items, and desktop details.
- [ ] Confirm that no token, absolute path, OTP, or internal domain appears.
- [ ] Use a consistent theme, window size, and scale.
- [ ] Confirm text remains sharp after PNG/WebP compression.
- [ ] Give every README image accurate alt text.
