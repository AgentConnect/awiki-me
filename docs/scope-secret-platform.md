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
- Android 使用 Keystore-backed encrypted shared preferences，`resetOnError=false`，Debug/
  Profile 使用 `.dev` application ID suffix。
- Web 和未支持平台返回 `scope_secret_platform_unsupported`，不降级到明文文件。

Flutter secure storage 在 iOS/Android 未提供系统级原子 CAS。当前实现使用进程级共享串行器，
其安全前提是一个 application identity 同时只有一个 AWiki Me writer process。多进程 writer
如未来成为需求，必须先增加平台原生 CAS/锁，不得把当前机制宣称为跨进程原子操作。macOS
同样通过单一 App writer 和 native serial queue消除进程内 TOCTOU。

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
