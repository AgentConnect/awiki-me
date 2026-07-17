# AWiki Me Platform and Service Compatibility

[English](compatibility.md) | [简体中文](compatibility.zh-CN.md)

Last reviewed: 2026-07-14. Add the actual versions or commits and latest verification date before a public release.

## 1. Platform matrix

| Platform | SDK/project state | Current product status | Required before release |
| --- | --- | --- | --- |
| macOS arm64 | Flutter app and native SDK | Priority support | Production signing, DMG, Keychain restart gate, and a real messaging flow. |
| macOS x64 | Flutter app and native SDK | Priority support | Production signing, DMG, and validation on Intel hardware or a trusted build environment. |
| Android arm64 | Flutter app and native SDK | Priority support | Signed release APK and startup/messaging flow on a device or emulator. |
| iOS | Flutter project and native SDK | Development target | Signing, physical-device, background, networking, secure-storage, and distribution validation. |
| Web | UI project exists; Core is a stub | Unsupported | A real Web Core, storage, encryption, and sync implementation. |
| Linux | `awiki_im_core` supports native Linux | Not an AWiki Me product target | App runner, packaging, UX, notifications, and secure-storage validation. |
| Windows | Not currently listed as supported | Unsupported/not planned | App runner, SDK, packaging, and complete validation. |

## 2. Service matrix

| Service type | Login/identity | Direct | Group | Attachment | Agent/Daemon | E2EE |
| --- | --- | --- | --- | --- | --- | --- |
| Default/hosted AWiki services | Primary path | Primary path | Primary path | Primary path | Primary path | Verify by message type and service capability. |
| `awiki-open-server` | Basic compatibility target | Plaintext Direct | Participant group capabilities | Local object capabilities | Disabled by default outside the allowlist | Unsupported |
| Other compatible AWiki services | Verify individually | Verify individually | Verify individually | Verify individually | Restricted by the realm allowlist | Verify individually |
| Generic remote ANP service | Only implemented scope | Depends on the service description and interop methods | Does not imply complete federation | Depends on the object protocol | Does not automatically provide AWiki Agent APIs | Cannot be inferred |

## 3. Agent boundaries on self-hosted domains

AWiki Me currently enables Agent and Daemon features only for these exact realms:

```text
awiki.ai
awiki.info
anpclaw.com
```

The backend must be the HTTPS origin for that hostname, the DID host must match the hostname exactly, and the realm must be in the built-in allowlist.

Other tenants should:

- continue to allow verified basic identity and messaging paths;
- show an unsupported state on the Agent page;
- avoid calling Agent backend APIs; and
- never disguise limited compatibility through UI wording.

Full Agent Console support for AWiki Open Server first requires a verifiable realm-binding or public extension mechanism. Do not simply relax the allowlist.

## 4. Encryption capabilities

Do not claim that all messages are end-to-end encrypted by default.

An accurate assessment must consider:

1. Direct or Group;
2. text or attachment;
3. current `awiki-im-core` capabilities;
4. peer client capabilities;
5. whether the server preserves and forwards the required protocol shape;
6. local SecretVault and identity state; and
7. real E2E verification for the current release.

A safe public statement is:

> AWiki Me delegates identity keys and secure-message state to the shared IM Core and SecretVault. Exact E2EE coverage depends on the conversation type, peer, and service capabilities. Messages are not end-to-end encrypted when connected to `awiki-open-server`.

## 5. ANP scope

AWiki Me currently focuses on:

- `did:wba` identity and DID-WBA authentication;
- `ANPMessageService` endpoints;
- Direct/Group messages, local projection, unread state, read acknowledgements, realtime hints, and reliable sync;
- attachment/Object Transfer direction;
- group-message mentions; and
- Agent, Daemon, and Personal Agent product entry points.

It must not claim complete coverage of all ANP application protocols, complete cross-domain federation, AP2 payments, complete Group E2EE on arbitrary servers, or AWiki Agent Runtime management on arbitrary domains.

## 6. Release compatibility record

```text
Verification date: YYYY-MM-DD
AWiki Me: <version + commit>
awiki_im_core: <version + commit>
awiki-im-core: <version + commit>
Server: <name + version + domain>
Platform: <OS + arch + version>

Verified:
- registration/login
- direct send/receive/history
- unread/read
- group create/join/send
- attachment send/download/open
- contact/follow
- Agent inventory/status
- secure direct/group (when applicable)

Not verified:
- ...
```
