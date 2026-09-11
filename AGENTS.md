# Repository Guidelines

## Shared rules

Engineering work follows [AI Coding Rules](../awiki-harness/rules/ai-coding-rules.md).
Behavior changes and verification follow the relevant [Verification Policy](../awiki-harness/rules/verification-policy.md)
sections; production behavior needs owning unit coverage and applicable System/product E2E review.
If Harness is absent, use local docs/tests/CI and disclose missing acceptance evidence.

## Project Structure & Module Organization
`lib/` contains the Flutter application. Domain contracts live in
`lib/src/domain/`, Dart service clients and persistence live in
`lib/src/data/`, and UI/providers live in `lib/src/presentation/`.
`tests/unit/` contains fast Dart logic, widget, provider, and fake-backed
harness tests. `tests/e2e/` contains E2E runners, configs, Flutter shim
implementations, and App + CLI peer/backend/device validation assets.
`tests/computer-use/` contains playbooks for a screen-using AI or human; it is
not a Dart runner and does not replace `tests/e2e/`. Root
`integration_test/*.dart` files are Flutter-tooling shims only. Platform runners live under
`android/`, `ios/`, `macos/`, and `web/`. Static assets live in `assets/`.

## Documentation
Follow this file, [`CLAUDE.md`](CLAUDE.md), and `docs/`. Do not apply the GEB fractal protocol, and do not add a `CLAUDE.md` to every directory.

## Architecture Guardrail
Preserve Core ownership, canonical identity, fail-closed behavior and migration
constraints. Locate the affected contract or section before editing:

- Conversation/list/detail/profile display, rendering and overlays: use the relevant
  owner, mapping, preview or timeline sections of
  [presentation ownership](docs/conversation-presentation-ownership.md).
- Storage Scope, tenant switch, vault lifecycle or upgrade: use the corresponding
  ownership, provision/open, route/switch or upgrade sections of
  [storage contract](docs/storage-scope-vault-contract.md).
- Core-owned identity, read/send/sync or realtime behavior: use the affected sections
  of [Core architecture](../awiki-cli-rs2/docs/architecture/im-core-sdk-architecture.md),
  such as `Host vs SDK Responsibilities`, `Identity Model`, `Reliable Message Sync`
  and `Conversation Read State`.

Read additional sections when the change crosses those boundaries or leaves a
contract question unresolved. Reuse established context; these links are not a
mandatory full-document reading sequence. Update the affected authoritative contract
before implementing a change to the architecture itself.

## Build, Test, and Development Commands
Use Flutter/Dart tooling only. When installing dependencies, prefer the
Tsinghua pub mirror:

```bash
PUB_HOSTED_URL=https://mirrors.tuna.tsinghua.edu.cn/dart-pub flutter pub get
dart analyze
dart run tests/unit/runner.dart
flutter run
```

Routine macOS Debug builds must detect the current host instead of fixing one
chip in test code: Intel uses `x86_64-apple-darwin`, Apple Silicon uses
`arm64-apple-darwin`, and the sibling `awiki_im_core` artifact must contain the
same native architecture. A Rosetta-translated x86 process on Apple Silicon is
reported explicitly and is not accepted as a native host build. Do not compile
a universal macOS XCFramework during routine debugging unless the user asks for
universal, Release, or packaging output. Keep the Flutter App itself as a Debug
incremental build.

For manual macOS dual-App runs, use
`scripts/build_manual_dual_macos_apps.sh`. It builds normal `lib/main.dart`
Admin/Joiner Apps with separate build roots and bundle IDs but one tenant
domain. Never use `.e2e/` App-pair artifacts or
`tool/build_isolated_e2e_app.dart`; those require the E2E runner and can
black-screen when opened manually.

## Coding Style & Naming Conventions
Target Dart 3.8+ and Flutter 3.41+. Follow the repository lint rules in
`analysis_options.yaml`. Keep files and functions in `snake_case`, classes in
`PascalCase`, constants in `lowerCamelCase` or `SCREAMING_CAPS` only when that
matches the surrounding code. Keep widgets focused and move reusable business
logic into `lib/src/data/` or `lib/src/domain/`.

## Testing Guidelines
Tests use `flutter_test`. Name test files `*_test.dart` and keep tests in the
correct active test domain:

- `tests/unit/`: fast deterministic checks for Dart logic, mappers,
  application/data services, providers, widgets, and pure E2E harness planning
  with fakes. These must not require real devices, real services, OTP, or CLI
  subprocesses.
- `tests/e2e/`: E2E runners, configs, Flutter shim implementations, platform
  smoke tests, real App + CLI peer/backend/device flows, reports, and redaction
  rules. Root `integration_test/*.dart` files must stay thin Flutter tooling
  shims that import implementations from `tests/e2e/flutter/`.
- `tests/computer-use/`: operator/AI playbooks for visible App actions on two
  real macOS Debug windows. Do not add a `--case` to `tests/e2e/runner.dart`
  for this domain, and do not treat a computer-use pass as Dart E2E
  attestation. Start at `tests/computer-use/README.md`.

When running AWiki Me E2E, select the desktop strategy from the current host
instead of treating macOS as a universal prerequisite. On macOS, use the macOS
runner/config (`platform: macos`). On Linux, use the Linux desktop simulation
supported by the E2E runner (`platform: linux`), which runs Flutter under Xvfb
and therefore requires `xvfb-run`. Linux-hosted desktop E2E, including the
isolated dual-App multi-device suites, must execute in that simulated desktop
environment; do not replace the real run with a macOS-shaped dry-run or skip it
only because the host is Linux. The messaging App + CLI peer flow and product-level
multi-device account, messaging, attachment, and read-state assertions are
valid on both hosts; by default run `dart run tests/e2e/runner.dart --case full`
with a local config for the detected platform. `full` aggregates every active
audited case, including App-pair, Recovery, Root Transfer and native gates;
`messaging` selects only the former 24-case flow. Require macOS only for an
assertion that genuinely depends on macOS operating-system behavior, such as
codesigning, Keychain, or LocalAuthentication, and never claim that Linux
simulates or attests those macOS-specific behaviors.

The suite platform schema also preserves `windows`; the existing Windows x64
build/native-smoke CI remains authoritative for that lane. The Mac/Linux E2E
runner must not silently treat Windows as an unknown platform or delete that
gate.

Use focused unit/provider/widget coverage for App behavior. Review native/bootstrap
smoke coverage when routing, platform bindings, native plugins or visual surfaces
change, and product E2E when real backend, CLI peer, account/OTP, multi-client or
device flows change. Reuse exact existing coverage and add only missing coverage
for this change, following Verification Policy. Cross-service System Tests remain
in `../awiki-system-test`; product E2E implementations exclusively belong to
`tests/e2e/` in this repository.

For development/test OTP flows, load the protected phone and code only from
the ignored, permission-restricted local E2E configuration. Never place those
values in tracked files, process arguments, run configuration, reports, or
test artifacts.

## Multi-Platform Safety
AWiki Me supports Android, iOS, macOS, and web. When fixing or changing one
platform, keep the diff scoped to that platform plus shared Dart code that is
strictly required. Do not modify another platform runner, generated registrant,
Pod/Gradle/Xcode metadata, entitlements, bundle IDs, signing settings, or
runtime behavior unless the task explicitly requires it. If a tool regenerates
unrelated platform files, inspect and revert those unrelated changes before
committing.

## App and Core Responsibilities

The App uses Dart/Flutter for UI, navigation, application orchestration and platform
adapters. Identity/vault, DID-WBA authentication, message proofs, IM and reliable
sync use the existing `awiki_im_core` facade backed by Rust Core. Keep User Service
calls in their established owning adapter/facade; do not move Core-owned contracts
into a parallel Dart protocol implementation. The current ownership contracts and
[repository context](CLAUDE.md) define the boundaries.

Do not add Python CLI tools, Python dependency manifests, legacy credential
migrations or old RPC gateway paths.

## Security & Configuration Tips
Do not commit real credentials, generated local state, signing keys, or custom
runtime configuration. Account identities remain e1 DID-only. Credential and key
storage follow the existing Core vault and platform secret-provider contracts.
