# Conversation Presentation Ownership

本文档记录 AWiki Me 会话列表 presentation projection 的当前 owner 边界。目标是避免 `awiki-me` 与 Rust `im-core` 对同一展示事实双写，确保 snapshot、patch、overlay、Agent lifecycle 和 group display 的职责可以被测试和 review。

## 1. 当前结论

`im-core` / Flutter SDK 负责会话基础事实，`awiki-me` 负责产品展示事实和组合逻辑。

短期不把 `hidden`、`pinned`、`muted`、`customTitle`、`avatarSeed`、Agent lifecycle 或 App domain DTO 加入 `ConversationSnapshotItem` / `DartConversationSnapshotItem`。这些字段继续由 `awiki-me` 的 `ProductLocalStore`、`ConversationService` 和 provider 层组合出来。

## 2. Owner 边界

| 数据或行为 | 当前 owner | 写入入口 | 读取 / 组合入口 |
|---|---|---|---|
| message、thread、group、conversation base projection | Rust `im-core` SQLite / runtime store | Flutter SDK message/group/sync/read-state API | `ConversationCorePort`、`AwikiImCoreConversationAdapter` |
| conversation snapshot cache | Rust `im-core` redb snapshot cache | `im-core` 从 committed projection 保存 | `ConversationCorePort.loadConversationSnapshot` |
| conversation patch stream | Rust `im-core` runtime store | committed sync/local write invalidation | `ConversationCorePort.watchConversationPatches` |
| unread count、unread mention、read-state 展示事实 | Rust `im-core` local state 和 read-state API | `markThreadRead` / sync apply / local projection | App 只消费 projected count，不拥有 checkpoint 或 read watermark 事实 |
| `hidden`、`pinned`、`muted` | `awiki-me` `ProductLocalStore` | `ConversationService.setThreadHidden`、`hideConversationFromRecents`、`restoreConversationToRecents` | `ImCoreConversationService` 加载 overlay 后过滤、排序和展示 |
| `customTitle`、`avatarSeed` | `awiki-me` `ProductLocalStore` | `ProductLocalStore.upsertConversationOverlay` | `ImCoreConversationService._applyOverlay` |
| 本地临时隐藏水位 | `ConversationListController` | `deleteFromRecents` 成功前后维护 memory waterline | snapshot、refresh 和 patch apply 前过滤，旧 patch 不能重新插入 |
| Agent display / lifecycle projection | `awiki-me` application service | `AgentInventoryPort` / agent control projection | `ImCoreConversationService._applyAgentLifecycleProjection` |
| group display name / avatar enrichment | `awiki-me` group application/provider | group summary refresh | `ConversationListController.applyGroupNames` |

## 3. API 与 DTO 约束

Flutter SDK conversation DTO 必须保持 core-only。以下字段不得加入 SDK public DTO 或 FRB generated DTO：

- `hidden`
- `pinned`
- `muted`
- `customTitle`
- `avatarSeed`
- `peerLifecycleState`
- `ConversationSummary`
- `ChatMessage`
- 其他 `awiki-me` App domain 类型

当前应保持的 DTO 形状：

- `crates/im-core/src/messages/dto.rs` 的 `ConversationSnapshotItem` 只包含 thread kind/id、participants、last message、unread count、unread mention、message count 和 last message time。
- `crates/im-core-dart/src/dto/message.rs` 的 `DartConversationSnapshotItem` 与 Rust core DTO 对齐。
- `packages/awiki_im_core/lib/src/models/message.dart` 的 `ConversationSnapshotItem` 是 SDK model，不引用 `awiki-me` domain。

如果未来需要把 presentation projection 下沉到 Rust，必须先新增独立的 presentation projection contract 和写入 API，不能直接扩展现有 core snapshot 来承载 App-only overlay。

## 4. App 组合规则

`ImCoreConversationService` 是 App 侧组合边界：

1. 从 `ConversationCorePort` 读取 core base row、snapshot 或 patch。
2. 使用 `ProductLocalStore` 读取 overlay。
3. 过滤隐藏会话。隐藏规则使用 overlay 的 `updatedAt` 或 provider memory waterline，只有 `lastMessageAt` 晚于隐藏时间的新消息才可以恢复会话。
4. 应用 `customTitle`、`avatarSeed`、Agent lifecycle 和 group display enrichment。
5. 输出 `ConversationSummary` 给 presentation provider。

`ConversationListController` 可以维护短生命周期 UI waterline，但只能用于防止 optimistic hide 后的旧 snapshot/patch 回填。它不是持久事实源，`clear()`、session switch 和 provider dispose 必须清理它。

## 5. 不引入 Flutter MMKV 双缓存

AWiki Me 不再新增 Flutter 侧 message/conversation/group 主数据 cache，也不引入 MMKV 作为 conversation snapshot 或 presentation truth。

原因：

- `im-core` SQLite 是 message、conversation、group、read-state 的主数据源。
- `im-core` redb snapshot 已覆盖冷启动 bootstrap 的非权威缓存需求。
- `ProductLocalStore` 只保存产品 overlay 和 UI preference，避免与 Rust projection 形成双主数据源。

## 6. 未来迁移条件

只有满足以下条件时，才考虑把部分 presentation projection 下沉到 Rust 或 SDK：

1. 字段已不再是 AWiki Me 独有产品语义，而是 CLI、App 和其他客户端共享的 IM 语义。
2. 有明确的 public SDK API、schema migration、repair/rebuild 策略和 logout/session cleanup 策略。
3. `awiki-cli-rs2`、`awiki-me`、`message-service` 和 `awiki-system-test` 的 API 文档和系统测试已同步。
4. 迁移期间不双写同一事实。旧 App overlay 到新 projection 的迁移必须有单向 owner 切换点和回滚方案。
5. DTO boundary review 确认 SDK 仍不引用 `awiki-me` App domain 类型。

## 7. 回归测试

当前必须保留以下测试覆盖：

- `tests/unit/application/messaging_conversation_service_test.dart`：验证 overlay 不进入 core 主数据、snapshot/fast list/enrichment 应用 App overlay、pinned 排序、hidden waterline、Agent lifecycle 和 runtime merge/hide。
- `tests/unit/data/im_core/awiki_im_core_mappers_test.dart`：验证 core DTO 到 App summary 的映射只通过 App 侧参数应用 overlay。
- `tests/unit/conversation_list_provider_test.dart`：验证 base row 先于 enrichment 展示、patch upsert/reorder/repair、clear 后不回填、snapshot bootstrap guard，以及 local hidden waterline 不被旧 patch 冲破。

Step 11 新增的关键回归是：`conversation patch upsert respects local hidden waterline`。它固定了本地 hide 后旧 patch 不得重新插入会话，而 `lastMessageAt` 晚于 hide 时间的新 patch 可以恢复会话。
