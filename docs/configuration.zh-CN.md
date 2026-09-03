# 配置说明

[English](configuration.md) | [简体中文](configuration.zh-CN.md)

本文是 **awiki-me** 的权威配置说明。内置租户目录是打包期 JSON 输入，其余功能开关使用编译期 `--dart-define`。加载器位于 `lib/src/application/config/`。

## 身份 / 租户 / 多设备 / 同步

| 标识符 | 来源 | 作用 | 默认值 |
| --- | --- | --- | --- |
| `scripts/package_app.sh --tenant-config FILE` | 打包参数 | 完整替换两个内置租户槽位 | `assets/config/builtin-tenants.default.json` |
| `AWIKI_BUILTIN_TENANTS_BASE64` | 内部 Dart define | 打包 worker 传入的完整已校验 JSON | 由 `package_app.sh` 生成 |
| `AWIKI_BUILTIN_TENANTS_SHA256` | 内部 Dart define | 将运行时目录与打包元数据绑定 | 由 `package_app.sh` 生成 |
| `AWIKI_MULTI_DEVICE_AUDIENCE` | Dart `fromEnvironment` | 多设备 audience；空会抛错 | `awiki-user-service` |
| `AWIKI_MULTI_DEVICE_DEVICE_REVOKE_ENABLED` | Dart `fromEnvironment` | 设备吊销能力 | `true` |
| `AWIKI_MULTI_DEVICE_DIRECT_E2EE_ENABLED` | Dart `fromEnvironment` | Direct E2EE **能力**（不是强制加密） | `true` |
| `AWIKI_MULTI_DEVICE_GROUP_E2EE_ENABLED` | Dart `fromEnvironment` | Group E2EE **能力** | `true` |
| `AWIKI_SYNC_V2_READ` | Dart `fromEnvironment` | Sync V2 读 | `true` |
| `AWIKI_RELEASE` | Dart `fromEnvironment` | 产品发布线 | `0815` |
| `defaultDirectMessageE2eeRequired` | **源码常量** | 私信是否默认强制 P5 | **`false`**（默认可发明文） |
| `defaultGroupCreationE2eeRequired` | **源码常量** | 建群是否默认强制 P6 | **`false`**（默认普通群） |

DID transition：App 不读 CLI 环境变量。im-core `ImCoreOpenOptions` 默认 `did_transition_vnext_hidden_rollout_enabled=true`，Dart 映射从 Default 继承。

原生 `im-core-dart` Flutter 构建已编进 `group-e2ee` 与 `secure-direct`。`defaultDirectMessageE2eeRequired` 与 `defaultGroupCreationE2eeRequired` 仍为 `false`（默认可发明文 / 建普通群）。

租户 JSON 使用 `schema_version=1`、`default_slot`，并且只能包含
`primary`、`secondary` 两个槽位；每个槽位提供中英文名称、
`backend_origin` 和 `did_host`。传入覆盖文件时整体替换，绝不与官方默认值
逐字段合并。生产端点必须是 HTTPS Origin，开发构建仅额外允许 loopback HTTP。

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
