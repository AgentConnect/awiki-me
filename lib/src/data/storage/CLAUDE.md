# `lib/src/data/storage/`

Storage Scope control plane：负责不可变 scope layout、manifest、provision/recovery
状态机、strict versioned envelope、`ScopeSecretRepository` port、平台 provider 和显式
E2E private-file adapter。这里不得根据域名、display name 或 tenant label派生路径，不得
记录或输出 secret material。Production/Development service 与 application identity 必须
隔离；E2E 只能显式选择 0600 file provider。Production provider 不得调用普通
`SecureAppKeyValueStore`、legacy migration 或 fallback。所有runtime consumer必须从
`AwikiStorageScopeLayout`取路径，runtime secret只允许`openExisting`。
