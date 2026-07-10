# AWiki Me Identity Secret Storage

Status: active  
Authority: authoritative for AWiki Me App-side identity vault integration

本文档记录 AWiki Me 当前如何接入 Flutter SDK / Rust `im-core` 的 identity
SecretVault，以及 App 代码必须遵守的本地 secret 边界。SDK、CLI 和 daemon 的完整端侧方案见
`awiki-cli-rs2/docs/architecture/identity-secret-storage.md`。

## 1. 当前结论

AWiki Me 不直接读写 DID 私钥、JWT 文件、vault record 或 daemon subkey package
文件。App 只负责提供 no-prompt root key 和稳定 host context，然后用
`VaultRequired` 打开 Dart SDK：

```text
AWiki Me
  -> StoredAwikiImCoreVaultSecretProvider
    -> one namespace-scoped secret bundle
      -> AwikiImCoreOpenOptions.vaultRequired
        -> packages/awiki_im_core
          -> im-core identity SecretVault
```

`im-core` 拥有 DID 私钥、E2EE static key material、auth/JWT state、daemon
subkey package persistence 和 Direct E2EE session/prekey local state 的加密落盘。App
层只做 root key provider、身份激活前校验和错误处理。

## 2. Root Key Provider

生产和普通 custom state root 使用 `SecureAppKeyValueStore`，底层为平台 secure storage；
macOS 通过 App 的 native Keychain bridge 写入一个 namespace-scoped item。App 只保存打开
vault 所需的最小 host secret/context：

- `awiki_me.im_core.identity_vault.<namespace>.secrets_v1`

`secrets_v1` 的值是一个结构化 JSON bundle：

```json
{
  "schema": 1,
  "root_key_b64": "...",
  "device_id": "app-device-..."
}
```

root key 是 32-byte 随机值，只在打开 SDK 时作为 `DeviceVaultRootKey` 传给 Dart SDK。它不能进入
App ordinary JSON state、日志、UI、E2E report、generated DTO dump 或测试 fixture。
device id 是稳定 host context，和 root key 一起放入同一个 bundle，避免 macOS 为同一
namespace 的多个 Keychain item 分别弹出授权。

当前版本不迁移、不读取、也不删除旧的拆分 key：

- `awiki_me.im_core.identity_vault.<namespace>.root_key_b64`
- `awiki_me.im_core.identity_vault.<namespace>.device_id`

这是一次不向后兼容的本地 vault secret 存储模型调整。旧本地 vault 数据不会被新版本自动恢复；
需要重新登录、重新注册或重新导入身份。

只有显式 E2E mode，也就是设置 `AWIKI_E2E_APP_STATE_ROOT` 时，App 才使用
`awiki_me_im_core_vault.json` 私有 file test provider。这个 JSON 可能包含 `secrets_v1`
bundle 以及其中的 base64 root key，必须留在本地并保持 untracked。

普通 `appStateRoot` override 不会把 root key 移到 JSON；它仍使用平台 secure
storage provider。

## 3. Vault Context

App state namespace 决定 vault 目录、workspace id 和 device id：

```text
<app support>/im-core/<namespace>/identity-vault
vaultWorkspaceId = awiki-me-<namespace>
deviceId = app-device-<stable-random>
```

`AwikiImCoreRuntime.open()` 的顺序：

1. 创建并验证 App / im-core 路径。
2. 从 `StoredAwikiImCoreVaultSecretProvider` 读取或创建单个 `secrets_v1` bundle，并从
   bundle 获取 root key 和 device id。
3. 用 `AwikiImCoreOpenOptions.vaultRequired(...)` 打开 `AwikiImCore`。

如果 bundle 损坏、root key 长度不对，或 strict file provider 已存在但缺少 `secrets_v1`，
App 必须 fail closed，不重新生成一个新 root key 覆盖已有状态。

## 4. 身份激活 Gate

App 在切换 active identity 前必须先验证 vault：

```text
identityVaultStatus
  -> migrateIdentityVault when legacy metadata is absent
  -> verifyIdentityVault
  -> switchIdentity
  -> ensureSession
```

当前实现入口：

- `lib/src/data/im_core/awiki_im_core_runtime.dart`
- `lib/src/application/app_session_service.dart`

重要事项：

- `identityVaultStatus` 显示已有 vault metadata 但 metadata 无法选择或验证时，App
  fail closed。
- App 不能先切换 active session，再补做 vault verify。
- App 不能在 verify 失败后用新 root key 重新 seal 旧明文。

## 5. Daemon Subkey Bootstrap 例外

当前 App bootstrap path 仍可能收到 daemon subkey private key plaintext DTO，例如
`user_subkey_package.private_key_pem`。这是临时传输兼容例外，不代表本地持久化可以明文：

- 传输层后续应改为端到端加密 bootstrap envelope。
- 即使传输暂时明文，daemon 接收后的持久化也必须用 daemon SecretVault 的 vault ref
  存储，不能写明文 DB 字段。
- App 侧日志、UI、E2E report 和 debug dump 不能输出该 DTO 中的 private key。

## 6. E2E 和测试状态

E2E runner 设置 `AWIKI_E2E_APP_STATE_ROOT` 后，Flutter shim 使用
`awiki_me_im_core_vault.json` 保存 App-local `secrets_v1` bundle。该文件在 E2E
状态目录下，必须保持本地私有。

相关测试：

- `tests/unit/bootstrap_test.dart`
- `tests/unit/data/im_core/awiki_im_core_secret_storage_test.dart`
- `tests/unit/data/im_core/awiki_im_core_runtime_test.dart`
- `tests/unit/application/app_session_service_test.dart`
- `tests/e2e/flutter/native/im_core_open_smoke_test.dart`

涉及 App identity vault 的变更应至少运行：

```bash
dart analyze
dart run tests/unit/runner.dart
dart run tests/e2e/runner.dart --case full
```

## 7. 安全红线

AWiki Me 代码不得：

- 直接读取 `private.key`、`key-*-private.pem`、`auth.json`、vault record 或
  daemon subkey package 文件。
- 在 App ordinary JSON state 中保存 identity vault root key。
- 在日志、UI、E2E report、performance trace、error detail 或 generated DTO dump 中输出
  root key、private key、JWT、bearer token、raw `SecretRef`、Direct E2EE session/prekey
  secret 或 daemon subkey plaintext DTO。
- 假设 CLI、daemon 和 App 能读取同一个系统 keychain item。App、CLI、daemon 是不同宿主进程，
  必须各自有自己的 no-prompt root key provider。

允许 App 输出的诊断只包括 redacted 状态，例如 vault 是否可用、metadata 是否存在/已验证、
warning code、missing item、workspace/device context 和测试 provider 类型。
