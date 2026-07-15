# AWiki Me Security Model Overview

[English](security-overview.md) | [简体中文](security-overview.zh-CN.md)

This document summarizes the security model for adopters and contributors. The authoritative app-side identity-key storage design remains in `docs/identity-secret-storage.md`, `docs/storage-scope-vault-contract.md`, and `docs/scope-secret-platform.md`.

## 1. Trust boundary

```text
Tenant Registry
  -> immutable storage_scope_id
     -> platform secret account scope/<uuid>
     -> workspace/device context
     -> AwikiImCoreOpenOptions.vaultRequired
     -> awiki-im-core Identity SecretVault
```

AWiki Me owns UI and user confirmation, tenant selection and runtime lifecycle, product-visible state, and calls to high-level SDK APIs.

The shared IM Core owns DID identity and authentication state; messages, conversations, outbox, sync, and read state; the identity SecretVault; sensitive Direct E2EE session/prekey state; and redacted status/error codes returned to the app.

## 2. Material the app must not hold

Normal app state, logs, UI, reports, and DTO dumps must never contain:

- DID private keys;
- JWTs or bearer tokens;
- SecretVault root keys or raw `SecretRef` values;
- Direct E2EE root, chain, or skipped keys;
- Daemon delegated-key or subkey packages;
- signing-certificate private keys; or
- real OTPs, E2E accounts, and local absolute paths.

## 3. Storage Scope

Every tenant has an immutable UUID `storage_scope_id`. It derives or binds the app data path, Product SQLite, attachment cache/temp, platform secure-storage account, im-core workspace/device context, and identity vault.

Tenant names, domains, and backend URLs are not local locators. Renaming a tenant must not move secure storage; changing a DID host should create a new tenant and scope.

## 4. Provisioning and opening

Only an explicit provisioning flow may generate a root key and create a scope envelope. A normal runtime may only read an existing envelope and verify the identity vault after opening it.

The following must fail closed:

- a missing or inaccessible key;
- a damaged envelope or unknown schema;
- mismatched workspace/device metadata;
- mismatched scope owner/path; or
- identity-vault verification failure.

After failure, do not generate a replacement root key, fall back to plaintext, silently scan legacy identity directories, or run an unauditable migration.

## 5. Tenant switching

```text
Stop realtime
-> wait for active Core operations
-> dispose client/core
-> close Product SQLite
-> open the new scope
-> verify the identity vault
-> commit the new active tenant
```

Do not open a new scope until the old runtime is fully released. If opening or committing the candidate tenant fails, destroy the candidate and restore the old runtime to avoid splitting UI and disk state.

## 6. Debug and Release isolation

- Release application identity: `ai.awiki.awikime`
- Debug/Profile identity: `ai.awiki.awikime.dev` or a controlled suffix
- Release and development use different Keychain services, Bundle IDs, and local data roots.
- Shared Debug builds may use ad-hoc signing by default; that is not evidence of production signing.
- Production macOS packages must pass stable identity, Team/Bundle, and process-restart gates.

## 7. E2EE wording

SecretVault protects local identity and secure-message material, but does not prove that every message uses E2EE, the server supports the secure protocol, Group E2EE is complete on every path, or the peer supports the same secure profile.

The README must state clearly when a connected server has no E2EE.

## 8. Security test entry points

```bash
dart run tests/unit/runner.dart
dart run tests/e2e/runner.dart --case smoke
scripts/run_macos_production_scope_restart_gate.sh
```

Real App/CLI, account, and remote-service tests require ignored local configuration. Reports must be redacted and must never become a transport for keys or tokens.

## 9. Vulnerability reporting

Follow the repository [SECURITY.md](../SECURITY.md). Do not post exploitation steps, real identity material, tokens, or user data in a public issue.
