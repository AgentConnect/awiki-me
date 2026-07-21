# AWiki Me Development Guide

[English](development.md) | [简体中文](development.zh-CN.md)

## 1. Technology stack

- Flutter 3.41+
- Dart 3.8+
- Riverpod
- Sibling `awiki_im_core` Flutter/Dart SDK
- Rust `awiki-im-core` with a native SQLite bridge
- Android, iOS, and macOS platform runners

## 2. Layers

```text
lib/src/presentation/   Pages, providers, components, responsive layout, user feedback
lib/src/application/    Use-case orchestration, sessions, messages, groups, contacts, agents, attachments, tenants
lib/src/domain/         Entities, repository/port contracts, pure domain logic
lib/src/data/           Service clients, im-core adapters, local/secure storage, platform bridges
```

Core rules:

- The app uses high-level `awiki_im_core` APIs.
- Do not rebuild DID proofs, raw RPC, WebSocket frames, reliable checkpoints, or internal E2EE state in the Dart UI layer.
- Product overlays may exist, but they must not replace Core as the source of truth.
- Every behavior change requires corresponding tests.

## 3. Environment setup

```bash
cd ../awiki-cli-rs2
scripts/flutter/build-sdk-native.sh --macos-only

cd ../awiki-me
flutter pub get
```

Use the option for the target platform when needed:

```bash
scripts/flutter/build-sdk-native.sh --linux-only
scripts/flutter/build-sdk-native.sh --android-only
scripts/flutter/build-sdk-native.sh --ios-only
```

## 4. Routine development gates

```bash
dart analyze
dart run tests/unit/runner.dart
dart run tests/e2e/runner.dart --case smoke
```

Branch coverage and regression baseline:

```bash
dart run tests/unit/runner.dart --branch-coverage
dart run tool/test_coverage_gate.dart
```

Real remote App and CLI peer flow:

```bash
cp tests/e2e/configs/e2e.example.yaml tests/e2e/configs/e2e.local.yaml
dart run tests/e2e/runner.dart --case full
```

Never commit real configuration, OTPs, accounts, CLI paths, or reports.

## 5. Test ownership

| Directory | Responsibility |
| --- | --- |
| `tests/unit/` | Pure Dart, widgets, providers, mappers, fake-backed services, and runner logic. |
| `tests/e2e/` | Desktop user flows, platform shims, native plugins, CLI peers, backend, and device orchestration. |
| `integration_test/` | Flutter tooling discovery entry points; keep only thin imports here. |
| `.e2e/` | Local reports and state; Git must ignore this directory. |

Do not place real product E2E logic in the root `integration_test/` directory.

## 6. Repository structure

```text
lib/                  Flutter application source
assets/               Brand, icons, and static assets
android/ ios/ macos/ web/
                      Platform runners
packages/             App-internal packages, if any
scripts/              Bootstrap, packaging, signing, and verification scripts
docs/                 Product, architecture, security, testing, and implementation plans
tests/unit/            Fast deterministic tests
tests/e2e/             E2E runner and platform implementations
```

## 7. Tenants and configuration

Use the in-app tenant switcher during normal development. Do not add a new Flutter flag for every service URL.

The only built-in primary-tenant compile-time override is:

```bash
flutter build macos --debug \
  --dart-define=AWIKI_PRIMARY_TENANT_DOMAIN=awiki.info
```

This value only changes the initial built-in tenant for a new tenant registry. It is not a runtime selector and does not rewrite an existing scope.

## 8. Packaging

```bash
scripts/package_app.sh
```

Default output:

```text
dist/<version>/
dist/latest.json
```

Targets are controlled by `scripts/package_app.config`:

```text
android-arm64
macos-arm64
macos-x64
windows-x64
```

The default remains Android arm64 plus both macOS architectures; Windows must be selected explicitly. The local script validates clean, exactly pushed APP/Core refs, dispatches the pinned GitHub Actions workflow, waits for the exact request ID, and downloads the aggregate artifact. It never changes `pubspec.yaml` or builds a package locally.

macOS trial and production packages must use a stable, non-ad-hoc signing identity. Android/macOS signing material and the read-only private Core token live in the protected `app-packaging` GitHub Environment. Private keys, `.p12`, `.pfx`, and local signing configuration must never enter the repository. Windows installers are unsigned in this phase. See [Windows x64 packaging](windows-packaging.md) for installer, data-preservation, and CI details.

## 9. Change checklist

Before submitting, confirm that:

- no unrelated generated Xcode, Gradle, or Pod metadata is included;
- no real token, private key, OTP, local YAML, E2E report, or absolute path is included;
- new UI has Widget or Provider tests;
- platform behavior has Smoke E2E coverage;
- cross-App/CLI/service behavior has a reproducible E2E record; and
- the README, screenshots, and compatibility documentation match the behavior.
