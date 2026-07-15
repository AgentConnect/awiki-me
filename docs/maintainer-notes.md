# AWiki Me README Pre-release Maintainer Notes

[English](maintainer-notes.md) | [简体中文](maintainer-notes.zh-CN.md)

This document is not for end users. Complete every item before merging the README proposal.

## 1. Suggested GitHub About

**Description**

```text
Agent-native cross-platform messenger and control console for people and AI agents, built on ANP and DID-WBA.
```

**Topics**

```text
agent, messaging, flutter, dart, anp, did, im, cross-platform
```

## 2. Filenames

Use `README.zh-CN.md` for the Chinese README and update the language switch in the English README.

## 3. Release links

The README intentionally contains no unverified download URLs. Before release, confirm the macOS arm64 DMG, macOS x64 DMG, Android arm64 APK, release notes, signing/notarization or installation-risk notice, and that the public download page agrees with `dist/latest.json`.

The default packaging configuration points to `https://<release-domain>/#download`, but the README may contain only a real, public, verified URL.

## 4. Status confirmation

The proposal uses `Developer Preview` because the app remains in the 0.1 series, validation does not cover every platform directory, Web Core is a runtime stub, self-hosted Agent realms use a fixed allowlist, and Group E2EE/cross-domain capabilities are not universally complete.

Changing the status to Beta or Stable also requires a version policy, upgrade contract, support platforms, compatibility matrix, and real release gates.

## 5. Facts that must remain explicit

- Web is currently unavailable.
- iOS must not use the same release wording as macOS and Android.
- The Agent/Daemon realm allowlist is `awiki.ai`, `awiki.info`, and `anpclaw.com`.
- AWiki Open Server has no E2EE.
- The app does not directly own private keys, JWTs, or the SecretVault root key.
- Debug and Release data and Keychain services are isolated.
- The README does not claim every ANP application protocol.

## 6. Screenshots

Capture assets under `docs/assets/readme/` according to `screenshot-plan.md`. A new public README should not ship without at least one screenshot of the running product near the top.

## 7. Default branch

The review baseline is `release/0710`, but the default branch is `main`. The new README must ultimately reach `main` or normal visitors will continue to see the old page.

## 8. Content moved out of the old README

The new README keeps summaries and links to focused documents for the complete ANP support scope, Storage Scope details, packaging variables, macOS signing and Xcode troubleshooting, full test matrix, and contributor checklist. Preserve this information without making first-time visitors read it before understanding the product.
