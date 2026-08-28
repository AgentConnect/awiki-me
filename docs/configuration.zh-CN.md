# 配置说明

[English](configuration.md) | [简体中文](configuration.zh-CN.md)

本文是 **awiki-me** 的权威配置说明。绝大多数旋钮是编译期 `--dart-define` / `String.fromEnvironment` / `bool.fromEnvironment`，运行时不可改。入口：`lib/src/application/config/awiki_environment_config.dart`。

user/message/mail/ANP URL **全部**由 `https://$AWIKI_PRIMARY_TENANT_DOMAIN` 派生，不再读 `AWIKI_USER_SERVICE_URL` 一类运行时 env。

## 身份 / 租户 / 多设备 / 同步

| 标识符 | 来源 | 作用 | 默认值 |
| --- | --- | --- | --- |
| `AWIKI_PRIMARY_TENANT_DOMAIN` | Dart `fromEnvironment` | 主租户域，派生全部服务 URL | `awiki.ai` |
| `AWIKI_MULTI_DEVICE_AUDIENCE` | Dart `fromEnvironment` | 多设备 audience；空会抛错 | `awiki-user-service` |
| `AWIKI_MULTI_DEVICE_DEVICE_REVOKE_ENABLED` | Dart `fromEnvironment` | 设备吊销能力 | `true` |
| `AWIKI_MULTI_DEVICE_DIRECT_E2EE_ENABLED` | Dart `fromEnvironment` | Direct E2EE **能力**（不是强制加密） | `true` |
| `AWIKI_MULTI_DEVICE_GROUP_E2EE_ENABLED` | Dart `fromEnvironment` | Group E2EE **能力** | `true` |
| `AWIKI_SYNC_V2_READ` | Dart `fromEnvironment` | Sync V2 读 | `true` |
| `AWIKI_RELEASE` | Dart `fromEnvironment` | 产品发布线 | `0815` |
| `defaultDirectMessageE2eeRequired` | **源码常量** | 私信是否默认强制 P5 | **`false`**（默认可发明文） |
| `defaultGroupCreationE2eeRequired` | **源码常量** | 建群是否默认强制 P6 | **`false`**（默认普通群） |

DID transition：App 不读 CLI 环境变量。im-core `ImCoreOpenOptions` 默认 `did_transition_vnext_hidden_rollout_enabled=true`，Dart 映射从 Default 继承。

原生 `im-core-dart` 当前 Flutter 构建 feature **没有 `secure-direct`**。即使 Direct E2EE 能力开关为 true，App 原生库也编不进 P5 实现，直到落地 PR-3。

## Push（Android EMAS / iOS xcconfig）

| 标识符 | 来源 | 作用 | 默认值 |
| --- | --- | --- | --- |
| `debug.enabled` 等 | `android/emas.properties` | Debug EMAS | `false` / 空 |
| `AWIKI_EMAS_ENABLED` | Android `BuildConfig` / iOS Info.plist | 运行时是否初始化推送 | `false` / iOS `NO` |
| `AWIKI_EMAS_APP_KEY` / `APP_SECRET` | 同上 | EMAS 凭证 | `""` |

## 可观测性 / 测试

| 标识符 | 来源 | 默认值 |
| --- | --- | --- |
| `AWIKI_PERF_LOG` | Dart define | `false` |
| `AWIKI_PERF_LOG_LEVEL` | Dart define | `off` |
| `AWIKI_E2E` | Dart define | `false` |
| `AWIKI_MACOS_NOTIFICATION_SMOKE` | Dart define | `false` |
| 其余 `AWIKI_*_TRACE` | Dart define | `false` |

`SPARKLE_FEED_URL`（macOS）：`https://agentconnect.github.io/awiki-me/updates/appcast.xml`。
