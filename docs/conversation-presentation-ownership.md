# Conversation Presentation And Message Rendering Ownership

本文档是 AWiki Me 会话展示、消息可见性、消息渲染分层和首屏展示链路的当前唯一入口文档。它覆盖 conversation presentation projection、message timeline、SDK DTO 到 App domain model 的映射、普通文本 / Markdown / mention / attachment / control payload 的展示规则，以及 local-first 打开会话的职责边界。

历史 plan 文档只作为执行台账和决策背景保留；如果历史 plan 与本文档或当前代码不一致，以本文档和当前代码为准。

## 1. 当前结论

`im-core` / Flutter SDK 负责 IM 基础事实；`awiki-me` 负责 App 产品展示事实、消息渲染模型和 UI 组合逻辑。

核心边界：

1. Rust `im-core` 是 message、thread、group、conversation、read-state 和 committed local projection 的主数据源。
2. Flutter SDK 暴露 core-only DTO，例如 `core.Message`、`core.ConversationSnapshotItem`、thread patch 和 realtime event。
3. `awiki-me/lib/src/data/im_core/` 是 SDK DTO 到 App domain model 的唯一生产映射层。
4. `awiki-me` presentation 层只消费 `ChatMessage`、`ConversationSummary`、`RealtimeUpdate` 等 App domain model，不直接消费 SDK DTO。
5. `ChatMessage.hasRenderableContent` 是普通聊天 timeline 是否展示消息气泡的核心 gate。
6. `ConversationListProvider` 只发布 recents、unread 和 badge 状态；`ChatThreadsProvider` / `ChatThreadsController` 拥有 message thread timeline。
7. `ChatPage` 只渲染当前 selected thread，并可对可见会话做 read ack；它不得因为 conversation summary 变化反向拉取 history。

短期不把 `hidden`、`pinned`、`muted`、`customTitle`、`avatarSeed`、Agent lifecycle 或 App domain DTO 加入 `ConversationSnapshotItem` / `DartConversationSnapshotItem`。这些字段继续由 `awiki-me` 的 `ProductLocalStore`、`ConversationService` 和 provider 层组合出来。

## 2. 分层总览

当前消息展示链路如下：

```text
Rust im-core
  SQLite local projection / runtime store / patch stream / realtime session
    -> Flutter SDK package:awiki_im_core
      core.Message / core.ConversationSnapshotMessage / core.RealtimeEvent
        -> awiki-me data adapter
          AwikiImCoreMappers / AwikiImCoreMessageAdapter / AwikiImCoreConversationAdapter
            -> awiki-me domain model
              ChatMessage / ConversationSummary / RealtimeUpdate / ThreadMessagePatch
                -> awiki-me presentation state
                  ConversationListProvider / ChatThreadsProvider
                    -> Flutter widgets
                      ChatPage / _MessageTextContent / _AttachmentContent / Agent projection widgets
```

这个分层的设计目标是：

- SDK DTO 不进入 presentation 层。
- App-only 展示字段不进入 SDK DTO。
- message timeline 和 conversation list 不双写同一事实。
- control payload、Agent projection、普通聊天气泡和 preview 各自有明确入口。
- 打开会话时先使用内存 / 本地 projection 首屏渲染，网络补同步后台化。

## 3. 文档权威层级

本文档是当前规则的主入口。相关文档的定位如下：

| 文档 | 定位 |
|---|---|
| `awiki-me/docs/conversation-presentation-ownership.md` | 当前唯一入口；记录最新展示 owner、渲染分层、可见性、preview、local-first 和测试要求。 |
| `awiki-me/README.md` | 面向仓库读者的短摘要；只说明 local-first message view 和 one-way chat presentation。 |
| `awiki-me/docs/message-mention-extension-implementation-plan/plan.md` | mention 方案历史 plan；可追溯 P9 payload 决策，但不作为当前唯一规则入口。 |
| `awiki-me/docs/message-mention-extension-implementation-plan/steps/03-app-send-render-mention.md` | mention send/render 的执行台账；记录当时的路径和验证证据。 |
| `awiki-me/docs/plan/20260628-chat-open-realtime-tail/plan.md` | 新消息首屏秒开优化历史 plan；可追溯 realtime tail、alias prewarm 和 local-first 决策。 |
| `awiki-me/docs/plan/20260628-chat-open-realtime-tail/steps/03-local-first-open-path.md` | local-first 打开路径执行台账。 |
| `awiki-cli-rs2/docs/api/im-core-public-api.md`、`awiki-cli-rs2/docs/api/im-core-interface/04-message-interface.md` | SDK/API contract 来源；不描述 AWiki Me UI 渲染。 |
| `awiki-cli-rs2/docs/flutter-sdk/awiki-me-future-integration.md` | SDK / App 映射边界来源；强调 `Message -> ChatMessage` 留在 `awiki-me`。 |

修改消息渲染、可见性、preview、timeline source-of-truth 或 local-first 行为时，必须同步本文档。历史 plan 路径不需要追改为最新事实，除非该 plan 自身被重新恢复执行。

## 4. Owner 边界

| 数据或行为 | 当前 owner | 写入入口 | 读取 / 组合入口 |
|---|---|---|---|
| message、thread、group、conversation base projection | Rust `im-core` SQLite / runtime store | Flutter SDK message/group/sync/read-state API | `ConversationCorePort`、`MessageCorePort`、`AwikiImCore*Adapter` |
| conversation snapshot cache | Rust `im-core` redb snapshot cache | `im-core` 从 committed projection 保存 | `ConversationCorePort.loadConversationSnapshot` |
| conversation patch stream | Rust `im-core` runtime store | committed sync/local write invalidation | `ConversationCorePort.watchConversationPatches` |
| thread message patch stream | Rust `im-core` runtime store | committed local message projection、sync、realtime incoming | `MessageCorePort.watchThreadPatches` / `ChatThreadsController` |
| unread count、unread mention、read-state 展示事实 | Rust `im-core` local state 和 read-state API | `markThreadRead` / sync apply / local projection | App 只消费 projected count，不拥有 checkpoint 或 read watermark 事实 |
| SDK message DTO | Flutter SDK / Rust `im-core` | SDK `messages`、`groups`、`realtime` API | 只允许 `awiki-me/lib/src/data/im_core/` 生产路径直接消费 |
| SDK DTO -> App message projection | `awiki-me` data mapper | `AwikiImCoreMappers.chatMessageFromCore`、`chatMessageFromSnapshot` | `ChatMessage` |
| message renderability | `awiki-me` domain model | `ChatMessage.hasRenderableContent` | adapters、providers、timeline、preview 回填共同使用 |
| message thread timeline | `ChatThreadsProvider` / `ChatThreadsController` | `openConversation`、realtime update、thread patch、thread-after、patch gap / stream repair | `ChatPage` 只通过 `chatThreadProvider` 渲染当前 thread |
| text / Markdown / mention / attachment widget render | `awiki-me` presentation widgets | `ChatMessage` 字段和当前 bubble context | `chat/parts/chat_message_part.dart` |
| conversation preview | `awiki-me` mapper / `ChatThreadsController` | SDK snapshot、realtime hint、latest renderable `ChatMessage` | `ConversationListProvider`、conversation workspace |
| control payload 会话预览可见性 | `awiki-me` mapper / realtime projection | SDK message 的 `body.text` + `payloadJson` | 只允许带显式可见文本的 control payload 更新 recents 预览；payload-only control 继续隐藏 |
| `hidden`、`pinned`、`muted` | `awiki-me` `ProductLocalStore` | `ConversationService.setThreadHidden`、`hideConversationFromRecents`、`restoreConversationToRecents` | `ImCoreConversationService` 加载 overlay 后过滤、排序和展示 |
| `customTitle`、`avatarSeed` | `awiki-me` `ProductLocalStore` | `ProductLocalStore.upsertConversationOverlay` | `ImCoreConversationService._applyOverlay` |
| 本地临时隐藏水位 | `ConversationListController` | `deleteFromRecents` 成功前后维护 memory waterline | snapshot、refresh 和 patch apply 前过滤，旧 patch 不能重新插入 |
| Agent display / lifecycle projection | `awiki-me` application service | `AgentInventoryPort` / agent control projection | `ImCoreConversationService._applyAgentLifecycleProjection` |
| group display name / avatar enrichment | `awiki-me` group application/provider | group summary refresh | `ConversationListController.applyGroupNames` |
| 可见会话 read ack | `ChatPage` 可见性 + `ChatThreadsProvider` mark-read | `ChatView` 挂载、当前可见 summary 更新、用户回到底部 | 只清未读和异步上报 read state，不触发 history/thread sync |

## 5. API 与 DTO 约束

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
- `awiki-me/lib/src/domain/entities/chat_message.dart` 是 App domain model，不得移动到 SDK 或 FRB generated DTO。

如果未来需要把 presentation projection 下沉到 Rust，必须先新增独立的 presentation projection contract 和写入 API，不能直接扩展现有 core snapshot 来承载 App-only overlay。

## 6. SDK Message 到 ChatMessage 的映射

`AwikiImCoreMappers` 是当前生产映射边界：

- `chatMessageFromCore(core.Message, ownerDid: ...)`
- `chatMessageFromSnapshot(core.ConversationSnapshotMessage, ownerDid: ...)`
- `conversationFromCore(...)`
- `conversationFromSnapshot(...)`
- `realtimeUpdateFromCore(...)`

映射规则：

| 输入事实 | App 字段 / 行为 |
|---|---|
| `message.id` | `ChatMessage.localId` 和 `remoteId` |
| SDK thread kind / group / direct peer | 规范化为 App `threadId`、`groupId`、`receiverDid` |
| `message.sender` + `ownerDid` + direction | `ChatMessage.isMine` |
| `body.text` | 普通文本 fallback，写入 `ChatMessage.content` |
| P9 mention payload JSON | `ChatMessage.content = payload.text`，`mentions = parsed mentions`，`payloadJson` 保留原文，`originalType = application/json` |
| attachment manifest | `ChatMessage.attachment`；caption 优先成为 `content` / preview 文本 |
| `metadata.contentType` / `body.kind` | `ChatMessage.originalType` |
| encrypted content type | `ChatMessage.isEncrypted` |
| server sequence | `ChatMessage.serverSequence`，用于排序、thread-after 和 first-paint 判断 |

`ChatMessage` 的关键 derived fields：

- `isTextMessage`：`originalType` 为空、`text`、`markdown`、`text/plain` 或 `text/markdown`。
- `isMentionPayload`：`payloadJson != null` 且 `originalType` 包含 `json`。
- `hasDisplayableText`：`content.trim().isNotEmpty` 且消息是 text 或 mention payload。
- `isAgentControlPayload`：`AgentControlPayloads.isControl(payloadJson)`。
- `hasRenderableContent`：不是 agent control payload，且存在 displayable text 或 attachment。
- `previewText`：优先使用可见文本；attachment 有 caption 时用 caption，否则用 attachment display name。

## 7. 消息类型与渲染规则

普通聊天 timeline 只渲染 `hasRenderableContent == true` 的消息。不同消息类型的处理规则如下：

| 类型 | 映射结果 | Timeline 渲染 | Preview |
|---|---|---|---|
| 普通 text | `content = body.text`，`originalType = text` 或 `text/plain` | `_MessageTextContent`；incoming bubble 可走 `MarkdownBody`，outgoing bubble 默认 plain text | `content.trim()` |
| Markdown | `originalType = markdown` 或 `text/markdown` | `_MessageTextContent`；当前 bubble context 决定是否 `renderMarkdown`，incoming / attachment caption 可用 `MarkdownBody` | 原始可见文本 |
| P9 mention payload | `content = payload.text`，`mentions` 为合法 ranges，`payloadJson` 保留 | `_MessageTextContent` 校验 range 后高亮 mention；有 Markdown 语法且允许 markdown 时走带 mention marker 的 `MarkdownBody`，否则走 `Text.rich` | `payload.text` |
| attachment | `attachment != null`，caption 可写入 `content` | `_AttachmentContent`；caption 再委托 `_MessageTextContent` 渲染，文件主体显示文件名、类型、大小和下载 / 打开状态 | caption 优先，否则 attachment display name |
| Agent / system control payload | `payloadJson` 可被 `AgentControlPayloads` 识别 | 不作为普通聊天气泡渲染；交给 Agent/control projection 或状态组件处理 | 只有显式 `body.text` 可作为 recents 预览；payload-only 隐藏 |
| unknown payload-only JSON | 通常无 `content` 或无法通过 mention/control 解析 | 默认不可渲染，除非 mapper 能投影出可见文本且不属于 control payload | 按 mapper fallback，避免把 raw JSON 当普通用户文案展示 |

`_MessageTextContent` 当前位于 `awiki-me/lib/src/presentation/chat/parts/chat_message_part.dart`。它不直接解析 SDK DTO，只接收 App `ChatMessage` 已投影出的 `text`、`mentions` 和 `payloadJson`。

mention 渲染规则：

1. 先用 `ChatMessage.mentions` 校验 `rangeMatches(text)`。
2. 再从 `payloadJson` 解析 P9 payload，补充合法 mention ranges。
3. 去重并按 start offset 排序。
4. 如果当前允许 Markdown 且文本含 Markdown 语法，使用私有 marker + custom inline syntax / builder 把 mention 高亮嵌入 `MarkdownBody`。
5. 如果不走 Markdown 且存在合法 mention，使用 `Text.rich` 和 `TextSpan` 高亮。
6. 无合法 mention 时按当前 bubble context 走 Markdown 或 plain text。

这意味着历史 plan 中“mention payload 默认不走 MarkdownBody”的说明只代表当时计划；当前实现支持 mention 与 Markdown 渲染组合，本文档记录当前事实。

## 8. Control Payload 和 Agent Projection

Agent / Message Agent control payload 是控制面事件，不是普通聊天消息。默认规则：

1. `ChatMessage.hasRenderableContent` 对 agent control payload 返回 false。
2. payload-only control 不进入普通聊天 timeline，也不触发普通消息通知。
3. control payload 带有显式 `body.text` 时，mapper 允许它更新 conversation preview，避免详情页可见状态文本和 recents “暂无消息”不一致。
4. control payload 的结构化语义交给 Agent control projection、runtime status、Message Agent cards 或后续 application service 处理。
5. 不允许把 control payload raw JSON 作为普通聊天文案展示。

`realtimeUpdateFromCore` 对 control payload 的处理也遵守该边界：有可见 preview 才返回 conversation update；结构化 payload 放在 `RealtimeUpdate.agentControlPayload`，普通 `message` 为空。

## 9. Conversation Preview 规则

Conversation preview 不是第二套消息真相，它只是 conversation list 的展示投影。

Preview 来源优先级：

1. control payload：只使用显式 `body.text`，无文本则隐藏。
2. attachment：caption 优先，否则使用 attachment display name。
3. P9 mention payload：使用 `payload.text`。
4. 普通文本 / Markdown：使用 `body.text`。
5. fallback：unsupported content type、content type 或 body kind，仅用于避免完全空白的低保真提示。

`ConversationSummary.lastMessageSnapshot` 只保存 `hasRenderableContent == true` 的 `ChatMessage`。这样打开会话时可以用 snapshot 预热首屏，但不会把 payload-only control 当成普通消息气泡。

打开会话后，如果 `ChatThreadsController` 从 alias、snapshot、本地历史、thread-after、thread patch 或远端 history 中加载到更新的可渲染消息，会用最新 `previewText` 回填 `ConversationListController` 的 preview。这样详情页已经展示的第一条消息不会让 recents 继续显示“暂无消息”。

## 10. Timeline 和 Local-First 打开路径

Chat presentation 是单向的：

- `ConversationListProvider` 负责 recents / unread / badge 状态。
- `ChatThreadsProvider` / `ChatThreadsController` 负责 thread timeline、merge、sort、repair、alias prewarm 和 read ack 调度。
- `ChatPage` 渲染 selected thread；它可以确认当前会话可见并触发 read ack，但不得因 summary 更新主动补拉 history。

打开会话的 first-paint 路径：

1. 根据 selected conversation 计算 display thread id。
2. 启动或确认 thread patch subscription。
3. 从当前 memory thread 检查是否已有 `hasRenderableContent` 消息。
4. 如果 display thread 为空，从 conversation aliases 复制已预热的 renderable messages。
5. 如果 conversation 有 renderable `lastMessageSnapshot`，可用 snapshot 预热。
6. 如果内存不足，再读取 recent local history。
7. memory / snapshot / local history 命中后，首屏立即可渲染，并后台触发 `syncThreadAfter`。
8. remote history 只在本地确实为空、本地读取失败或显式 force refresh 时兜底。

特殊边界：`dm:peer-scope:*` 直聊会话使用精确 storage thread 来隔离 Agent controller/runtime 消息；当前 `im-core` 尚未支持对 raw `ThreadRef::Thread` 做远端 history 拉取，会返回 `unsupported_capability: thread-history`。因此这类会话必须保持 local-first：打开会话时读取本地 history，并尽力执行 `syncThreadAfter`；当本地为空或用户强制刷新时，App 也不得回退到未支持的远端 thread history，更不得把该错误暴露为 UI 报错。等 native `thread-history` 能力补齐后，再重新打开这个边界。

实时消息路径：

1. Rust `im-core` 先把 realtime incoming 写入本地 SQLite projection。
2. committed projection 成功后，runtime store 发 conversation patch 和 thread message patch。
3. App 收到 typed realtime update 后，通过 `ChatThreadsController.applyRealtimeUpdate` 把同一条消息预热到 conversation thread、message thread、DID、handle、canonical direct/group 等 alias。
4. 首次打开会话时，`open.alias_prewarm` 可以命中这些 alias，避免等待远端 history。

禁止路径：

- App 不读写 global reliable checkpoint。
- App 不传 `since_event_seq`。
- App 不手写 raw `/im/rpc` `sync.*` payload。
- App 不把 realtime `sync` hint 当作 checkpoint commit。
- App 不从 conversation summary 变化反向调用 thread history sync。

诊断事件：

- `realtime.prewarm`
- `open.alias_prewarm.hit` / `open.alias_prewarm.miss`
- `chat.open.first_paint`
- `chat.local_history.*`
- `im_core_messages.local_history*`

性能指标和排查方法见 `awiki-me/docs/performance-tracing.md`。

## 11. App 组合规则

`ImCoreConversationService` 是 App 侧 conversation 组合边界：

1. 从 `ConversationCorePort` 读取 core base row、snapshot 或 patch。
2. 使用 `ProductLocalStore` 读取 overlay。
3. 过滤隐藏会话。隐藏规则使用 overlay 的 `updatedAt` 或 provider memory waterline，只有 `lastMessageAt` 晚于隐藏时间的新消息才可以恢复会话。
4. 应用 `customTitle`、`avatarSeed`、Agent lifecycle 和 group display enrichment。
5. 输出 `ConversationSummary` 给 presentation provider。

`ConversationListController` 可以维护短生命周期 UI waterline，但只能用于防止 optimistic hide 后的旧 snapshot/patch 回填。它不是持久事实源，`clear()`、session switch 和 provider dispose 必须清理它。

## 12. 不引入 Flutter MMKV 双缓存

AWiki Me 不再新增 Flutter 侧 message/conversation/group 主数据 cache，也不引入 MMKV 作为 conversation snapshot 或 presentation truth。

原因：

- `im-core` SQLite 是 message、conversation、group、read-state 的主数据源。
- `im-core` redb snapshot 已覆盖冷启动 bootstrap 的非权威缓存需求。
- `ProductLocalStore` 只保存产品 overlay 和 UI preference，避免与 Rust projection 形成双主数据源。
- `ChatThreadsProvider` 的内存 tail 是 UI 状态和 first-paint 加速，不是持久主数据源。

## 13. 回归测试

当前必须保留以下测试覆盖：

- `tests/unit/application/messaging_conversation_service_test.dart`：验证 overlay 不进入 core 主数据、snapshot/fast list/enrichment 应用 App overlay、pinned 排序、hidden waterline、Agent lifecycle 和 runtime merge/hide。
- `tests/unit/data/im_core/awiki_im_core_mappers_test.dart`：验证 core DTO 到 App summary 的映射只通过 App 侧参数应用 overlay，并固定带显式可见文本的 control payload 可以更新 recents 预览、payload-only control 继续隐藏。
- `tests/unit/data/im_core/awiki_im_core_payload_mapper_test.dart`：验证 payload / mention 解析、合法 range 投影和无效 payload fallback。
- `tests/unit/chat_mention_send_test.dart`：验证有 valid mentions 时发送 payload，无 mentions 时继续走普通 sendText。
- `tests/unit/chat_mention_composer_test.dart`：验证 draft mention range 维护、编辑失效和候选插入。
- `tests/unit/chat_page_test.dart`：验证聊天窗口渲染、read ack 边界、header 行为和关键 widget 行为。
- `tests/unit/chat_provider_open_test.dart`：验证打开会话 local-first/thread-after/remote fallback、thread patch version gap repair、thread stream closed repair/re-subscribe，以及 unread-only summary 不单独触发 history load。
  - 其中 `dm:peer-scope:*` 直聊必须验证本地为空和强制同步时都跳过未支持的远端 `thread-history`，避免点击 Codex / Agent 会话时弹出 `unsupported_capability: thread-history`。
- `tests/unit/app_runtime_notification_test.dart`：验证 realtime update、alias prewarm 和通知 / runtime 分发边界。
- `tests/unit/conversation_list_provider_test.dart`：验证 base row 先于 enrichment 展示、patch upsert/reorder/repair、clear 后不回填、snapshot bootstrap guard、local hidden waterline 不被旧 patch 冲破，以及已读/no-op read ack 不重复 emit。

涉及首屏性能或真实 App + CLI peer 消息流的变更，还应运行：

- `cd awiki-me && dart run tests/e2e/runner.dart --case performance`
- 用户明确要求 AWiki Me E2E 时，默认运行 `cd awiki-me && dart run tests/e2e/runner.dart --case full`

涉及 SDK local projection / patch stream 行为的变更，还应同步运行对应 `awiki-cli-rs2` Rust tests，并按 workspace AGENTS 说明使用 remote `awiki.info` 环境运行 AWiki system tests。

## 14. 未来迁移条件

只有满足以下条件时，才考虑把部分 presentation projection 下沉到 Rust 或 SDK：

1. 字段已不再是 AWiki Me 独有产品语义，而是 CLI、App 和其他客户端共享的 IM 语义。
2. 有明确的 public SDK API、schema migration、repair/rebuild 策略和 logout/session cleanup 策略。
3. `awiki-cli-rs2`、`awiki-me`、`message-service` 和 `awiki-system-test` 的 API 文档和系统测试已同步。
4. 迁移期间不双写同一事实。旧 App overlay 到新 projection 的迁移必须有单向 owner 切换点和回滚方案。
5. DTO boundary review 确认 SDK 仍不引用 `awiki-me` App domain 类型。
6. 本文档的 owner 表、数据流、渲染规则和测试清单已同步更新。

## 15. 会话头部信息入口

当前聊天头部不再渲染右上角的资料 / 会话信息入口按钮：

- macOS 聊天头部不显示 `身份卡`、`群聊信息` 和 `会话信息` 按钮。
- 窄屏 / 移动聊天头部不显示右侧竖向更多按钮。
- 头像仍是轻量资料入口：直聊打开用户 / 智能体信息弹窗，群聊打开既有群详情路由。
- 直聊头像弹窗采用 shell-first 渲染：点击后立即基于 `ConversationSummary`、本地 runtime `AgentSummary` 和 DID 展示标题、头像、DID、类型与 Agent 收件箱入口；`peerProfileProvider` 的公开 profile、关系状态和主页 Markdown 返回后再增量补齐昵称、头像、handle、身份卡正文和关系标签。
- 公开 profile 或后续关系 / 主页 Markdown 加载失败不得阻塞弹窗打开，也不得清空已展示的基础信息；只在身份卡区域内提示资料暂不可用或继续保留已返回的 profile 内容。
- 群详情里的成员刷新能力不属于聊天头部入口，保留在群详情 / 群信息组件内。

相关回归覆盖在：

- `tests/unit/chat_page_test.dart`：除头部入口移除外，还固定头像信息弹窗必须先展示基础信息，并在 profile 返回后补齐资料。
- `tests/unit/conversation_workspace_test.dart`
- `tests/e2e/flutter/app/app_smoke_test.dart`
- `tests/e2e/flutter/app/ui_visual_verification_test.dart`
