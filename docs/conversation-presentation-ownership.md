# Conversation Presentation And Message Rendering Ownership

本文档是 AWiki Me 会话展示、消息可见性、消息渲染分层和首屏展示链路的当前唯一入口文档。它覆盖 conversation presentation projection、message timeline、SDK DTO 到 App domain model 的映射、普通文本 / Markdown / mention / attachment / control payload 的展示规则，以及 local-first 打开会话的职责边界。

历史 plan 文档只作为执行台账和决策背景保留；如果历史 plan 与本文档或当前代码不一致，以本文档和当前代码为准。已过时且会误导执行的旧 SDK migration plan 不再保留在 `docs/` 主路径下。

## 1. 当前结论

`im-core` / Flutter SDK 是 message、conversation identity、canonical `conversationId` read model、read-state、send/outbox、sync/realtime/backfill committed projection 的事实源。AWiki Me 只拥有 product overlay、read presentation waterline、renderability、draft/scroll/loading、短生命周期 UI window 和 widget composition。

核心边界：

1. Rust `im-core` 是 message、thread、group、conversation、read-state、send/outbox 和 committed local projection 的主数据源。
2. Flutter SDK 暴露 core-only DTO，例如 `core.Message`、`core.ConversationSnapshotItem`、conversation identity、conversation timeline patch 和 realtime event。
3. `awiki-me/lib/src/data/im_core/` 是 SDK DTO 到 App domain model 的唯一生产映射层。
4. `awiki-me` presentation 层只消费 `ChatMessage`、`ConversationSummary`、`RealtimeUpdate` 等 App domain model，不直接消费 SDK DTO。
5. `ChatMessage.hasRenderableContent` 是普通聊天 timeline 是否展示消息气泡的核心 gate。
6. `ConversationListProvider` 只发布 recents、unread 和 badge 状态；base row 来自 core conversation read model，App 只叠加 product overlay 和短生命周期 read presentation waterline。
7. `ChatThreadsProvider` / `ChatThreadsController` 只拥有当前 `conversationId` 的 UI window，不拥有消息归属、read watermark、send correctness 或 realtime correctness。
8. `ChatPage` 只渲染当前 selected conversation，并可对可见会话发出 read intent；它不得因为 conversation summary 变化反向拉取 history。

App list/detail/read/send/realtime 主链路必须通过 `ConversationIdentity.conversationId` / `AppConversationReadRef` 消费 core projection。`ThreadRef`、alias、targetPeer/targetDid、visibility key 只允许作为 legacy adapter、migration fallback 或 diagnostic input，不再作为消息归属、read correctness、send correctness 或 realtime correctness 的机制。

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
| message、thread、group、conversation base projection | Rust `im-core` SQLite / runtime store | Flutter SDK message/group/sync/read-state API | `ConversationCorePort`、`MessageCorePort`、`ConversationTimelineMessageCorePort`、`AwikiImCore*Adapter` |
| canonical `conversationId` / identity aliases | Rust `im-core` / SDK DTO | resolver、message upsert、conversation projection migration | App 只消费 `ConversationIdentity` / `ConversationSummary.effectiveConversationId`，不自行生成 direct canonical key |
| conversation snapshot cache | Rust `im-core` redb snapshot cache | `im-core` 从 committed projection 保存 | `ConversationCorePort.loadConversationSnapshot` |
| conversation patch stream | Rust `im-core` runtime store | committed sync/local write invalidation | `ConversationCorePort.watchConversationPatches` |
| conversation timeline patch stream | Rust `im-core` runtime store | committed local message projection、sync、realtime incoming | `ConversationTimelineMessageCorePort.watchConversationTimelinePatches` / `ChatThreadsController` |
| unread count、unread mention、read-state 展示事实 | Rust `im-core` local state 和 read-state API | `markConversationRead` / sync apply / local projection | App 只消费 projected count，不拥有 checkpoint 或 read watermark 事实 |
| text / payload / attachment send/outbox/local echo | Rust `im-core` messages / attachments projection + send state | `sendConversationText` / `sendConversationPayload` / `sendConversationAttachment` / retry result | App 发送 intent 并渲染 core timeline row 的 pending/failed/sent；sending row 连续可见满 3 秒后才显示转圈，明确 send result 只可收敛已由 core patch 暴露的 row；附件可保留本地文件 preview 作为短生命周期 UI 状态，但不得用 memory pending、thread move 或本地 upsert conversation row 决定 correctness |
| realtime / backfill | Rust `im-core` sync/realtime committed projection | realtime hint 调度 `syncDelta`，conversation-after 补新，projection commit 后 patch | App 不从 realtime typed event 直接写 list/timeline truth；只消费 core patch/read model 并在 gap 时 repair |
| SDK message DTO | Flutter SDK / Rust `im-core` | SDK `messages`、`groups`、`realtime` API | 只允许 `awiki-me/lib/src/data/im_core/` 生产路径直接消费 |
| SDK DTO -> App message projection | `awiki-me` data mapper | `AwikiImCoreMappers.chatMessageFromCore`、`chatMessageFromSnapshot` | `ChatMessage` |
| message renderability | `awiki-me` domain model | `ChatMessage.hasRenderableContent` | adapters、providers、timeline、preview 回填共同使用 |
| message timeline window | `ChatThreadsProvider` / `ChatThreadsController` | `openConversation`、conversation timeline load、conversation timeline patch、conversation-after、patch gap / stream repair | `ChatPage` 只通过 `chatThreadProvider` 渲染当前 selected conversation window |
| text / Markdown / mention / attachment widget render | `awiki-me` presentation widgets | `ChatMessage` 字段和当前 bubble context | `chat/parts/chat_message_part.dart` |
| conversation preview | Rust `im-core` conversation summary + `awiki-me` mapper/overlay | SDK snapshot、conversation patch、latest renderable core message projection | `ConversationListProvider`、conversation workspace |
| control payload 会话预览可见性 | `awiki-me` mapper / realtime projection | SDK message 的 `body.text` + `payloadJson` | 只允许带显式可见文本的 control payload 更新 recents 预览；payload-only control 继续隐藏 |
| `hidden`、`pinned`、`muted` | `awiki-me` `ProductLocalStore` | `ConversationService.setThreadHidden`、`hideConversationFromRecents`、`restoreConversationToRecents` | `ImCoreConversationService` 加载 overlay 后过滤、排序和展示 |
| `customTitle`、`avatarSeed` | `awiki-me` `ProductLocalStore` | `ProductLocalStore.upsertConversationOverlay` | `ImCoreConversationService._applyOverlay` |
| 本地临时隐藏水位 | `ConversationListController` | `deleteFromRecents` 成功前后维护 memory waterline | snapshot、refresh 和 patch apply 前过滤，旧 patch 不能重新插入 |
| 本地新建空会话 intent | `ConversationListController` presentation memory | identity flow `startConversation` | 只让用户刚显式发起且尚无消息的会话跨 refresh / patch reset 保持在 recents；core row 出现消息、用户删除、normalization reject 或 session clear 后释放，最多保留 64 条，不写 durable message/conversation truth |
| recents read presentation waterline | `ConversationListController` presentation memory | refresh / fast-local / enrichment / patch / repair / group-name / visible message watermark / read ack | 发布 recents 前统一投影：latest message watermark 只前进，read watermark 只前进；summary-only 更新不能清 unread；read watermark 覆盖的旧 unread 不能重新出现；旧的 0 unread 不能清掉更新消息；可见状态只在严格会话身份内推进，不跨 legacy DID 与 peer-scoped identity 桥接 |
| Agent display / lifecycle projection | `awiki-me` application service | `AgentInventoryPort` / agent control projection | `ImCoreConversationService._applyAgentLifecycleProjection` |
| group display name / avatar enrichment | `awiki-me` group application/provider | group summary refresh | `ConversationListController.applyGroupNames` |
| 可见会话 read ack | `ChatPage` 可见性 + `ChatThreadsProvider` mark-read intent | `ChatView` 挂载、当前可见 summary 更新、用户回到底部 | 调用 `markConversationRead(AppConversationReadRef, watermark)`；普通 summary ack 的 watermark 来自当前线程中被本次 conversation summary 覆盖的最新 renderable message；用户已在底部或明确强制的 visible ack 可使用当前线程最新已渲染消息 watermark |

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

- `crates/im-core/src/messages/dto.rs` 的 `ConversationSnapshotItem` 是 core-only conversation projection DTO，可包含 thread kind/id、`conversation_identity`、participants、last message、unread count、unread mention marker、message count 和 last message time。
- `crates/im-core-dart/src/dto/message.rs` 的 `DartConversationSnapshotItem` 与 Rust core DTO 对齐。
- `packages/awiki_im_core/lib/src/models/message.dart` 的 `ConversationSnapshotItem` 是 SDK model，不引用 `awiki-me` domain。
- `awiki-me/lib/src/domain/entities/chat_message.dart` 是 App domain model，不得移动到 SDK 或 FRB generated DTO。

如果未来需要把 presentation projection 下沉到 Rust，必须先新增独立的 presentation projection contract 和写入 API，不能直接扩展现有 core snapshot 来承载 App-only overlay。

`conversationIdentity`、`serverSequence`、`sendState`、`retryPlan`、unread mention marker 和 redacted attachment manifest 属于 core projection / SDK DTO 范畴；它们可以进入 SDK DTO。`hidden`、`pinned`、`muted`、`customTitle`、`avatarSeed`、Agent lifecycle、`ConversationSummary`、`ChatMessage` 和 UI window 状态属于 AWiki Me presentation/application 范畴，不能进入 SDK DTO。

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
| attachment | `attachment != null`，caption 可写入 `content` | `_AttachmentContent`；caption 再委托 `_MessageTextContent` 渲染；PNG/JPEG/GIF/WebP 在本地路径可用或远端对象已知且不超过 20 MiB 时经 App cache 内联显示，解码/下载失败、未知大小、超限或其它类型回退为文件名、类型、大小和下载 / 打开状态 | caption 优先，否则 attachment display name |
| Agent / system control payload | `payloadJson` 可被 `AgentControlPayloads` 识别 | 不作为普通聊天气泡渲染；交给 Agent/control projection 或状态组件处理 | 只有显式 `body.text` 可作为 recents 预览；payload-only 隐藏 |
| unknown payload-only JSON | 通常无 `content` 或无法通过 mention/control 解析 | 默认不可渲染，除非 mapper 能投影出可见文本且不属于 control payload | 按 mapper fallback，避免把 raw JSON 当普通用户文案展示 |

`_MessageTextContent` 当前位于 `awiki-me/lib/src/presentation/chat/parts/chat_message_part.dart`。它不直接解析 SDK DTO，只接收 App `ChatMessage` 已投影出的 `text`、`mentions` 和 `payloadJson`。

附件显示的 SDK 输入和显示投影要分开理解：发送请求可以使用 SDK `MessageBody::Attachment` / `sendConversationAttachment`，但当前 SDK display DTO 不新增 `MessageBodyView::Attachment`。附件消息通过 core 持久化的 redacted attachment manifest、content type、metadata attributes 和 mapper 投影为 `ChatMessage.attachment`；AWiki Me 不能用本地临时文件 preview 替代 core projection 来决定 list/detail/send correctness。内联图片只是一层短生命周期 presentation：远端内容仍通过 `AttachmentPreviewService`、core download 和 app-owned cache 获取，不允许 UI 根据 object URI 绕过 core 直接联网；无法安全加载时必须保留文件卡和原下载入口。

Composer 的附件来源仍统一进入 `AttachmentDraft`：文件选择、拖拽、剪贴板图片和 macOS `/usr/sbin/screencapture -i -x` 交互式截图都只负责暂存，用户点击发送后才调用 canonical attachment send API。截图期间主窗口始终保持可见，不再根据 Shift 或 native 全局 modifier 隐藏 App。Emoji 面板只修改当前 `TextEditingValue` 的选区并沿用 draft mention range 转换，不引入新的消息类型。

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

“发起新消息”是 recents 的一个短生命周期例外：搜索、联系人、关注/粉丝、Profile 和 Agent 入口都必须先完成 SDK directory resolution，直接消费 Core 返回的 canonical `conversationId`，再由 `ConversationListController.startConversation` 发布空 direct row 并记录 locally-started intent。只有裸 Handle 时，App 用已关联 DID 解析，不自行补 domain；完整 Handle 已解析到 user scope 时，初始 row 必须已经是 `dm:peer-scope:v1:*`。解析缺失/退化或 identity 不一致时 fail closed，不写 recents/overlay。App 不能先创建 `dm:<DID>` 再等待首条消息纠正。authoritative refresh、snapshot repair 或 patch reset 尚未返回该会话时，只保留这类用户显式创建的空 row；普通空 local row 仍会被 authoritative reset 清理。

identity flow 与 core refresh / patch 仍可能并发，且旧数据库或 directory lookup 降级时仍可能出现 legacy DID row。该兼容情况只允许在当前 locally-started intent 内做一次 presentation bridge：候选 row 必须仍是 replaceable legacy alias，两边必须具有同一权威 domain-qualified Handle，然后以 core canonical id/thread 胜出并同步 selected conversation。新建完整 Handle 主路径不得依赖这个 bridge；裸 local-part、display name、头像或两个 peer-scoped row 也不得使用它。Handle 在这里仅是兼容迁移证据，不参与消息归属、路由、read ack 或授权。

打开会话后，text/payload/attachment 首发、重试和 read/sync 都传入同一 canonical `AppConversationReadRef`；Core 用 directory 解析时写入的 owner-scoped Direct route 寻址 current DID。App 不得把 peer-scope 会话降级为 `dm:<targetDid>` write alias。`ChatThreadsController` 只从 canonical `conversationId` timeline、conversation timeline patch 或 committed projection repair 中获得更新消息。列表 preview 的 authoritative base 仍来自 `im-core` conversation summary projection；App 可以做短生命周期 UI overlay / optimistic state，但不能把 legacy alias、remote history best-effort page 或 realtime hint 当作第二套 preview 真相。`ConversationListProvider` 是 recents state 的唯一发布边界，snapshot、fast-local、enrich、patch reset/upsert/remove/reorder、repair、group-name enrichment 和 read ack 都必须在发布前应用同一套 read presentation waterline。这个 waterline 只接受两类因果事件：latest message watermark 前进、read watermark 前进。summary-only 更新不能提前清 unread；已经被 read watermark 覆盖的迟到 unread 不能重新出现；旧的 0 unread 不能清掉更新消息；DID-backed legacy direct row 可以提交远端 read ack，但不能在本地 presentation waterline 中污染新的 peer-scoped identity。真正的 read state 必须通过带 message watermark 的 `markConversationRead(AppConversationReadRef, watermark)` 提交。

## 10. Timeline 和 Local-First 打开路径

Chat presentation 是单向的：

- `ConversationListProvider` 负责 recents / unread / badge 状态，base row 来自 core conversation read model，App 只叠加 product overlay 和 read presentation waterline。
- `ChatThreadsProvider` / `ChatThreadsController` 负责 conversation timeline window、merge、sort、repair 和 read ack 调度，主 key 是 `ConversationSummary.effectiveConversationId` / `AppConversationReadRef`。
- `ChatPage` 渲染 selected conversation；它可以确认当前会话可见并触发 read ack，但不得因 summary 更新主动补拉 history。

打开会话的 first-paint 路径：

1. 从 selected conversation 读取 `effectiveConversationId`，构造 `AppConversationReadRef`。
2. 启动或确认 `watchConversationTimelinePatches(conversationId)` subscription。
3. 从当前 memory conversation window 检查是否已有 `hasRenderableContent` 消息。
4. 如果 conversation 有 renderable `lastMessageSnapshot`，可用 snapshot 预热首屏。
5. 如果内存不足，再调用 `loadConversationTimeline(conversationId)` 读取 recent local projection。
6. memory / snapshot / local projection 命中后，首屏立即可渲染，并后台触发 `syncConversationAfter(conversationId)`。
7. remote history / thread legacy adapter 只作为迁移兜底；返回消息必须先持久化到 core projection，再通过 conversation timeline load/patch 成为 UI 事实。
8. 如果 patch key 与当前 window 不一致，应触发 repair/diagnostic，不得用易漂移的 summary 或 alias 规则静默 drop core 已返回的消息。

Timeline merge 必须把“同一条本机发送消息的 durable server row”和“迟到的本地 echo/pending/failed row”视为同一展示实体：如果 mine、thread、sender、可见文本和时间窗口匹配，且其中一条已经是 `sent`，UI window 保留已发送的 server row，不再把迟到的本地失败 echo 渲染成第二个气泡。这个规则只属于 presentation 去重防线，不改变 `im-core` 作为 send/outbox/local projection 事实源的职责。

发送状态的 UI 降噪规则：core timeline row 进入 `sending` 后，气泡先不显示转圈且不预留左侧空白；同一 row 连续保持 `sending` 满 3 秒才显示 indicator。row 更新为 `sent` 或 `failed` 时 indicator widget 立即销毁。若 `sendConversationText` / `sendConversationPayload` 已返回明确终态，App 只允许用该 SDK 结果收敛当前 timeline 中已经存在、且 message id 或严格 pending match 对应的 core row；不得因此插入新的 memory-only message，也不得触发 full conversation refresh 或 remote history reconcile。

特殊边界：`dm:peer-scope:*`、legacy DID direct、old Flutter direct alias、handle 切换和 DID rotation 都必须在 `im-core` identity resolver / migration 中收敛到 canonical `conversationId`。AWiki Me 可以展示 alias/handle/DID，但不能用这些字段决定消息归属、read ack key 或 timeline patch key。旧 `ThreadRef` / raw thread history 能力只作为 compatibility adapter；App 主路径不得把 `unsupported_capability: thread-history` 暴露为可见错误。附件下载是明确的网络寻址例外：timeline 归属仍保持 canonical peer-scoped conversation，但下载请求必须使用该会话已解析的 direct peer reference，不能把不可逆的 `dm:peer-scope:*` storage thread 传给只支持 direct/group 的 attachment lookup。

会话列表、聊天头部和联系人关系行属于同一个 Profile 展示投影消费面。投影由 `im-core` 按 storage scope、owner identity 和 peer DID 持久化，App 通过 `hydrateDisplayProfiles` 仅从本地批量读取并在内存中统一发布；切换消息页、选择会话和联系人首页预览都不得触发远端 Profile 查询。用户打开完整关注/粉丝列表时，App 必须先取得关系分页，再并发刷新该页仍缺少本地投影的 peer Profile；单个失败不能阻断其他条目，成功结果由 Core 回写本地投影。用户打开头像/身份详情时仍显式刷新单个 Profile。两类更新均统一刷新会话列表、聊天头部和联系人行。展示顺序为昵称、Handle、紧凑 DID；有本地昵称时首帧必须直接显示昵称，不得出现 `Unknown → 昵称` 或 `Handle → 昵称` 闪烁。联系人首页分别保留 following/follower 的成功结果和错误状态，任何一路失败都不得清空另一路；互相关注对象同时出现在两个分区。

实时消息路径：

1. realtime notification / `sync` hint 只用于 duplicate/gap/dirty 判断和调度 SDK sync。
2. App runtime 不直接 upsert 会话列表或 chat timeline authoritative state。
3. Rust `im-core` 在 sync/realtime/backfill 成功写入 SQLite local projection 后，runtime store 发 conversation patch 和 conversation timeline patch。
4. AWiki Me 收到 patch 后按 canonical `conversationId` 更新 list/detail；alias prewarm 只可作为迁移优化或诊断，不能作为消息归属 correctness 机制。

禁止路径：

- App 不读写 global reliable checkpoint。
- App 不传 `since_event_seq`。
- App 不手写 raw `/im/rpc` `sync.*` payload。
- App 不把 realtime `sync` hint 当作 checkpoint commit。
- App 不从 conversation summary 变化反向调用 thread history sync。
- App 不用 target DID、handle、legacy direct alias 或 display thread id 自行决定消息属于哪个会话。
- App 必须用当前 renderable cache 计算本次 read ack 覆盖的 message watermark；core 负责校验 watermark、提交本地 read-state projection，并处理远端 ack / pending ack。

旧路径退场清单：

- `ThreadRef` history、`watchThreadPatches(ThreadRef)`、`repairThreadStore(ThreadRef)`、`syncThreadAfter(ThreadRef)` 只允许 CLI、legacy adapter、migration 或低层诊断使用；AWiki Me display correctness 必须走 conversationId-first API。
- target DID / handle / legacy direct alias / old Flutter sorted direct id 只允许作为 core resolver 输入或诊断字段；AWiki Me 不得用它们重新推导 canonical direct key。
- alias prewarm 只允许作为迁移期性能辅助，不得作为消息归属、patch key、read ack key 或 send route 的判断依据。
- UI renderable cache 只能决定当前窗口是否有内容可展示，不得计算默认 read watermark 或过滤 core 已经归属到当前 conversation 的 committed message。
- memory pending、local thread move、本地 upsert conversation row 只能作为短生命周期 UI 状态，不得替代 core durable send/outbox row、conversation patch 或 timeline patch。
- generic SDK `retryMessage(messageId)` 当前仍是 unsupported；AWiki Me 重试文本、payload 和附件时必须用 `AppConversationReadRef` 重新调用 `sendConversationText`、`sendConversationPayload` 或 `sendConversationAttachment`，并保留稳定 `clientMessageId` / `idempotencyKey`。

诊断事件：

- `message_sync.delta`
- `message_sync.thread_after` / `message_sync.conversation_after`
- `chat.open.first_paint`
- `chat.local_history.*`
- `chat.conversation_timeline.*`
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
- `tests/unit/chat_page_test.dart`：验证聊天窗口渲染、read ack 边界、header 行为、sending indicator 的 3 秒延迟与明确终态清理等关键 widget 行为。
- `tests/unit/chat_provider_open_test.dart`：验证打开会话 local-first conversation timeline、conversation-after/remote fallback、conversation timeline patch version gap repair、stream closed repair/re-subscribe、read ack、文本 / payload / 附件 send intent 和附件 retry 都按 `effectiveConversationId` / `AppConversationReadRef` 走主路径。
  - 其中 `dm:peer-scope:*`、legacy direct、old Flutter direct alias 和 handle/DID rotation 必须由 core/SDK canonical identity 收敛；App 不因 raw thread history unsupported 而把错误暴露成可见 UI 报错。
- `tests/unit/app_runtime_notification_test.dart`：验证 realtime notification / sync hint 只调度 SDK sync、dirty/gap/repair 和通知 / runtime 分发边界，不直接写 list/detail authoritative state。
- `tests/unit/conversation_list_provider_test.dart`：验证 base row 先于 enrichment 展示、patch upsert/reorder/repair、clear 后不回填、snapshot bootstrap guard、local hidden waterline 不被旧 patch 冲破、locally-started 空会话跨 refresh/reset 保留并在 materialize/delete 时释放、verified full-handle start 在 DID rotation 期间与迟到 canonical row 收敛且不误合并裸 Handle / 第二个 peer-scoped row、所有 recents state 发布入口都应用 read presentation waterline、临时 0 unread 不清新消息、旧 0 unread 不清更新消息、read watermark 覆盖的迟到 unread 不重新出现，以及已读/no-op read ack 不重复 emit。
- `tests/e2e/flutter/app/app_smoke_test.dart`：验证真实 App UI 从完整 Handle 发起空私聊后，即使迟到 core row 携带不同 DID/canonical id，recents 和 selected conversation 也在首条消息前保持单行 canonical 状态。
- `tests/e2e/flutter/desktop_cli_peer/flows/direct_message_flow.dart`：direct App + CLI peer E2E 在 CLI -> App 消息后，先等 conversation refresh 返回 `ConversationSummary`，再验证 list latest message 能在 `effectiveConversationId` 对应的 canonical timeline 中唯一出现。
- `tests/e2e/flutter/desktop_cli_peer/flows/contact_flow.dart`：`CONTACT-MSG-E2E-001` 通过可见联系人行打开 Direct，验证一次发送只对应一个 canonical message/Core summary/UI row/Product overlay，并覆盖 restart 和 unread `+1 -> 0` 闭环。
- `tests/e2e/flutter/desktop_cli_peer/flows/attachment_flow.dart`：App -> CLI 附件发送使用 `AppConversationReadRef.fromConversationId(conversation.effectiveConversationId)` / SDK conversation attachment API，不再通过 legacy target/thread API 决定发送归属。
- `tests/e2e/flutter/desktop_cli_peer/support/polling.dart`：`_waitForAppConversationLatestInTimeline` 要求 messaging 实现 `ConversationTimelineMessagingService`，使用 `AppConversationReadRef.fromConversationId(conversation.effectiveConversationId)` 调用 `loadConversationTimeline`，并验证 `lastMessageSnapshot` id 也属于同一 timeline。

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
