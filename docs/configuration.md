# Configuration

[English](configuration.md) | [简体中文](configuration.zh-CN.md)

Authoritative configuration for **awiki-me**. Most knobs are compile-time `--dart-define` / `fromEnvironment`. Loader: `lib/src/application/config/awiki_environment_config.dart`. Service URLs are derived from `https://$AWIKI_PRIMARY_TENANT_DOMAIN`.

## Identity / tenant / sync

| Key | Source | Purpose | Default |
| --- | --- | --- | --- |
| `AWIKI_PRIMARY_TENANT_DOMAIN` | Dart `fromEnvironment` | Primary tenant; derives all service URLs | `awiki.ai` |
| `AWIKI_MULTI_DEVICE_AUDIENCE` | Dart `fromEnvironment` | Multi-device audience; empty throws | `awiki-user-service` |
| `AWIKI_MULTI_DEVICE_DEVICE_REVOKE_ENABLED` | Dart `fromEnvironment` | Device revoke capability | `true` |
| `AWIKI_MULTI_DEVICE_DIRECT_E2EE_ENABLED` | Dart `fromEnvironment` | Direct E2EE **capability** (not force-encrypt) | `true` |
| `AWIKI_MULTI_DEVICE_GROUP_E2EE_ENABLED` | Dart `fromEnvironment` | Group E2EE **capability** | `true` |
| `AWIKI_SYNC_V2_READ` | Dart `fromEnvironment` | Sync V2 read | `true` |
| `AWIKI_RELEASE` | Dart `fromEnvironment` | Release line | `0815` |
| `defaultDirectMessageE2eeRequired` | source constant | Force P5 on DMs | **`false`** |
| `defaultGroupCreationE2eeRequired` | source constant | Force P6 on group create | **`false`** |

DID transition: App does not read the CLI env. im-core `ImCoreOpenOptions` defaults `did_transition_vnext_hidden_rollout_enabled` to **true**.

Flutter `im-core-dart` builds include `group-e2ee` and `secure-direct`. `defaultDirectMessageE2eeRequired` and `defaultGroupCreationE2eeRequired` stay `false`.

## Push / observability / tests

| Key | Default |
| --- | --- |
| `AWIKI_EMAS_ENABLED` | `false` / iOS `NO` |
| `AWIKI_PERF_LOG` | `false` |
| `AWIKI_E2E` | `false` |
| trace defines | `false` |
