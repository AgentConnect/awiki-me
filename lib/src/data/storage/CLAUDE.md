# `lib/src/data/storage/`

Storage Scope control plane：负责不可变 scope layout、manifest、provision/recovery
状态机和 `ScopeSecretRepository` port。这里不得根据域名、display name 或 tenant label
派生路径，不得记录或输出 secret material。平台 secure-storage adapter 位于 Step 03，
runtime consumer cutover 位于 Step 04。
