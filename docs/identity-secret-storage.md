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
- debug/profile：`ai.awiki.awikime.dev` 或受控的 `ai.awiki.awikime.dev.<suffix>`；
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

release/0710 Legacy identity 的显式升级由 Core 拥有完整 transaction deadline、pending
record 和重试分类。App 等待 `completed|retryRequired` typed status，不再叠加 20 秒通用
request timeout，因为 Dart timeout 不会取消 native upgrade，反而会在原事务仍执行时开放
第二次重试。失败页只投影 allowlisted diagnostic code，不展示 document、key、proof、token
或服务响应正文。

正式兼容基线固定为 AWiki Me `0.1.5+14`（App `c19a01a...`、Core `d7c853a...`）。
Core 原位升级保持同一 Storage Scope、local identity ID、DID root、Handle、Product DB、
attachments 和全部历史 Vault record；远端 vNext 文档的 managed fields 由 ANP builder
重新生成，旧 `#key-2/#key-3` 不再发布但继续作为历史解密材料保留。App 只等待 typed
upgrade 结果并在成功后重新读取 identity projection；失败时不得清除 active identity 指针。
Core pending record 固定保存同一组新设备密钥和目标文档；响应丢失后先按远端 DID 的真实状态
收敛，只有远端明确仍是 Legacy 时才保留设备密钥刷新 proof，App 不实现自己的重试分支。

冷启动恢复已持久化 active identity 时，会话服务必须先读取 Core 的 Legacy upgrade status；
未完成时先恢复或执行同一 Core upgrade transaction，只有返回 `completed` 后才允许
`switchIdentity` 和 JWT 刷新。升级完成后必须重新读取 identity projection，不能继续使用升级前
缺少 VNext device state 的旧快照。若 Core 返回 `retryRequired`，本次冷启动不激活身份，也不
清除 active identity 指针；Onboarding 保留本地凭证入口并继续使用 Core pending record 重试，
不得绕过升级直接认证而把服务端拒绝误报为普通 `permission_denied`。

## 5. Tenant 切换与本地状态

切换顺序是 stop realtime → 等待 active core operations → dispose client/core → close Product
SQLite → open new scope。旧 runtime 完全释放前不得打开新 runtime。Product DB、attachments、
active identity、im-core state/cache/temp 都从统一 `AwikiStorageScopeLayout` 获取或由 scope UUID
派生，不能自行拼接域名目录。

切换 active tenant 或修改 active tenant route 时先生成未持久化 registry candidate；只有旧
runtime 已释放且 candidate runtime 已成功打开后，才用 revision CAS 提交 registry。打开或提交
失败时销毁 candidate，并按旧 registry 重新打开原 scope，避免“UI 回滚但磁盘已切换”的半提交。

### 5.1 单个本地身份删除

“退出并删除本地凭证”不是网络 logout，也不是整个 Storage Scope 删除。App 先清除 active
identity 指针并从 UI session 脱离，再调用 Core 的离线 identity-retirement 事务；
realtime stop 与 runtime dispose 只做 best-effort 尾部清理，不得阻塞或改变本地删除结果，
也不得被通用 UI timeout 误报成网络超时。

登录后的设置页和未登录的本地身份选择器复用同一个 application 删除入口。身份选择器以
Core `identity_id` 为首选 selector，DID 只作为 Legacy host fallback；删除按钮与切换按钮
必须是独立语义和独立点击区域。未登录删除不创建临时 session，删除默认身份后也不自动登录
下一个身份；UI 只在 Core 成功返回并重新读取本地 registry 后移除对应条目。

会话列表、timeline 等 presentation Patch subscription 的取消同样不是 identity-retirement
事务前置条件。App 可以立即清空内存 UI 投影并在后台取消 subscription，但必须随即进入 Core
删除；不得等待一个 idle native stream 的 `cancel()` 才开始删除身份。Core 删除成功后再刷新
本地身份列表，删除失败则以 Core 事务结果为权威，不能用 presentation cleanup 的完成与否
推断凭证是否仍存在。

Core 负责 registry/default pointer tombstone、身份目录和 exact `identity_id` Vault records
的顺序、一致性与启动恢复。App 不枚举或删除 Vault records。中途崩溃时 Core open 继续未完成
阶段；已完成的 identity-ID tombstone 还会清理由删除开始前已进入执行、但稍后才写回的凭证。
删除一个身份不会删除 scope root key、Product SQLite、attachments 或同 scope 的其他身份。

## 6. E2E 与发布 Gate

Native smoke 覆盖显式 provision、native `VaultRequired` open、同一进程重新创建 runtime 后读取同一
root，以及删除 key 后 openExisting 不重建。Debug smoke 不是 production Team-signing 或真实 App
进程重启证据；`scripts/run_macos_production_scope_restart_gate.sh` 是独立 release Gate：每个阶段重新
构建并用同一稳定 identity签名production bundle，分别启动 provision/reopen/cleanup App进程，校验
Team/bundle identity、dev/prod service隔离、revision 1持续存在和duplicate create拒绝。Gate 会在
三个阶段前从 sibling `awiki-cli-rs2`（或显式 `AWIKI_IM_CORE_REPO_DIR`）只构建一次 universal macOS
Core，校验 arm64/x86_64，刷新 CocoaPods 并清理旧 Release XCFramework 中间目录；原生依赖准备
失败必须与 Keychain 行为失败分开报告。

相关测试：

- `tests/unit/data/storage/`
- `tests/unit/data/im_core/awiki_im_core_secret_storage_test.dart`
- `tests/unit/data/im_core/awiki_im_core_runtime_test.dart`
- `tests/unit/data/tenant/app_tenant_store_test.dart`
- `tests/unit/app_runtime_archive_actions_test.dart`
- `IDENTITY-DELETE-E2E-001`：真实 native Core、idle conversation Patch、删除凭证和独立
  Flutter 冷启动不恢复身份。
- `LEGACY-UPGRADE-E2E-001`：使用正式 `0.1.5+14` 与候选包执行覆盖安装，验证同 DID/root、
  Handle、local identity ID、Product DB、消息/联系人/群组/未读/附件、历史 Vault material 和
  response-loss 重试均收敛到同一设备；该发布级双 artifact 用例不进入日常 unit/smoke。
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
