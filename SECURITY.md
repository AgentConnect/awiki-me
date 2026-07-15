# AWiki Me Security Policy

[English](SECURITY.md) | [简体中文](SECURITY.zh-CN.md)

## Supported versions

Security fixes prioritize the latest maintained release line and the default branch. Historical prerelease branches, unsigned builds, personal forks, and versions with locally modified security boundaries may not receive equivalent support.

## Reporting a vulnerability

Do not disclose unpatched vulnerabilities, exploitation steps, tokens, private keys, or user data in a public GitHub issue, discussion, group chat, or ordinary message.

<!-- TODO(security-contact): Enable GitHub Private Vulnerability Reporting or add the organization's official security email/form. -->

Use these channels in order:

1. The repository's GitHub Private Vulnerability Reporting feature.
2. If it is not enabled, the private security contact publicly designated by AgentConnect.
3. Do not publish technical details until a maintainer acknowledges the report.

A useful report includes:

- affected version, commit, and platform;
- reproduction steps and a minimal proof of concept;
- impact;
- whether real accounts or data are involved;
- suggested mitigation; and
- safely shareable, redacted logs or screenshots.

## Critical security boundaries

AWiki Me must not directly hold or log:

- DID private keys;
- JWTs or bearer tokens;
- SecretVault root keys, envelopes, or raw `SecretRef` values;
- private Direct/Group E2EE state;
- Daemon delegated-key or subkey packages;
- macOS, iOS, or Android signing private keys; or
- real OTPs and test account pools.

Every tenant must isolate local data and platform secure storage with an immutable Storage Scope. Vault open or verification failures must fail closed. The app must not generate a replacement root key, fall back to plaintext, or silently run a legacy migration.

## High-risk changes

The following require additional security review and testing:

- SecretVault, Keychain/Keystore, or Storage Scope changes;
- DID registration, recovery, replacement, or active-identity changes;
- E2EE session, prekey, or MLS changes;
- tenant switching and route changes;
- Agent authorization, controller scope, and control payloads;
- attachment download authorization and opening local files;
- Bundle ID, entitlement, signing, and automatic updates; and
- logs, diagnostics, E2E reports, and error details.

## Encryption statement

Local SecretVault and secure-message capabilities do not mean that every message is inherently end-to-end encrypted. Actual coverage depends on the conversation type, peer, server, and current release. When connected to a service that explicitly lacks E2EE, the UI must communicate that boundary accurately.

## Disclosure

After confirming an issue, maintainers should coordinate the fix, release, and advisory schedule. Premature uncoordinated disclosure can put users at risk, but the project will not ask reporters to conceal facts that are already public or cannot reasonably remain confidential.
