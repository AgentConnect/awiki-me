# AWiki Me Storage Scope / Keychain / Identity Vault Contract

Status: active; scope control plane, typed platform provider, and runtime cutover implemented
Authority: authoritative for AWiki Me tenant-local storage identity and host vault context

本文档冻结 AWiki Me 首个正式版本的本地 tenant、Storage Scope、平台
secure storage 和 im-core Identity Vault host context 契约。它定义长期稳定的
locator 和生命周期，不描述服务端 tenant/admission，也不改变 im-core 内部 vault
record 密码格式。

`release/0710` 已上线；其 Storage Scope locator、Keychain account 和 Vault context
保持不变。后续版本必须在同一 scope 内通过 Core 的显式 local-state upgrade gate
迁移 schema 27，不能把 0710 SQLite 当作不兼容数据归档或要求用户重新登录。

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
- tenant switch必须停止realtime、取消scope-owned work、等待active operations、flush/close
  SQLite，旧runtime完整dispose后才能打开新scope。
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

## 11. Clean cut 与未来演进

Production不读取或迁移：

- `awiki-me/environments/<namespace>`；
- `awiki.ai`/`tenant-default` locator；
- `.root_key_b64`/`.device_id` split items；
- `<namespace>.secrets_v1` bundle。

预发布数据只由developer-only dry-run + explicit archive/reset工具处理。未来registry、
manifest、layout、envelope、SQLite各自版本化，并且只能在同scope/account内原位迁移。
Root rotation使用同account内的CAS/journal/reseal/verify流程；backup使用单独加密recovery
package；二者都不得改变locator。

## 12. Security Review checklist

- [ ] mutable tenant字段无法影响path/account/context。
- [ ] runtime没有root-key create能力。
- [ ] existing scope + missing/denied/corrupt secret一律fail closed。
- [ ] registry/manifest/envelope scope ID交叉校验。
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
