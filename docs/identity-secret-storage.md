# AWiki Me Identity Secret Storage

Status: active  
Authority: authoritative for AWiki Me App-side identity vault integration

本文档记录 AWiki Me 首发 Storage Scope runtime 如何接入 Flutter SDK / Rust
`im-core` SecretVault。长期 locator、schema 与 lifecycle 以
[Storage Scope / Keychain / Vault Contract](storage-scope-vault-contract.md) 为准；平台细节见
[Scope Secret Platform Provider](scope-secret-platform.md)。

## 1. 当前架构

```text
Tenant Registry
  -> immutable storage_scope_id
    -> storage-scopes/<uuid>/im-core/identity-vault
    -> platform account scope/<uuid>
    -> workspace awiki-me.scope.v1.<uuid>
    -> device context awiki-me.scope-device.v1.<uuid>
      -> AwikiImCoreOpenOptions.vaultRequired
        -> im-core identity SecretVault
```

租户显示名称、backend URL、DID Host、`awiki.ai` 和 `tenant-default` 都不参与上述 locator。
App 不直接读写 DID 私钥、JWT 文件、vault record、Direct E2EE key material 或 daemon
subkey package。

## 2. Provision 与 OpenExisting

只有 `StorageScopeProvisioner` 可以生成 root key，并通过
`ScopeSecretRepository.createExclusive` 创建 envelope v1。Runtime 的顺序固定为：

1. 按 Registry 找到 active profile 与 `storage_scope_id`；
2. 校验 ready manifest、owner 与 scope path；
3. `readExisting(scopeId)` 并严格解码 envelope；
4. 由 scope UUID 派生 workspace/device context；
5. 使用 `VaultRequired` 打开 im-core；
6. 枚举已有 identity，逐个调用 `verifyIdentityVault`；
7. 只有全部通过后才向 App 暴露 runtime。

Runtime 没有 `getOrCreate`、upsert、legacy scan 或 migration。missing、denied、corrupt、scope
mismatch、unknown schema、wrong root、metadata/context mismatch 全部 fail closed。已有 scope 缺 key
返回 `vault_key_missing`，绝不生成替代 key。

## 3. 平台与宿主隔离

- macOS/iOS/Android production application identity：`ai.awiki.awikime`；
- debug/profile：`ai.awiki.awikime.dev`；
- production service：`ai.awiki.awikime.scope-secrets`；
- development service：`ai.awiki.awikime.dev.scope-secrets`；
- account：`scope/<canonical-uuid-v4>`；
- E2E：显式 state root 下 `awiki-me/e2e-scope-secrets/<scope>.json`，目录 `0700`、文件和锁 `0600`。

App、CLI、daemon 是独立 host，不共享 secure-storage item、root key 或 locator namespace。

## 4. 身份验证 Gate

`AwikiImCoreRuntime.open()` 会验证所有已有 identity；身份激活前
`ensureIdentityVault()` 还会再次调用 `verifyIdentityVault`。App 按 SDK 的 stable error code
处理 unavailable、metadata missing/unverified、workspace/device mismatch、record-open 和
verification failure，不解析 human message，也不执行旧 identity migration。

## 5. Tenant 切换与本地状态

切换顺序是 stop realtime → 等待 active core operations → dispose client/core → close Product
SQLite → open new scope。旧 runtime 完全释放前不得打开新 runtime。Product DB、attachments、
active identity、im-core state/cache/temp 都从统一 `AwikiStorageScopeLayout` 获取或由 scope UUID
派生，不能自行拼接域名目录。

切换 active tenant 或修改 active tenant route 时先生成未持久化 registry candidate；只有旧
runtime 已释放且 candidate runtime 已成功打开后，才用 revision CAS 提交 registry。打开或提交
失败时销毁 candidate，并按旧 registry 重新打开原 scope，避免“UI 回滚但磁盘已切换”的半提交。

## 6. E2E 与发布 Gate

Native smoke 覆盖显式 provision、native `VaultRequired` open、同一进程重新创建 runtime 后读取同一
root，以及删除 key 后 openExisting 不重建。Debug smoke 不是 production Team-signing 或真实 App
进程重启证据；`scripts/run_macos_production_scope_restart_gate.sh` 是独立 release Gate：每个阶段重新
构建并用同一稳定 identity签名production bundle，分别启动 provision/reopen/cleanup App进程，校验
Team/bundle identity、dev/prod service隔离、revision 1持续存在和duplicate create拒绝。

相关测试：

- `tests/unit/data/storage/`
- `tests/unit/data/im_core/awiki_im_core_secret_storage_test.dart`
- `tests/unit/data/im_core/awiki_im_core_runtime_test.dart`
- `tests/unit/data/tenant/app_tenant_store_test.dart`
- `tests/unit/tenant_runtime_transition_test.dart`
- `tests/e2e/flutter/native/im_core_open_smoke_test.dart`
- `tests/e2e/flutter/native/secure_storage_smoke_test.dart`
- `tests/e2e/flutter/native/production_scope_restart_probe.dart`

## 7. 安全红线

AWiki Me 不得：

- 读取预发布 split item、namespace bundle 或域名目录作为 production fallback；
- 在 ordinary JSON、日志、UI、E2E report、performance trace、error detail 或 DTO dump 中输出
  envelope、root key、private key、JWT、bearer token、raw `SecretRef` 或 Direct E2EE secret；
- 在 verify/open 失败后生成新 root key、回退明文或重跑旧 migration；
- 将删除 Keychain item 宣称为已经物理擦除 SQLite/attachments；
- 假设 App、CLI、daemon 可以读取同一个平台 secret。
