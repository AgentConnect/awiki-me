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
| control payload 会话预览可见性 | `awiki-me` mapper / realtime projection | SDK message 的 `body.text` + `payloadJson` | `AwikiImCoreMappers` 只允许带显式可见文本的 control payload 更新 recents 预览；payload-only control 继续隐藏 |
| message thread timeline | `ChatThreadsProvider` / `ChatThreadsController` | `openConversation`、realtime update、thread patch、thread-after、patch gap / stream repair | `ChatPage` 只通过 `chatThreadProvider` 渲染当前 thread |
| 可见会话 read ack | `ChatPage` 可见性 + `ChatThreadsProvider` mark-read | `ChatView` 挂载、当前可见 summary 更新、用户回到底部 | 只清未读和异步上报 read state，不触发 history/thread sync |

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

Agent / Message Agent control payload 默认不作为普通聊天消息渲染，也不触发通知。但当 SDK message 同时带有 `payloadJson` 和显式 `body.text`（例如聊天详情中展示的 “Agent 已准备好。” 状态气泡）时，`awiki-me` 会把这段可见文本作为会话列表预览并保留该会话，避免用户在详情页已经看到状态消息而 recents 仍显示“暂无消息”。没有 `body.text` 的 payload-only control 仍被视为纯系统控制面事件，在 snapshot、patch 和 realtime recents projection 中保持隐藏。

打开会话时，如果 `ChatThreadsController` 从本地历史、远端历史、thread-after 或 thread patch 中加载到了可渲染消息，会用最新可渲染消息回填 `ConversationListController` 的预览。这样即使首次进入会话前 recents 只有空预览，详情页已经展示的第一条消息也会同步到列表，不再继续显示“暂无消息”。

实时消息的详情页预热以 `ChatThreadsController.applyRealtimeUpdate` 为入口。普通 realtime update 必须携带 `conversationHint`，provider 会把消息写入会话 thread、message thread、DID、handle、canonical direct/group 等 alias；首次打开会话前如果当前 display thread 为空，会先从这些 alias 中复制已有可渲染消息，再决定是否读取本地历史或远端 history。诊断日志包含 `realtime.prewarm`、`open.alias_prewarm.hit/miss` 和 `chat.open.first_paint`，用于确认“收到新消息后首次打开”是否命中内存预热而不是落到慢路径。

Chat presentation 不再有从上层 summary 反向驱动消息历史同步的常规链路。`ConversationListProvider` 只发布 recents / unread / badge 状态；`ChatPage` 可以监听该状态以确认当前可见会话需要 read ack，但不得调用 `syncHistoryForConversation`、`syncVisibleConversationAfterSummaryUpdate` 或任何 thread repair 来补拉消息。必要同步只发生在打开会话、thread patch version gap、thread patch stream error/closed repair/re-subscription 等 `ChatThreadsProvider` 内部路径。macOS header 也不再提供手动刷新当前会话按钮。

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
- `tests/unit/data/im_core/awiki_im_core_mappers_test.dart`：验证 core DTO 到 App summary 的映射只通过 App 侧参数应用 overlay，并固定带显式可见文本的 control payload 可以更新 recents 预览、payload-only control 继续隐藏。
- `tests/unit/chat_page_test.dart`：验证 conversation list 刷新到新消息或 canonical thread 后，当前聊天窗口只做 read ack，不反向补拉 history；同时固定 `chat-refresh-button` 不存在。
- `tests/unit/chat_provider_open_test.dart`：验证打开会话 local-first/thread-after/remote fallback、thread patch version gap repair、thread stream closed repair/re-subscribe，以及 unread-only summary 不单独触发 history load。
- `tests/unit/conversation_list_provider_test.dart`：验证 base row 先于 enrichment 展示、patch upsert/reorder/repair、clear 后不回填、snapshot bootstrap guard、local hidden waterline 不被旧 patch 冲破，以及已读/no-op read ack 不重复 emit。

Step 11 新增的关键回归是：`conversation patch upsert respects local hidden waterline`。它固定了本地 hide 后旧 patch 不得重新插入会话，而 `lastMessageAt` 晚于 hide 时间的新 patch 可以恢复会话。
