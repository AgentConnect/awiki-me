# AWiki Me Storage Scope / Keychain / Identity Vault Contract

Status: active; scope control plane, typed platform provider, and runtime cutover implemented
Authority: authoritative for AWiki Me tenant-local storage identity and host vault context

本文档冻结 AWiki Me 首个正式版本的本地 tenant、Storage Scope、平台
secure storage 和 im-core Identity Vault host context 契约。它定义长期稳定的
locator 和生命周期，不描述服务端 tenant/admission，也不改变 im-core 内部 vault
record 密码格式。

`release/0710` 的 UUID Storage Scope 实现已经成为 production 升级基线。后续版本必须
原位打开已有 registry、manifest、scope data 和 platform secret，不得因编译期默认域名、
租户显示名称、后端地址或构建版本变化而重新创建 scope。旧 `awiki.ai` /
`tenant-default` namespace、旧 split keys 和 namespace bundle 只属于预发布开发数据，
不进入 production 启动或恢复链路，也不得在普通启动时自动删除。
同一 scope 内的 release/0710 schema 27 数据必须通过 Core 显式 local-state upgrade gate
升级，不能被当作不兼容数据归档，也不能要求用户重新登录。

## 1. Ownership 与边界

```text
Tenant Profile（App 业务连接配置）
  -> Storage Scope（App 本机数据与 secret 生命周期）
    -> platform secure storage（host root key）
      -> AwikiImCoreOpenOptions.vaultRequired
        -> im-core SecretVault（record crypto / verify / private material）
```

- AWiki Me 拥有 tenant profile、scope registry、scope manifest、平台 secret provider、
  路径编排和 runtime lifecycle。
- `awiki-cli-rs2/crates/im-core` 拥有 Identity Vault record、AAD、seal/open、status、
  migration/verification 和私钥/JWT/E2EE secret 正确性。
- App 不读取 vault record、private PEM、JWT、完整 `SecretRef` 或 ciphertext。
- App、CLI、daemon 是不同 host，不共享 root key、Keychain account 或本地 scope。
- 删除单个本地身份由 im-core identity-retirement 事务负责；它不删除 scope
  Keychain item，也不等价于删除整个 Storage Scope。App 只负责先脱离 active session，
  realtime/runtime teardown 不能成为该离线事务的网络前置条件。
- 每个有效 scope/account/device binding 默认参加普通消息与账号状态同步，不按本地 scope、
  账号或设备做产品灰度；raw cursor、recovery 和 mutation outbox 仍只属于该 scope 的 Core
  SQLite。测试 operator allowlist 不得写入 scope registry 或业务 cache。

## 2. 不可变 ID

| ID | Owner | 生成 | 可变性 | 用途 |
|---|---|---|---|---|
| `tenant_profile_id` | App registry | canonical UUIDv4 | 永久不变 | 本机连接配置主键 |
| `storage_scope_id` | App scope control plane | canonical UUIDv4 | 永久不变 | 唯一数据/secret locator |
| `remote_realm_id` | server capability，可为空 | 服务端 | 服务端定义 | route update 校验，不是本地 locator |
| `vault_workspace_id` | App host contract | scope ID确定性派生 | 永久不变 | im-core vault context |
| `vault_context_device_id` | App host contract | scope ID确定性派生 | 永久不变 | im-core vault context |

首发约束：一个 active tenant profile恰好绑定一个storage scope；一个scope最多由
一个tenant profile拥有。两者仍分开建模，使orphan recovery、archive、显式import
和scope lifecycle无需改变路径或Keychain locator。

以下字段永远不得参与path/account/context派生：

- display name；
- backend URL；
- DID host/domain；
- `awiki.ai` / `awiki.info`；
- `default` / `tenant-default`；
- server-facing tenant label。

## 3. Registry schema

全局registry固定在：

```text
awiki-me/control/tenant-registry.json
```

Schema v1：

```json
{
  "schema_version": 1,
  "revision": 1,
  "active_tenant_profile_id": "<uuid>",
  "tenants": [
    {
      "tenant_profile_id": "<uuid>",
      "storage_scope_id": "<uuid>",
      "kind": "built_in_awiki|custom",
      "display_name": "AWiki",
      "backend_base_url": "https://awiki.ai",
      "did_host": "awiki.ai",
      "remote_realm_id": null,
      "lifecycle": "active|archived",
      "created_at": "<RFC3339>",
      "updated_at": "<RFC3339>"
    }
  ]
}
```

要求：

- UUID必须是lowercase hyphenated canonical UUIDv4；
- `revision`防止stale writer覆盖；
- 使用temp file、flush/fsync和same-directory atomic rename；
- active scope不可重复，tenant/profile与scope映射必须唯一；
- registry不得包含root key、private key、JWT、vault record或完整`SecretRef`；
- unknown newer schema必须fail closed，旧App不得写入。

## 4. Scope layout 与 manifest

Application Support：

```text
awiki-me/
├── control/tenant-registry.json
└── storage-scopes/
    └── <storage_scope_id>/
        ├── scope-manifest.json
        ├── im-core/
        │   ├── identities/
        │   ├── identity-vault/
        │   └── state/im_core.sqlite
        ├── product/awiki_me_product_store.db
        └── attachments/
```

Cache/temp：

```text
<cache-root>/awiki-me/storage-scopes/<storage_scope_id>/im-core/
<temp-root>/awiki-me/storage-scopes/<storage_scope_id>/im-core/
```

`scope-manifest.json` v1：

```json
{
  "schema_version": 1,
  "layout_version": 1,
  "storage_scope_id": "<uuid>",
  "owner_tenant_profile_id": "<uuid>",
  "lifecycle": "provisioning|ready|deleting|blocked",
  "realm_binding": {
    "remote_realm_id": null,
    "did_host_at_creation": "awiki.ai"
  },
  "vault_context_version": 1,
  "secret_envelope_schema": 1,
  "created_at": "<RFC3339>",
  "updated_at": "<RFC3339>"
}
```

顶层`storage-scopes/<uuid>`一经发布永久不改名。未来layout或SQLite升级只能在同一
scope root内原位完成。所有tenant-scoped path必须由单一`AwikiStorageScopeLayout`
或等价typed layout提供，业务模块不得自行拼接domain/name路径。
Layout在创建和打开时必须拒绝support/cache/temp trusted root以下任一scope路径祖先的
symlink，不能只检查最终scope目录；目录创建仍需保持exclusive/contained语义。

Manifest只保存非secret不变量。Keychain service/account不能从manifest自由读取，
必须由编译期channel配置和scope ID派生，避免被篡改后指向其他secret item。

### 4.1 Product local DB v4 与账号绑定

`product/awiki_me_product_store.db` 的 schema v4 是 additive upgrade。它保留 v3 的
conversation overlay、draft、UI preference 和 `local_agent_states`，并一次建立：

```text
account_domain_sync_state
account_agent_inventory_snapshot
account_agent_status_snapshot
account_profile_snapshot
account_device_registry_snapshot
```

这些表只保存 User Service 权威账号域的可丢弃展示 cache，不保存 message、conversation、
group、read-state、sync cursor、event receipt、mutation outbox、JWT 或密钥。消息可靠状态仍由
im-core SQLite 独占。

App 激活或切换身份后必须从当前 `AwikiImClient.activeSyncAccountBinding()` 取得 typed
`ActiveSyncAccountBinding`，并验证：

```text
ownerIdentityId == 当前 IdentitySummary.id
currentDid == 当前 IdentitySummary.did
accountId 非空
protocolDeviceId 非空且不等于保留兼容值 default
identityGeneration / deviceAuthGeneration 为 canonical positive decimal string（大于 0、无前导零）
```

该 binding 不可由 Handle、DID、JWT payload、`vault_context_device_id`、Storage Scope UUID 或
App installation UUID 推断。Core 返回 unavailable、字段不一致、Protocol Device ID 为
`default`，或 generation 不是 canonical positive decimal 时，session activation fail closed，
不能写 active-session pointer 或账号域 cache。`SessionIdentity` 和 `AppSession` 只保留这一
typed binding 的安全字段；JWT 仍只用于现有认证兼容面，不能成为账号主键来源。

每个账号域以 `(owner_identity_id, domain)` 保存 version，并同时保存稳定 `account_id`。
同一 `owner_identity_id` 已出现其他 `account_id` 时，SQLite 和 InMemory store 都必须拒绝读写。
四个 typed replace API 在单一事务中清旧 rows、写完整 snapshot并推进 version；空 snapshot
同样清旧并推进。Agent inventory topology 和 latest status 独立替换，status 不能改写
`active_state`。Product DB 中的 `domain_version`、`inventory_version`、
`agent_status_version`、`profile_version`、`registry_version` 和 Registry snapshot
`auth_generation` 使用任意精度 canonical non-negative decimal TEXT，允许唯一的零值表示
`0`，不收窄为 SQLite INTEGER 或 Dart number。这些 Product cache 字段不得与 Session
binding 中必须大于 0 的 identity/device generation 混用。

旧 `owner_did` Agent cache 只有在 stable binding 和明确旧 owner DID 同时提供后才允许
copy-on-read 到 inventory version `0`；旧表不在 v4 migration 中删除。数据库从 v1/v2/v3
升级到 v4 前，未升级连接必须先通过 `VACUUM INTO` 生成并用 `PRAGMA integrity_check` 验证：

```text
product/schema-upgrades/awiki_me_product_store.pre-v4.sqlite
```

事务失败时 snapshot rows 与 domain version 都保持原值；不能留下半个账号域快照。

### 4.2 多设备消息同步的本地所有权

普通消息多设备同步沿用同一个 Storage Scope，但不会把可靠状态下放到 Product DB 或
Flutter provider：

```text
ActiveSyncAccountBinding.ownerIdentityId
  -> im-core SQLite owner partition
    -> account/replica sync state、可靠 cursor、event receipt、recovery state
    -> canonical message/conversation/read projection
      -> Core committed patch
        -> AWiki Me bounded in-memory window
```

- `owner_identity_id` 是 Core 本地消息、会话、已读和同步状态的稳定分区键；当前 DID、
  `account_id`、`protocol_device_id` 和 generation 只作为经过验证的绑定与 fencing 字段。
- 账号流的 raw scan cursor、visible cursor、replica bootstrap/recovery 状态、幂等 receipt
  和 mutation outbox 只存在 im-core SQLite。AWiki Me 不读取、保存或推进这些 cursor，
  `awiki_me_product_store.db` 也不得复制它们。
- AWiki Me 的会话列表和当前消息窗口只是 Core canonical projection 的有界内存投影。
  App session 激活必须先建立 committed-patch subscription，再完成当前 session generation
  的一次有界本地 seed，之后才能发起首次可靠同步。同一 generation 的后续 realtime hint、
  WebSocket 重连和前台对账复用该订阅，不再在每次同步后全量刷新会话或执行 20×50
  history prewarm。
- patch generation、session generation、`owner_identity_id`、`account_id`、
  `device_auth_generation` 或当前 DID 不匹配时，App 必须拒绝旧 patch 和旧同步结果；
  gap、stream rebuild 或显式 repair 只能重新执行一次有界 seed，不能清空 Core 权威库。

新设备和已有设备的恢复语义不同：

- 新 replica 使用 tail-only bootstrap，从服务端当前流尾开始，不导入加入前的普通消息。
- 已有 replica 出现 retention gap、epoch mismatch 或长期离线时，由 Core 驱动 compact
  recovery；服务端按自己的时间同时限制为最近 48 小时且最多 500 条普通逻辑消息。
- 500 条只统计普通逻辑消息，不统计状态事件或 E2EE/MLS 数据。Snapshot 是 merge：
  窗口外缺失不表示删除，也不得删除设备本地已经存在的更早普通消息。
- Agent Inventory、Agent Status、Profile 和 Device Registry 是独立的版本化当前快照，
  不受普通消息 48h/500 窗口限制，仍只缓存于 Product DB 对应账号域表。

WebSocket 只携带 dirty-domain/wake-up hint；即使提示丢失，startup、前台恢复、重连或周期
对账仍通过 HTTP 可靠拉取并由 Core 原子提交事实与 cursor。移动 Push 在当前版本明确延期，
将来启用也只能负责唤醒，不能携带消息事实或替代 HTTP/Core commit。

产品安全诊断只允许暴露 typed `lastSuccessAt`、sync/recovery mode、
`pendingMutationCount`、dirty domains、retry state 和可选 `nextRetryAt`。普通 state、
日志和 UI 不得包含 raw cursor/epoch、完整 account/device ID、recovery token、消息正文、
payload 或认证材料。

当前普通同步明确不包含 Direct E2EE、Group MLS、密钥、密文、加密历史，也不定义普通消息
编辑、撤回、删除或消息 tombstone。以上数据不得为了“统一存储”进入普通 sync state、
Product DB cache 或 App diagnostics。

## 5. Keychain / platform secret locator

Production locator：

```text
service = ai.awiki.awikime.scope-secrets
account = scope/<canonical_storage_scope_id>
```

Account不包含schema version、domain或tenant name；value schema升级不改变locator。
一个scope只有一个item，首发envelope如下：

```json
{
  "schema_version": 1,
  "scope_id": "<uuid>",
  "revision": 1,
  "active_secrets": {
    "identity_vault_root": {
      "key_id": "<uuid>",
      "key_version": 1,
      "algorithm": "raw-256",
      "material_b64": "<32-byte-secret>"
    }
  }
}
```

- `scope_id`必须与request、registry和manifest一致；
- root key严格为32 bytes；
- `revision`用于compare-and-swap；
- `key_id`/`key_version`为未来rotation journal预留，不改变account；
- `active_secrets`未来可增加database wrapping key，但当前只实现identity root；
- envelope、root key和material字段不得进入logs、UI、errors、reports或fixtures。

平台secret API必须是窄口：

```text
readExisting(scopeId)
createExclusive(scopeId, envelope)
compareAndReplace(scopeId, expectedRevision, envelope)
delete(scopeId)
```

禁止production `getOrCreate`和unconditional upsert。`createExclusive`遇到已有item必须
返回`already_exists`，不得覆盖。plugin missing、ACL denied、decode error不得切换到
另一backend或生成新key。

平台实现、安全选项和测试边界见
[Scope Secret Platform Provider](scope-secret-platform.md)。

## 6. Vault context v1

```text
workspace_id = awiki-me.scope.v1.<scope_uuid>
device_id    = awiki-me.scope-device.v1.<scope_uuid>
vault_dir    = storage-scopes/<scope_uuid>/im-core/identity-vault
```

这里的`device_id`是im-core vault host context，不是全局物理设备ID。规则发布后永久
冻结。如果将来需要installation/device identity，必须新增独立字段，不能替换已经进入
vault metadata/AAD的context。

## 7. Provision 与 open 必须分离

### 7.1 Provision

只有显式创建tenant/scope流程可以生成root key：

```text
registry lock
  -> allocate profile/scope UUIDs
  -> exclusive create scope root
  -> write manifest(provisioning)
  -> createExclusive platform secret
  -> initialize/open empty VaultRequired im-core scope
  -> validate path/context/envelope
  -> write manifest(ready)
  -> atomically commit registry mapping
```

目录和manifest先创建，使Keychain写入后的crash仍可枚举恢复。只有可证明没有identity、
core DB或业务数据的provisioning scope可以rollback。

### 7.2 Open existing

Runtime启动只能：

```text
registry lookup
  -> ready manifest validation
  -> readExisting platform secret
  -> envelope scope/schema/key validation
  -> derive v1 context
  -> inspect Core local-state schema（只读）
  -> 若为0710 schema 27：online backup + shadow migration + conservation validation + cutover
  -> VaultRequired open
  -> verify existing identities
```

任何步骤失败都不得创建key、切换directory、猜测domain scope或回退plaintext。
“scope存在但key缺失”是blocked/unrecoverable local vault，不是fresh scope。
Core升级失败时保持backup/journal并停留在启动错误页；允许重试，但不得清库、触发OTP/
Handle恢复或在升级完成前创建conversation/profile/product业务Store。

## 8. Route、switch 与删除规则

- display name可原位修改，不改变scope。
- backend URL只有在server证明相同`remote_realm_id`/service identity时可原位修改。
- server尚无stable realm ID时，scope有数据后禁止修改backend/DID host。
- DID host/realm变化默认创建新tenant profile和scope。
- tenant switch必须先推进 App active session generation，使旧 owner 的 sync、timeline、patch、read、send completion 和 presentation cache 立即失效；再停止 realtime、取消 scope-owned work、等待 active operations、flush/close SQLite，旧 runtime 完整 dispose 后才能打开新 scope。新 identity 只能在旧 runtime 释放后启动；同一 identity 的 JWT/profile refresh 不推进 generation。
- archive默认保留scope和key。
- explicit local-data deletion进入`deleting`，停止runtime、删除platform secret和scope files；
  失败保持可重试的`deleting/blocked`。

删除root key只完成Identity Vault secret的crypto-erasure，不代表SQLite/Product/attachment
已经删除，也不承诺SSD物理secure erase。

## 9. Channel 隔离

| Channel | Data root | Secret provider |
|---|---|---|
| production | production application container | production platform secure store |
| development/profile | 独立dev application identity和data root | 独立dev secure-store service |
| E2E | `AWIKI_E2E_APP_STATE_ROOT` | private file provider，0600/strict read |

E2E和dev不得读写production item。macOS ACL必须最终由stable Team + bundle designated
requirement验证；iOS使用device-only/non-sync accessibility；Android使用Keystore-backed
provider。Web在安全backend获批前保持vault unavailable。

## 10. 错误与诊断

App/SDK mapping至少区分：

```text
scope_registry_missing
scope_registry_corrupt
scope_manifest_missing
scope_manifest_mismatch
scope_not_ready
scope_schema_unsupported
vault_key_missing
vault_key_access_denied
vault_key_bundle_corrupt
vault_key_scope_mismatch
vault_context_mismatch
vault_metadata_unverified
vault_verification_failed
orphan_scope_detected
```

只允许记录code、stage、duration和scope ID短hash。不得解析Rust human error string来决定
安全行为。

## 11. Production 升级与未来演进

已有 `tenant-registry.json` 是启动时的唯一租户与 scope authority。编译期默认租户配置只
允许在 registry 不存在时参与首次 provision；已有 registry 存在时不得比较、覆盖或重建
其中的 profile/scope。覆盖安装新 App 只能替换应用 bundle，必须继续使用相同 production
application identity、data root、Keychain service/account 和 Storage Scope ID。

Registry、manifest、layout、envelope 或 SQLite 的未来升级必须满足：

- 在原 scope/account 内进行，不通过分配新 scope 模拟迁移；
- 版本化、幂等，并在提交前完成完整校验；
- 失败时保留原数据和原 secret，不得删除后重建；
- unknown newer schema fail closed，旧版本不得回写；
- 自动清理与数据升级分离，普通启动和覆盖安装不删除 legacy path。

Production不读取或迁移：

- `awiki-me/environments/<namespace>`；
- `awiki.ai`/`tenant-default` locator；
- `.root_key_b64`/`.device_id` split items；
- `<namespace>.secrets_v1` bundle。

预发布数据只由developer-only dry-run + explicit archive/reset工具处理。Root rotation
使用同account内的CAS/journal/reseal/verify流程；backup使用单独加密recovery package；
二者都不得改变locator。

## 12. Security Review checklist

- [ ] mutable tenant字段无法影响path/account/context。
- [ ] runtime没有root-key create能力。
- [ ] existing scope + missing/denied/corrupt secret一律fail closed。
- [ ] existing registry忽略新的编译期默认租户配置并保留原profile/scope映射。
- [ ] registry/manifest/envelope scope ID交叉校验。
- [ ] production bundle identity、data root和Keychain locator跨覆盖安装保持稳定。
- [ ] production/dev/E2E隔离。
- [ ] App/CLI/daemon secrets不共享。
- [ ] root key/private key/JWT/SecretRef不进入ordinary state和diagnostics。
- [ ] delete、backup、rotation、database encryption边界无过度承诺。

## 13. 相关权威文档

- [AWiki Me identity integration](identity-secret-storage.md)
- [AWiki Me README](../README.md)
- `awiki-cli-rs2/docs/architecture/identity-secret-storage.md`
- `awiki-harness/features/identity-secret-vault.md`
- `awiki-harness/features/multi-tenant-federated-identity.md`
