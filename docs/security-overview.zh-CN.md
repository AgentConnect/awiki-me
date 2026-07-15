# AWiki Me 安全模型概览

[English](security-overview.md) | [简体中文](security-overview.zh-CN.md)

本文提供面向采用者和贡献者的安全摘要。App 侧身份密钥存储的权威实现说明仍以 `docs/identity-secret-storage.md`、`docs/storage-scope-vault-contract.md` 和 `docs/scope-secret-platform.md` 为准。

## 1. 信任边界

```text
Tenant Registry
  -> immutable storage_scope_id
     -> platform secret account scope/<uuid>
     -> workspace/device context
     -> AwikiImCoreOpenOptions.vaultRequired
     -> awiki-im-core Identity SecretVault
```

AWiki Me 负责：

- UI 和用户确认；
- 租户选择与 runtime 生命周期；
- 产品级展示状态；
- 调用高层 SDK API。

共享 IM Core 负责：

- DID 身份与认证状态；
- 消息、会话、outbox、sync 和 read state；
- 身份 SecretVault；
- Direct E2EE session/prekey 等敏感状态；
- 向 App 返回脱敏后的状态与错误码。

## 2. App 不应持有的材料

App 普通状态、日志、UI、报告或 DTO dump 中不得出现：

- DID private key；
- JWT / bearer token；
- SecretVault root key 或 raw `SecretRef`；
- Direct E2EE root/chain/skipped keys；
- Daemon delegated/subkey package；
- 签名证书私钥；
- 真实 OTP、E2E 测试账号和本地绝对路径。

## 3. Storage Scope

每个租户具有不可变 UUID `storage_scope_id`。以下资源由该 UUID 派生或绑定：

- App 本地数据路径；
- Product SQLite；
- attachment cache/temp；
- 平台 secure-storage account；
- im-core workspace/device context；
- identity vault。

租户名称、域名和 backend URL 不能作为本地 locator。重命名租户不应移动安全存储；修改 DID host 应创建新的租户与 scope。

## 4. Provision 与打开

只有显式 provision 流程可以生成 root key 并创建 scope envelope。普通 runtime 只能读取既有 envelope，并在打开后验证已有 identity vault。

以下情况必须 fail closed：

- key 缺失或访问被拒绝；
- envelope 损坏或 schema 未知；
- workspace/device metadata 不匹配；
- scope owner/path 不匹配；
- identity vault 验证失败。

失败后不得：

- 生成替代 root key；
- 回退明文；
- 静默扫描旧版身份目录；
- 自动执行不可审计迁移。

## 5. 租户切换

安全切换顺序：

```text
停止 realtime
→ 等待 active Core 操作完成
→ dispose client/core
→ 关闭 Product SQLite
→ 打开新 scope
→ 验证 identity vault
→ 提交新的 active tenant
```

旧 runtime 未完全释放前，不得同时打开新 scope。候选租户打开或提交失败时，应销毁候选并恢复旧 runtime，避免 UI 与磁盘状态分裂。

## 6. Debug 与 Release 隔离

- Release application identity：`ai.awiki.awikime`；
- Debug/Profile identity：`ai.awiki.awikime.dev` 或受控 suffix；
- Release 和开发使用不同 Keychain service、Bundle ID 与本地数据根；
- 共享 Debug 默认允许 ad-hoc 构建，但这不等于生产签名证据；
- 正式 macOS 包必须通过稳定 identity、Team/Bundle 校验与进程重启 Gate。

## 7. E2EE 表述

SecretVault 保护本地身份与安全消息材料，但它不自动证明：

- 每条消息都使用 E2EE；
- 服务端支持对应安全协议；
- Group E2EE 已在所有路径完整处理；
- 对端客户端支持同一安全 profile。

连接无 E2EE 的服务端时，README 必须明确标注。

## 8. 安全测试入口

```bash
dart run tests/unit/runner.dart
dart run tests/e2e/runner.dart --case smoke
scripts/run_macos_production_scope_restart_gate.sh
```

真实 App + CLI、账号和远端服务测试需要本地 ignored 配置。测试报告必须脱敏，不能作为密钥或 token 的传输渠道。

## 9. 漏洞报告

请遵循仓库根目录 [SECURITY.md](../SECURITY.zh-CN.md)。不要在公开 Issue 中发布可利用步骤、真实身份材料、token 或用户数据。
