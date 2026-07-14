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
6. `ConversationListProvider` 只发布 recents、unread 和 badge 状态；base row 来自 core conversation read model，App 只叠加 product overlay 和短生命周期 read presentation waterline。发布状态是一次替换的 `entitiesById + orderedIds + loadState + version`，不允许 Map、排序和 patch version 分帧更新。
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
| canonical `conversationId` / identity aliases | Rust `im-core` / SDK DTO | resolver、message upsert、conversation projection migration | App 只消费 `ConversationIdentity` / `ConversationSummary.conversationId`，不自行生成 direct canonical key |
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
| Direct `customTitle`、`avatarSeed` | `awiki-me` `ProductLocalStore` | `ProductLocalStore.upsertConversationOverlay` | Direct `customTitle` 只投影为 Persona 级本地备注，不再改写 Core `displayName`；`avatarSeed` 仍为 App overlay |
| 本地临时隐藏水位 | `ConversationListController` | `deleteFromRecents` 成功前后维护 memory waterline | snapshot、refresh 和 patch apply 前过滤，旧 patch 不能重新插入 |
| 用户显式打开的空会话 | Rust `im-core` conversation registry | identity flow 先 `resolve/open`，再 `ensureConversation(conversationId)` | Core list/snapshot/patch 返回 committed row；App 不保留 locally-started bridge，也不构造 fake summary |
| recents read presentation waterline | `ConversationListController` presentation memory | refresh / fast-local / patch / repair / visible message watermark / read ack | 发布 recents 前统一投影：latest message watermark 只前进，read watermark 只前进；summary-only 更新不能清 unread；read watermark 覆盖的旧 unread 不能重新出现；旧的 0 unread 不能清掉更新消息；可见状态只在严格 canonical conversation 内推进 |
| Agent display / lifecycle projection | `awiki-me` application service | `AgentInventoryPort` / agent control projection | `ImCoreConversationService._applyAgentLifecycleProjection` |
| group display name / avatar | `awiki-me` group application/provider | group summary refresh | Widget 按相同 canonical `conversationId` 组合；不得回写 `ConversationSummary` |
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
- `chatMessageFromSnapshot(core.ConversationSnapshotMessage, ownerDid: ..., conversationId: ...)`
- `conversationFromCore(...)`
- `conversationFromSnapshot(...)`
- `realtimeUpdateFromCore(...)`

映射规则：

| 输入事实 | App 字段 / 行为 |
|---|---|
| required `conversationId` | 直接写入 App message/conversation projection；不得回退 `conversationIdentity` 或 `threadId` |
| `message.id` | `ChatMessage.localId` 和 `remoteId` |
| SDK thread kind / group / direct peer | 规范化为 App `threadId`、`groupId`、`receiverDid` |
| `message.sender` + `ownerDid` + direction | `ChatMessage.isMine` |
| `body.text` | 普通文本 fallback，写入 `ChatMessage.content` |
| P9 mention payload JSON | `ChatMessage.content = payload.text`，`mentions = parsed mentions`，`payloadJson` 保留原文，`originalType = application/json` |
| attachment manifest | `ChatMessage.attachment`；caption 优先成为 `content` / preview 文本 |
| `metadata.contentType` / `body.kind` | `ChatMessage.originalType` |
| encrypted content type | `ChatMessage.isEncrypted` |
| server sequence | `ChatMessage.serverSequence`，用于排序、thread-after 和 first-paint 判断 |

SDK conversation list/snapshot 只有在 `resolutionState == resolved` 且 Direct
具有 `peerPersonaId`、Group 具有 `canonicalGroupDid` 时才能进入 App mapper。
缺少任一 canonical identity 的行在 adapter 边界 fail closed，不再由 UI 用 DID、
Handle 或 thread 进行猜测合并。snapshot message 自身不再独立推断 conversation，
而是继承所属 snapshot item 的 required `conversationId`。

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

Composer 的附件来源仍统一进入 `AttachmentDraft`：文件选择、拖拽、剪贴板图片和 macOS `/usr/sbin/screencapture -i -x` 交互式截图都只负责暂存，用户点击发送后才调用 canonical attachment send API。截图期间主窗口始终保持可见，不再根据 Shift 或 native 全局 modifier 隐藏 App。App 在启动系统截图前必须通过 native `CGPreflightScreenCaptureAccess` 检查权限，单进程最多调用一次 `CGRequestScreenCaptureAccess`；未授权时禁止继续执行 `screencapture`，避免把只有桌面的错误图片当作有效附件。Debug App 必须使用稳定 Apple Development designated requirement，不能用随构建变化的 ad-hoc CDHash。Emoji 面板只修改当前 `TextEditingValue` 的选区并沿用 draft mention range 转换，不引入新的消息类型。

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

“发起新消息”与“打开群聊”采用同一 committed lifecycle：Direct 入口先完成 SDK directory resolution并取得 canonical `conversationId`，Group 入口使用 SDK 返回的 Group `conversationId`；随后先调用 Core `ensureConversation` 提交 `conversation_registry` 存在性，再按该 ID 选择和导航。Core list/snapshot/patch/repair 是空会话存在性的唯一事实源，首条消息不再是创建 recents 的条件；ensure 失败时不发布 ghost row。完整 Handle 解析缺失/退化、Direct route 不匹配或 Group membership 非 active 时 fail closed，不写 overlay。App 不能创建 `dm:<DID>` / `group:*` canonical ID、fake `ConversationSummary`、fake message、fake unread或第二套 durable conversation store。

release/0710 的 legacy DID/thread/Handle alias 只允许由 Core upgrade、alias resolver 和 App overlay migration 处理。业务 Store 启动后，App 不再保留 locally-started identity bridge，也不按 DID、Handle、thread、display name 或头像猜测合并；两个不同 `conversationId` 即使 target 相同也保持为不同记录并暴露 Core invariant 问题，不能由 UI 静默修正。selected state 只保存 canonical ID，并从当前 ConversationStore 同步解析实体。

0710 迁移保留下来的 `active + legacy_unresolved` registry row 仍可进入最近会话，以保全历史入口；App 必须保留其 resolution state，并继续只按非空 `conversationId` 建索引，不得根据相同 DID、Handle 或显示名合并。`blocked_conflict` 不进入普通列表，resolved Direct/Group 缺少 Persona/Group canonical identity 时同样 fail closed。新入站 unresolved backlog 仍由 Core 隔离，不属于这一兼容显示规则。

打开会话后，text/payload/attachment 首发、重试和 read/sync 都传入同一 canonical `AppConversationReadRef`；Core 用 directory 解析时写入的 owner-scoped Direct route 寻址 current DID。App 不得把 peer-scope 会话降级为 `dm:<targetDid>` write alias。`ChatThreadsController` 只从 canonical `conversationId` timeline、conversation timeline patch 或 committed projection repair 中获得更新消息。列表 preview 的 authoritative base 仍来自 `im-core` conversation summary projection；legacy alias、remote history best-effort page 或 realtime hint 都不能成为第二套 preview 真相。`ConversationListProvider` 是 recents state 的唯一发布边界，snapshot、fast-local、patch reset/upsert/remove/reorder、repair 和 read ack 都必须在发布前应用同一套 read presentation waterline；Profile/Group 展示信息在 Widget/View Provider 中组合，不回写 base summary。这个 waterline 只接受 latest message watermark 前进或 read watermark 前进；summary-only 更新不能提前清 unread，read watermark 覆盖的迟到 unread 不能重新出现，旧的 0 unread 不能清掉更新消息。真正的 read state 必须通过带 message watermark 的 `markConversationRead(AppConversationReadRef, watermark)` 提交。

## 10. Timeline 和 Local-First 打开路径

Chat presentation 是单向的：

- `ConversationListProvider` 负责 recents / unread / badge 状态，base row 来自 core conversation read model，App 只叠加 product overlay 和 read presentation waterline。
- `ChatThreadsProvider` / `ChatThreadsController` 负责 conversation timeline window、merge、sort、repair 和 read ack 调度，主 key 是 `ConversationSummary.conversationId` / `AppConversationReadRef`。
- `ChatPage` 渲染 selected conversation；它可以确认当前会话可见并触发 read ack，但不得因 summary 更新主动补拉 history。

打开会话的 first-paint 路径：

1. 从 selected conversation ID state 读取 `conversationId`，构造 `AppConversationReadRef`。
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

会话列表、聊天头部、联系人、群成员和群消息发送人属于同一个 Profile 展示投影消费面。持久投影由 `im-core` 按 storage scope、owner identity 和 `peerPersonaId` 隔离；当前 DID 只是 Persona 的 route。App `PeerDisplayProfileStore` 以 Persona 为主键，DID-only unresolved 项进入独立 bucket，不能把一个 DID 查询结果复制成另一个身份的 alias。切换消息页、选择会话和联系人首页预览都不得触发远端 Profile 查询；完整关注/粉丝页和用户主动打开头像时才刷新远端资料，单个失败保留旧缓存且不能阻断其他条目。展示顺序为本地备注、昵称、完整 Handle、紧凑 DID、unknown；有本地昵称时首帧必须直接显示昵称，不得出现 `Unknown → 昵称` 或 `Handle → 昵称` 闪烁。群资料同样按 canonical `conversationId` 在 View 层组合，不改写 Core conversation projection；群资料刷新、添加成员和移除成员回调只能更新 `groupId` 等展示元数据，必须保留已选会话原有的 `conversationId`，不得用 `groupId` 重新拼接 `group:*`。

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

1. 通过 `ConversationCorePort.ensureConversation` 提交显式打开的Direct/Group存在性，并从Core registry-backed list、snapshot或patch读取base row。
2. 使用 `ProductLocalStore` 读取 overlay。
3. 过滤隐藏会话。隐藏规则使用 overlay 的 `updatedAt` 或 provider memory waterline，只有 `lastMessageAt` 晚于隐藏时间的新消息才可以恢复会话。
4. Direct `customTitle` 只作为 `peerLocalNote` 输入统一 Peer View Provider，不改写 conversation base `displayName`；再应用 `avatarSeed`、Agent lifecycle 和 group display enrichment。
5. 输出 `ConversationSummary` 给 presentation provider。

`ConversationListController` 可以维护短生命周期 UI waterline，但只能用于防止 optimistic hide 后的旧 snapshot/patch 回填。它不是持久事实源，`clear()`、session switch 和 provider dispose 必须清理它。

`ConversationListState` 是 normalized store：`entitiesById` 只以 required canonical
`conversationId` 为 key，`orderedIds` 只保存展示顺序，`version` 与
reset/upsert/remove/reorder 在同一次 state assignment 中前进。空数据必须与
`initializing/stale/error` 正交；Core 加载失败显示可重试错误，不得伪装成真实空列表。

Peer 名称只由纯 `PeerDisplayNameResolver` 和 `peerDisplayNameProvider`
组合，固定优先级为“Persona 本地备注 > 当前昵称 > 完整 Handle >
历史 sender snapshot（仅未解析/Profile 缺失）> 紧凑 DID > unknown”。
会话列表、聊天页头、联系人、群成员、群消息发送人和用户详情都消费
同一 ID-scoped provider；Widget 不得自己重写 DID/Handle 回退。会话本地 bundle
与 cached Persona profile 完成后才发布首个内容帧，避免
`Unknown/Handle -> 昵称` 闪烁。

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
- `tests/unit/chat_provider_open_test.dart`：验证打开会话 local-first conversation timeline、conversation-after/remote fallback、conversation timeline patch version gap repair、stream closed repair/re-subscribe、read ack、文本 / payload / 附件 send intent 和附件 retry 都按 `conversationId` / `AppConversationReadRef` 走主路径。
  - 其中 `dm:peer-scope:*`、legacy direct、old Flutter direct alias 和 handle/DID rotation 必须由 core/SDK canonical identity 收敛；App 不因 raw thread history unsupported 而把错误暴露成可见 UI 报错。
- `tests/unit/app_runtime_notification_test.dart`：验证 realtime notification / sync hint 只调度 SDK sync、dirty/gap/repair 和通知 / runtime 分发边界，不直接写 list/detail authoritative state。
- `tests/unit/conversation_list_provider_test.dart`：验证 base row 先于 enrichment 展示、patch upsert/remove/reorder/repair 全部按 canonical ID、clear 后不回填、snapshot bootstrap guard、local hidden waterline 不被旧 patch 冲破、不同 canonical ID 不因 DID/Handle 相同而合并、selected state 仅保存 ID，以及所有 recents 发布入口应用同一 read presentation waterline。
- `tests/e2e/flutter/app/app_smoke_test.dart`：验证真实 App UI 从完整 Handle 发起空私聊后，Core committed row 在首条消息前可见，recents 与 selected ID 始终指向同一个 canonical conversation。
- `tests/e2e/flutter/desktop_cli_peer/flows/direct_message_flow.dart`：direct App + CLI peer E2E 在 CLI -> App 消息后，先等 conversation refresh 返回 `ConversationSummary`，再验证 list latest message 能在 `conversationId` 对应的 canonical timeline 中唯一出现。
- `tests/e2e/flutter/desktop_cli_peer/flows/contact_flow.dart`：`CONTACT-MSG-E2E-001` 通过可见联系人行打开 Direct，验证一次发送只对应一个 canonical message/Core summary/UI row/Product overlay，并覆盖 restart 和 unread `+1 -> 0` 闭环。
- `tests/e2e/flutter/desktop_cli_peer/flows/attachment_flow.dart`：App -> CLI 附件发送使用 `AppConversationReadRef.fromConversationId(conversation.conversationId)` / SDK conversation attachment API，不再通过 legacy target/thread API 决定发送归属。
- `tests/e2e/flutter/desktop_cli_peer/support/polling.dart`：`_waitForAppConversationLatestInTimeline` 要求 messaging 实现 `ConversationTimelineMessagingService`，使用 `AppConversationReadRef.fromConversationId(conversation.conversationId)` 调用 `loadConversationTimeline`，并验证 `lastMessageSnapshot` id 也属于同一 timeline。

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

release/0710 到 canonical schema 的启动顺序固定为：Vault 解锁 → Core
检测/升级 → 读取 Core owner-scoped alias mapping → ProductLocalStore 备份并在单一
SQLite transaction 内迁移 overlay/draft 与 journal → 创建业务 Store。Core 已完成但
App 在 overlay cutover 前崩溃时，下一次启动必须重新读取 mapping 并幂等续跑；不得
启动半新半旧的 Conversation/Profile/Group Store，也不得通过清库、OTP 或 Handle
恢复绕过。ProductLocalStore 的备份使用 `VACUUM INTO` 生成一致 SQLite snapshot，
legacy/canonical 行冲突按最新 `updatedAt`、同时间 canonical 优先的确定性规则合并。
ProductLocalStore 自身需要 schema upgrade 时，也必须先用未版本升级的连接生成并通过
`PRAGMA integrity_check` 验证同一份 snapshot，再执行 `onUpgrade`；不能先回填
`conversation_id` 后才声称该文件是 pre-migration backup。
只有 Core inspection 明确返回 `required` 时，启动 shell 才显示“安全升级本地数据”；
Core cutover 后继续显示 overlay 收尾阶段，完成前不创建业务 Store。NotRequired 启动
保持普通 loading，不制造升级提示。失败页只展示稳定的脱敏 diagnostic code，并提供
复制诊断、重试和退出；不得把异常正文、SQLite path、DID、消息内容或 SecretVault
细节直接渲染到 UI，也不得自动清库或重新走 OTP/Handle recovery。

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
