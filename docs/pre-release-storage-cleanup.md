# AWiki Me 预发布 Storage Cleanup Runbook

Status: active；仅用于首发前开发数据

`release/0707` 与 `release/0710` 均未上线。正式 App 不读取旧
`awiki-me/environments/<namespace>`、split Keychain items 或 namespace bundle。本工具只帮助
开发者盘点、归档或显式删除这些预发布残留，不属于 production migration。

## 安全边界

- 默认是 dry-run；没有确认词不会修改文件或 Keychain。
- 必须显式提供 App support root，工具拒绝 `/`、HOME 和空路径。
- 只处理 `<support-root>/awiki-me/environments`，不读取
  `<support-root>/awiki-me/storage-scopes`。
- Keychain 只检查两个旧 service 下、由已知 namespace 派生的三个旧 account suffix：
  `root_key_b64`、`device_id`、`secrets_v1`。
- `security find-generic-password` 不带 `-g`，工具不会读取、打印或写入 Keychain value。
- archive 只移动旧目录并保存不含 value 的 account inventory；Keychain item原样保留。
- delete 必须使用不同的强确认词；不会匹配新 `scope/<uuid>` account。

## Dry-run

先确认当前 App support root。macOS 常见位置在
`~/Library/Application Support/<bundle-id>`，但必须以当前构建实际容器为准，不要猜测后直接删除。

```bash
cd awiki-me
dart run scripts/pre_release_storage_cleanup.dart \
  --support-root "/absolute/app-support-root"
```

如果旧目录已删除但还知道其他 namespace，可重复传入：

```bash
dart run scripts/pre_release_storage_cleanup.dart \
  --support-root "/absolute/app-support-root" \
  --namespace awiki.ai \
  --namespace tenant-default
```

输出只包含路径、namespace、Keychain service/account 和存在状态，不包含 secret value。

## Archive（推荐）

```bash
dart run scripts/pre_release_storage_cleanup.dart \
  --support-root "/absolute/app-support-root" \
  --archive \
  --confirm ARCHIVE_PRE_RELEASE_STORAGE
```

旧目录移动到 `awiki-me/pre-release-archive/`。Keychain item不会删除，inventory manifest权限为
`0600`。确认新 Storage Scope build稳定后，再决定是否显式删除。

## Explicit delete

```bash
dart run scripts/pre_release_storage_cleanup.dart \
  --support-root "/absolute/app-support-root" \
  --delete \
  --confirm DELETE_PRE_RELEASE_STORAGE
```

删除是不可逆操作。它只处理本次 dry-run inventory 中的旧 locator；新 registry、
`storage-scopes/<uuid>` 和 `scope/<uuid>` 不在匹配范围内。不要把本工具加入 App startup、安装器或
自动升级流程。
