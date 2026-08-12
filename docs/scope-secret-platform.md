# AWiki Me Scope Secret Platform Provider

Status: active; provider and runtime Storage Scope cutover implemented

本文档记录 `StorageScopeId` 对应的 typed secret envelope、平台 provider 和原生
Keychain bridge。长期 schema 与生命周期仍以
[Storage Scope / Keychain / Identity Vault Contract](storage-scope-vault-contract.md)
为准。

## Locator 与 channel 隔离

| Build channel | Application identity | Provider locator |
|---|---|---|
| production/release | `ai.awiki.awikime` | service `ai.awiki.awikime.scope-secrets` |
| development/profile | `ai.awiki.awikime.dev` 或 `ai.awiki.awikime.dev.<suffix>` | service `ai.awiki.awikime.dev.scope-secrets` |
| E2E | 显式测试 state root | private file provider，不访问平台 item |

macOS Keychain item 使用不参与定位的友好显示标签：production/release 为
`AWiki Me secure storage`，development/profile 为
`AWiki Me secure storage (Development)`。所有 tenant 共用对应 channel 的显示标签；
同一 application channel 下的通用安全存储 ACL 也使用相同显示标签，避免它在 Scope
Vault 之前访问时显示另一套名称。
稳定 locator 仍仅由上述 service 与 `scope/<canonical-uuid-v4>` account 组成。新 item
创建时直接写入标签；旧 item 在成功读取后仅做 best-effort 标签元数据更新，更新失败不得
影响 vault 读取。

平台 account 永远是 `scope/<canonical-uuid-v4>`。Dart 和 macOS native bridge 都会
拒绝任意 service、非 canonical account、scope mismatch 和 unknown schema。域名、tenant
名称和 backend URL 不参与 locator。

## Typed API 与 envelope

`ScopeSecretRepository` 只暴露：

- `readExisting`；
- `createExclusive`；
- `compareAndReplace(expectedRevision)`；
- `delete`。

没有 `getOrCreate` 或 upsert。Envelope v1 严格验证 exact JSON shape、scope UUID、正整数
revision、canonical key UUID、`raw-256` algorithm 和 32-byte root。`toString`、exception 和
native error message 只输出稳定 code 或 `<redacted>`，不输出 envelope/value。

Dart/platform channel 在编码或 SDK open 边界会产生无法保证原地清零的短生命周期对象；provider
通过 defensive byte copy和最窄 API 限制暴露，但不宣称 GC language 可提供强制 zeroization。
runtime consumer取得 copy 后应尽快交给 im-core并覆盖可写 buffer，不能缓存或诊断输出。

## 平台实现

- macOS 使用独立 `ai.awiki.awikime/scope_secret` MethodChannel。Native 端只允许上述两个
  service，并按当前 bundle identity只允许对应的一个 service，在专用 serial queue 内完成
  read/create/CAS/delete。Production item 创建 ACL
  失败时直接 fail closed；不会复用普通 preferences 的 generic upsert 或 legacy fallback。
- iOS 使用 `first_unlock_this_device`、`synchronizable=false`，Debug/Profile 与 Release bundle
  identity 分离。
- Android v10 target 使用独立 `storageNamespace` 的 Keystore-backed storage，
  `resetOnError=false`、`migrateWithBackup=true`，Debug/Profile 使用 `.dev` application ID
  suffix。Scope secret 与普通 App key-value storage 必须使用不同 namespace，使 data、
  config marker、wrapped-key preferences 和 KeyStore alias 全部隔离。
- Web 和未支持平台返回 `scope_secret_platform_unsupported`，不降级到明文文件。

Flutter secure storage 在 iOS/Android 未提供系统级原子 CAS。当前实现使用进程级共享串行器，
其安全前提是一个 application identity 同时只有一个 AWiki Me writer process。多进程 writer
如未来成为需求，必须先增加平台原生 CAS/锁，不得把当前机制宣称为跨进程原子操作。macOS
同样通过单一 App writer 和 native serial queue消除进程内 TOCTOU。

### Android 9.2.4 到 10.x 的一次性迁移

旧版 Scope secret 使用 `awiki_me_scope_secrets` EncryptedSharedPreferences 和
`awiki_scope_` key prefix；普通 App state 使用 `FlutterSecureStorage` 与默认 prefix。
两者的数据文件不同，但旧 plugin 的 wrapped-key preferences/KeyStore alias 不完整隔离，
因此禁止让两个实例依次执行 v10 的通用自动算法迁移。

升级实现必须将两个 consumer 分别迁入固定且互不相同的 `storageNamespace`。每个精确 key
执行 target-first 双读；只有 source 成功解密、Scope envelope 校验通过、target 写入并
read-back 完全一致后，才采用 target。首个兼容版本不自动删除 source key，因为 plugin
普通写入的即时 read-back 不能替代跨进程/强杀后的持久性证据。迁移跨两个 consumer共用
同一进程级串行器。不删除旧 account/全局 key material，不扫描未知 key，不把解密失败当作 missing，也不使用
`resetOnError`、本地数据恢复或新 secret provision 兜底。

App 单元测试必须覆盖 App state 与 Scope secret 的不同 target namespace、冻结的 v9 source
options、target-first、成功迁移、read-back 不一致、source/target 异常、source 保留、并发串行、
exclusive create/CAS/delete。Android 真实升级门必须从 9.2.4 artifact 预置同一 scope root 与
非 secret session sentinel，覆盖安装候选后验证 DID/vault root/sentinel 保持一致，并在强杀
冷启动后复验；没有这项设备证据时只能标记 `UNVERIFIED`。

## E2E file provider

`E2eFileScopeSecretRepository` 只有在编译期显式设置 `AWIKI_E2E=true` 且测试提供
state root 时才可由 factory 选择；普通 production/development build 即使传入自定义
`appStateRoot` 也只能使用平台 secure store，不能降级到明文文件。它不会发现 production 路径。
目录权限固定 `0700`，每 scope envelope 和 lock file固定 `0600`，read 是 strict decode。
symlink、不安全权限、corrupt value 和 scope mismatch 都 fail closed。写入使用 exclusive create，
CAS 在文件锁内验证 revision 后 atomic replace。

## 错误与 release gate

稳定错误包括 `scope_secret_already_exists`、`scope_secret_revision_conflict`、
`scope_secret_access_denied`、`scope_secret_corrupt`、
`scope_secret_scope_mismatch`、`scope_secret_schema_unsupported`、
`scope_secret_provider_unavailable`、`scope_secret_platform_unsupported`。

Debug native smoke 覆盖 tamper rejection、exclusive create、跨 repository instance read、CAS、
stale CAS 和 delete；它不是 App process restart 或 production signing 证据。正式发布仍必须在
稳定 Team/signing 环境运行 `scripts/run_macos_production_scope_restart_gate.sh`，验证production
bundle三次签名/rebuild/process launch后仍读取同一item，并拒绝dev service和duplicate create。
