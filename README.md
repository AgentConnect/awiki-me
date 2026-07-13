# AWiki Me

[English](README.md) | [中文](README_zh.md)

AWiki Me is AWiki's cross-platform Flutter client for human users and intelligent agents. It is an application implementation that supports the **Agent Network Protocol (ANP)** protocol suite. The app combines account onboarding, `did:wba` identity, DID-WBA authentication, ANP instant messaging, group collaboration, attachments, message mentions, Agent/Daemon control, and local secure storage in one Dart/Flutter client.

- **ANP protocol link**: <https://github.com/agent-network-protocol/AgentNetworkProtocol>
- **Project positioning**: Dart-only app. Flutter owns product UI and application orchestration; `awiki_im_core` / Rust `im-core` owns protocol correctness, local IM state, sync, outbox, identity vault, and sensitive cryptographic material.
- **Platforms**: Android, iOS, macOS, and Web. Current automated validation focuses on desktop flows plus Android/macOS packaging.

## Contents

- [Product Positioning](#product-positioning)
- [ANP Support Scope](#anp-support-scope)
- [Core Features](#core-features)
- [Architecture Overview](#architecture-overview)
- [Repository Layout](#repository-layout)
- [Requirements](#requirements)
- [Quick Start](#quick-start)
- [Runtime Configuration](#runtime-configuration)
- [Testing](#testing)
- [Packaging and Release Artifacts](#packaging-and-release-artifacts)
- [Building on macOS with Xcode](#building-on-macos-with-xcode)
- [Security Boundaries](#security-boundaries)
- [Key Documents](#key-documents)
- [Contributor Checklist](#contributor-checklist)
- [License](#license)

## Product Positioning

AWiki Me is designed to be a trusted IM client and Agent console for the Agent era:

1. **Identity before Message**: conversations, contacts, groups, and Agents are anchored by DID / handle identities.
2. **Permission before Action**: high-risk Agent actions must go through explicit authorization or confirmation.
3. **Task over Chat**: normal messages, Agent status, authorization requests, task progress, and results can all appear in one trusted conversation flow.
4. **Hide Protocol, Show Trust**: users see product-level language such as “identity verified”, “message encrypted”, and “operation authorized”, while ANP / DID-WBA / im-core provide the protocol foundation.

## ANP Support Scope

The ANP 1.1 release line organizes protocol capabilities around identity, naming, Agent description, discovery, end-to-end instant messaging, and application protocols. AWiki Me currently implements and integrates the following scope:

| ANP / AWiki capability | AWiki Me status | Main entry points |
| --- | --- | --- |
| `did:wba` identity and DID-WBA authentication | Account onboarding, identity activation, User Service calls, and Message Service calls go through Dart service clients and `awiki_im_core`; new identities follow the e1 DID-only direction. | `lib/src/application/auth/`, `lib/src/data/im_core/` |
| `ANPMessageService` endpoint | The app derives the ANP message endpoint `/anp-im/rpc` and service DID `did:wba:<domain>` from the active in-app tenant. The default tenant is AWiki (`https://awiki.ai` + `awiki.ai`). | `lib/src/application/config/awiki_environment_config.dart`, `lib/src/application/tenant/` |
| ANP instant messaging P1/P2/P3/P4 direction | Direct/group conversations, send, history, local projections, unread state, read ack, realtime patch, and reliable sync. | `lib/src/application/messaging_service.dart`, `lib/src/application/message_sync_service.dart` |
| ANP attachments / Object Transfer (P7 direction) | Attachment picking, desktop drag-and-drop staging, clipboard image/file paste staging, send, download, save, and native open. Display correctness comes from im-core persisted redacted attachment manifests, not UI memory alone. | `lib/src/application/attachment_*`, `lib/src/presentation/chat/` |
| ANP message mentions (P9 direction) | Group `@` composer, P9 JSON payload sending, valid-range highlighting, and safe fallback for invalid mentions. | `lib/src/domain/entities/chat_mention.dart`, `docs/message-mention-extension-implementation-plan/` |
| Agent / Daemon / Message Agent collaboration | Agents page, daemon status, runtime conversation, and Message Agent binding/recovery flows provide the App entry for Agent collaboration. | `lib/src/presentation/agents/`, `docs/message-agent/message-agent-design.md` |
| E2EE and secret vault | The app does not directly own DID private keys, JWTs, Direct E2EE session/prekey material, or daemon subkey package persistence; these are owned by the im-core identity SecretVault. | `docs/identity-secret-storage.md` |

> AWiki Me is a client implementation that supports the ANP protocol suite. It does not claim to cover every ANP application protocol at once. AP2 payments, full cross-domain federation, and full Group E2EE plaintext processing should continue through shared SDK, service-side, and product rollout plans.

## Core Features

- **Account and identity**: registration/login, DID identity initialization, active identity vault checks, profile display and editing.
- **Trusted IM**: direct chat, group chat, conversation list, local-first first paint, realtime patches, reliable sync, unread waterlines, retry, and failure states.
- **Group collaboration**: group creation, member summaries hydrated from public profile Display Name, group messages, group system events, group mentions, and Agent group collaboration entry points.
- **Contacts and profiles**: friends/relationship state, peer profile, tenant/owner-scoped local display-profile projections, Display Name-only conversation labels (handles remain identity metadata), copy actions, identity cards, independently recoverable follower/following lists whose rows prefer nicknames and fall back to handles, and optimistic follow/unfollow UI state. Conversation previews read only the local projection; opening a full relationship list concurrently fetches only missing peer profiles and caches them, while opening peer details explicitly refreshes an individual profile.
- **Attachments**: attachment picking plus desktop drag-and-drop or clipboard image/file paste into the chat composer, upload/send, download, save, native open, and App + CLI E2E interoperability.
- **Agent console**: Agent inventory, local-first refresh, daemon install command rendering, runtime status, Agent inbox, and control payload projection.
- **Local security**: platform secure storage, native macOS Keychain bridge, E2E private file provider, and secret redaction.
- **Packaging and updates**: Android arm64 APK, macOS arm64/x64 DMG, versioned dist output, latest manifest, and Sparkle feed placeholder.

## Architecture Overview

```text
Flutter UI / Riverpod providers
  -> Application services
     (auth, session, messaging, groups, profile, agents, realtime, attachments)
  -> Domain ports + data adapters
  -> awiki_im_core Dart package
  -> Rust im-core / SQLite / native bridge
  -> User Service / Message Service / ANP endpoint / Daemon
```

Important boundaries:

- `lib/src/domain/`: entities, repository/port contracts, and focused domain logic.
- `lib/src/application/`: use-case orchestration, session, messaging, groups, contacts, agents, attachments, and environment config.
- `lib/src/data/`: Dart service clients, `awiki_im_core` adapters, secure/local persistence, and platform bridges.
- `lib/src/presentation/`: Flutter pages, Riverpod providers, responsive layout, and user feedback.
- `awiki_im_core` / Rust `im-core`: source of truth for messages, threads, groups, conversation identity, read-state, send/outbox, sync/realtime/backfill, local projections, and identity vault.

The App may own product overlays, UI waterlines, and short-lived pending presentation state. It must not bypass im-core to write the global reliable checkpoint, `since_event_seq`, `next_event_seq`, or raw `/im/rpc` sync payloads.

## Repository Layout

```text
lib/                  Flutter application source
  src/domain/         Domain entities and interface contracts
  src/application/    Application services, use cases, and ports
  src/data/           im-core adapters, service clients, local/secure storage, platform bridges
  src/presentation/   UI pages, providers, components, and responsive layout
assets/               Branding, icons, and static assets
android/ ios/ macos/ web/
                      Platform runners; avoid unrelated platform metadata changes
docs/                 PRD, testing, message presentation, Agent, identity vault, performance, and plan docs
tests/unit/           Fast deterministic unit/widget/provider/fake-backed harness tests
tests/e2e/            E2E runners, configs, Flutter shims, App + CLI peer/backend/device assets
integration_test/     Flutter tooling shims only; real implementations live under tests/e2e/flutter/
scripts/              macOS bootstrap plus packaging scripts and config
```

## Requirements

- Flutter **3.24.0+**
- Dart **3.8.0+**
- Sibling workspace checkout at `../awiki-cli-rs2/packages/awiki_im_core`
- CocoaPods for macOS desktop development
- System `libsqlite3` and desktop dependencies for Linux desktop/E2E runners
- Tsinghua pub mirror is recommended for dependency installation

To rebuild Flutter SDK native artifacts from the sibling CLI repository:

```bash
cd ../awiki-cli-rs2
scripts/flutter/build-sdk-native.sh --macos-only     # common for macOS local development
scripts/flutter/build-sdk-native.sh --linux-only     # Linux CI / desktop E2E
scripts/flutter/build-sdk-native.sh --android-only   # Android packaging
```

## Quick Start

```bash
PUB_HOSTED_URL=https://mirrors.tuna.tsinghua.edu.cn/dart-pub flutter pub get
dart analyze
dart run tests/unit/runner.dart
flutter run
```

Recommended local gate:

```bash
PUB_HOSTED_URL=https://mirrors.tuna.tsinghua.edu.cn/dart-pub flutter pub get
dart analyze
dart run tests/unit/runner.dart
dart run tests/e2e/runner.dart --case smoke
```

The `smoke` E2E case uses Flutter desktop shims and native im-core smoke. It does not require a real OTP, real account, real backend, or `awiki-cli` binary.

## Runtime Configuration

Tenant configuration is managed inside the app, not through separate Flutter service URL flags. The login page has a low-emphasis tenant switcher in the bottom-right corner. Each tenant stores:

- local display name (1-40 visible characters)
- backend base URL
- DID host
- an immutable UUID Storage Scope

The default tenant is `AWiki`:

```text
backend base URL: https://awiki.ai
DID host: awiki.ai
storage scope: generated UUID (not derived from the domain)
```

The built-in tenant domain has one compile-time override. It accepts a lowercase
hostname only and keeps `awiki.ai` as the default:

```bash
flutter build macos --debug \
  --dart-define=AWIKI_PRIMARY_TENANT_DOMAIN=awiki.info
```

The App derives the built-in backend URL (`https://<domain>`), DID host, service
DID, update URL, and Daemon download URL from that single value. The override is
used only when creating a fresh tenant registry; it does not rewrite an existing
`tenant-registry.json` or move an existing Storage Scope.

Every tenant profile owns a different immutable `storage_scope_id`. Paths, the platform-secret account, and the im-core workspace/device context derive only from that UUID; tenant names and backend URLs never act as local locators. Switching tenants fully disposes the old runtime before opening the new scope. Names can be changed in place. A DID-host change requires a new tenant profile and scope; a backend route cannot be changed after local data exists without a future verified realm-binding flow.

Agent and Daemon features use an exact, bundled tenant-realm allowlist:
`awiki.ai`, `awiki.info`, and `anpclaw.com`. A tenant is enabled only when its
backend is the HTTPS origin for the allowlisted hostname and its DID host is the
same hostname. All other tenants fail closed, show the unsupported state, and do
not call Agent backend APIs.

The app still supports non-tenant build flags such as `AWIKI_E2E` and `AWIKI_E2E_APP_STATE_ROOT` for test harnesses.

The first production storage generation is the UUID Storage Scope clean cut. It does not read the pre-release `awiki.ai`, `tenant-default`, split-item, or namespace-bundle formats. See [docs/storage-scope-vault-contract.md](docs/storage-scope-vault-contract.md).

Pre-release namespace data is never migrated during startup. Developers can inventory or explicitly archive/delete it with the dry-run-first [storage cleanup runbook](docs/pre-release-storage-cleanup.md).

## Testing

See [docs/testing.md](docs/testing.md) for the full testing strategy.

| Test domain | Command | Purpose | Must not require |
| --- | --- | --- | --- |
| Unit / Widget / Provider | `dart run tests/unit/runner.dart` | Dart logic, mappers, providers, widgets, fake services, E2E runner planning/redaction | Real backend, OTP, CLI, devices |
| Desktop smoke E2E | `dart run tests/e2e/runner.dart --case smoke` | App shell, Flutter platform shims, native im-core open smoke | Real accounts, OTP, CLI peer |
| Signed production Keychain | `scripts/run_macos_production_scope_restart_gate.sh` | Release rebuild/process restart, production service isolation, exclusive create | Local AWiki services, secret output, ad-hoc signing |
| Remote App + CLI product E2E | `dart run tests/e2e/runner.dart --case full` | UI-driven direct/unread/read/retry, contacts, group/mention, attachment and exact-one App + CLI checks against `awiki.info` | Unconfigured account pools or committed local credentials |

Prepare real-backend E2E config locally:

```bash
cp tests/e2e/configs/e2e.example.yaml tests/e2e/configs/e2e.local.yaml
dart run tests/e2e/runner.dart --case full
```

Live App + CLI cases accept only the audited remote `awiki.info` target. Set
`cliPeer.sourceRef` in the ignored config to the exact commit that built both
the debug CLI and `awiki_im_core` artifacts. Suite membership, owners, timeout,
and cleanup policy live in `tests/e2e/suite_manifest.json`; reports include the
source ref, isolated `awiki.info` CLI tenant identity preflight, and a redacted
`resource_ledger.json`. Dry-run
and prepare-only output remain non-passing orchestration evidence.

The traceable case source is `tests/e2e/case_catalog.json`; the generated human
catalog is [docs/test-case-catalog.md](docs/test-case-catalog.md). Validate
manifest/catalog/implementation/report-ID drift with
`dart run tool/validate_test_catalog.dart`. Unit quality is guarded by a
checked-in line + branch baseline:

```bash
dart run tests/unit/runner.dart --branch-coverage
dart run tool/test_coverage_gate.dart
```

The baseline protects the whole suite plus chat, conversation, relationship,
read/sync state machines individually. Coverage is a regression floor, not a
claim that every product behavior has E2E coverage.

For the maintained remote gate, configure `service.baseUrl` as
`https://awiki.info` and `service.didDomain` as `awiki.info`. The App-side
actions in `full` must be visible input/tap/drop actions; service calls are
read-only result oracles. See [docs/testing.md](docs/testing.md) for the exact
message, unread/read, retry, relationship, mention, and attachment contracts.

Local YAML config is ignored by Git and may contain OTP, test accounts, backend URLs, and `awiki-cli` paths. Do not commit it. On macOS, choose an explicit macOS config such as `tests/e2e/configs/e2e.codex-macos-allowed.local.yaml`; do not accidentally use a Linux local config.

The repository configures `package:sqlite3` to use the system SQLite native asset hook. macOS includes SQLite. Linux machines need `libsqlite3-dev` or an equivalent system package.

## Packaging and Release Artifacts

Entrypoint:

```bash
scripts/package_app.sh
```

For a one-off package whose fresh built-in tenant uses another domain:

```bash
scripts/package_app.sh --primary-tenant-domain awiki.info
```

Config file: [`scripts/package_app.config`](scripts/package_app.config). For normal packaging, edit `PACKAGE_RELEASE_DOMAIN` and, when needed, `PACKAGE_TARGETS`:

```text
PACKAGE_RELEASE_DOMAIN="awiki.ai"    # current checked-in default
PACKAGE_RELEASE_DOMAIN="awiki.info"  # internal mirror / integration package downloads

PACKAGE_TARGETS="android-arm64,macos-arm64,macos-x64"  # all targets
PACKAGE_TARGETS="android-arm64"                        # Android only
PACKAGE_TARGETS="macos-arm64,macos-x64"                # macOS only
```

macOS trial packages require one stable, non-ad-hoc signing identity. Import the
certificate and private key into the Keychain, then copy
`scripts/package_app.local.config.example` to the Git-ignored
`scripts/package_app.local.config` and set the identity and Team ID. `.p12` and
`.pfx` bundles are transfer/backup artifacts and must not live in the repository.
Regular developers do not need the release identity: shared Debug builds default
to ad-hoc signing, with an optional Git-ignored
`macos/Runner/Configs/LocalSigning.xcconfig` for a developer's own stable TCC
identity. See [`docs/macos-signing.md`](docs/macos-signing.md).

The script uses `PACKAGE_RELEASE_DOMAIN` only for release artifact metadata: package download URLs, the generated update manifest location, and the download page. It does not inject backend base URL, DID host, state namespace, or update-check endpoint into the app; those are controlled by the app runtime and in-app tenant registry after launch.

Packaging behavior:

- Android arm64: Flutter release APK, signed through `android/key.properties` for internal distribution.
- macOS arm64 / x64: release DMG signed by the fixed Team ID; packaging fails
  before release if the Keychain identity is unavailable or the resulting app
  is ad-hoc, has the wrong Bundle ID, or has the wrong Team ID.
- Native SDK artifacts are rebuilt only for the selected targets.
- Android release packaging validates the production plugin registrant and blocks dev-only plugins such as `integration_test` from shipping.
- If exactly one Android emulator is connected, the script installs the APK, clears app data, and launches a startup smoke test by default.
- `dist/latest.json` contains the platforms produced by the current packaging run.
- Output:

```text
dist/<version>/
dist/latest.json
```

## Building on macOS with Xcode

Generate CocoaPods support files before opening Xcode:

```bash
scripts/prepare_macos_build.sh
open macos/Runner.xcworkspace
```

Open `Runner.xcworkspace`, not `Runner.xcodeproj`. If Xcode reports `Unable to load contents of file list: '/Target Support Files/Pods-Runner/...'`, the generated `macos/Pods` support files are missing or CocoaPods is not on `PATH`; rerun the bootstrap script.

macOS Debug/Profile builds use the separate `ai.awiki.awikime.dev` application identity and development Keychain service. User trial packages and future formal packages both use Release, `ai.awiki.awikime`, and `ai.awiki.awikime.scope-secrets`. Each scope has one versioned envelope at account `scope/<uuid>`. Runtime only reads an existing envelope; only explicit scope provisioning may create it. See [docs/identity-secret-storage.md](docs/identity-secret-storage.md).

Shared Debug defaults to ad-hoc signing so every developer can build. Developers who need a stable macOS Screen Recording TCC identity across rebuilds configure their own Apple Development identity, Team ID, and development Bundle ID through the Git-ignored `LocalSigning.xcconfig`. Debug is displayed as `AWikiMe (Development)` in macOS privacy settings so it cannot be confused with an installed Release `AWikiMe`. Reauthorize `ScreenCapture` after changing the signing identity or development Bundle ID. See [docs/macos-signing.md](docs/macos-signing.md).

After changing macOS signing, entitlements, or secure-storage options, run:

```bash
flutter test --no-pub integration_test/secure_storage_smoke_test.dart -d macos
```

## Security Boundaries

AWiki Me must follow these constraints:

- Do not commit real credentials, generated local state, signing keys, JWTs, private keys, or custom runtime config.
- Do not add Python CLI tools, Python dependency manifests, legacy credential migrations, or old RPC gateway paths.
- The App must not directly read or persist DID private keys, JWT files, vault records, Direct E2EE session/prekey secrets, or daemon subkey packages.
- Root keys must not appear in ordinary JSON state, logs, UI, E2E reports, performance traces, DTO dumps, or fixtures.
- Only an explicit E2E state root may select the private per-scope file provider under `awiki-me/e2e-scope-secrets`; those `0600` envelope files must remain local and untracked.
- Group E2EE opaque messages must not be decrypted and delivered to Agent prompts without a separate security design.
- Before changing platform runners, Pod/Gradle/Xcode metadata, entitlements, bundle IDs, or signing settings, confirm the task truly requires it. Revert unrelated platform files generated by tools.

## Key Documents

| Document | Purpose |
| --- | --- |
| [docs/testing.md](docs/testing.md) | Unit, desktop smoke, and real-backend E2E domains and gate policy |
| [docs/identity-secret-storage.md](docs/identity-secret-storage.md) | App-side identity vault, root key provider, E2E file provider, and security red lines |
| [docs/storage-scope-vault-contract.md](docs/storage-scope-vault-contract.md) | First-release UUID Storage Scope, stable Keychain locator, provision/open, and lifecycle contract |
| [docs/scope-secret-platform.md](docs/scope-secret-platform.md) | Typed scope envelope, platform provider isolation, and native/E2E security gates |
| [docs/conversation-presentation-ownership.md](docs/conversation-presentation-ownership.md) | Conversation display, local-first path, timeline, read waterline, attachment / mention / control payload rendering boundaries |
| [docs/performance-tracing.md](docs/performance-tracing.md) | Startup, list, chat-open, sync/realtime performance trace keys and diagnosis |
| [docs/message-agent/message-agent-design.md](docs/message-agent/message-agent-design.md) | Message Agent MVP, daemon binding, delegated key, secure bootstrap, disable/delete behavior |
| [docs/group/group-chat-processing-plan.md](docs/group/group-chat-processing-plan.md) | Runtime Agent group-message handling, group session isolation, and safety prompt gate |
| [docs/awiki-me-prd.md](docs/awiki-me-prd.md) | Product positioning, information architecture, core objects, MVP flows, and acceptance criteria |
| [../awiki-cli-rs2/docs/api/im-core-interface/README.md](../awiki-cli-rs2/docs/api/im-core-interface/README.md) | Sibling SDK / Rust im-core API entry |
| [../awiki-cli-rs2/docs/architecture/identity-secret-storage.md](../awiki-cli-rs2/docs/architecture/identity-secret-storage.md) | Shared CLI / SDK / daemon identity secret storage design |

## Contributor Checklist

1. Keep changes scoped to the platform and shared Dart code required by the task.
2. Pair behavior changes with tests. Prefer `tests/unit/`; add `tests/e2e/` when platform, backend, CLI peer, or device flows are involved.
3. Run and record:

   ```bash
   PUB_HOSTED_URL=https://mirrors.tuna.tsinghua.edu.cn/dart-pub flutter pub get
   dart analyze
   dart run tests/unit/runner.dart
   dart run tests/e2e/runner.dart --case smoke
   ```

4. Run real backend, CLI peer, OTP, mobile-device, or release packaging validation only when that environment is prepared, and record the configuration context.
5. Check `git diff` for unrelated platform generated files, local config, E2E reports, secrets, and absolute paths.

## License

This repository uses [Apache License 2.0](LICENSE). For the ANP protocol documents and upstream implementations, refer to the official ANP repository: <https://github.com/agent-network-protocol/AgentNetworkProtocol>.
