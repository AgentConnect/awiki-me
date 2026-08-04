# Conversation Presentation And Message Rendering Ownership

本文档是 AWiki Me 会话展示、消息可见性、消息渲染分层和首屏展示链路的当前唯一入口文档。它覆盖 conversation presentation projection、message timeline、SDK DTO 到 App domain model 的映射、普通文本 / Markdown / mention / attachment / control payload 的展示规则，以及 local-first 打开会话的职责边界。

历史 plan 文档只作为执行台账和决策背景保留；如果历史 plan 与本文档或当前代码不一致，以本文档和当前代码为准。已过时且会误导执行的旧 SDK migration plan 不再保留在 `docs/` 主路径下。

## 1. 当前结论

`im-core` / Flutter SDK 是 message、conversation identity、canonical `conversationId` read model、read-state、send/outbox、sync/realtime/backfill committed projection 的事实源。AWiki Me 只拥有 product overlay、User Service 权威账号域的本地展示快照、read presentation waterline、renderability、draft/scroll/loading、短生命周期 UI window 和 widget composition。账号域快照是可丢弃 cache，不是消息、会话、群或 Agent 控制事件的第二事实源。

核心边界：

1. Rust `im-core` 是 message、thread、group、conversation、read-state、send/outbox 和 committed local projection 的主数据源。
2. Flutter SDK 暴露 core-only DTO，例如 `core.Message`、`core.ConversationSnapshotItem`、conversation identity、conversation timeline patch 和 realtime event。
3. `awiki-me/lib/src/data/im_core/` 是 SDK DTO 到 App domain model 的唯一生产映射层。
4. `awiki-me` presentation 层只消费 `ChatMessage`、`ConversationSummary`、`RealtimeUpdate` 等 App domain model，不直接消费 SDK DTO。
5. `ChatMessage.hasRenderableContent` 是普通聊天 timeline 是否展示消息气泡的核心 gate。
6. `ConversationListProvider` 只发布 recents、unread 和 badge 状态；base row 来自 core conversation read model，App 只叠加 product overlay 和短生命周期 read presentation waterline。发布状态是一次替换的 `entitiesById + orderedIds + loadState + version`，不允许 Map、排序和 patch version 分帧更新。
7. `ChatThreadsProvider` / `ChatThreadsController` 只拥有当前 `conversationId` 的 UI window 和短生命周期 read intent drain，不拥有消息归属、durable read watermark、send correctness 或 realtime correctness。
8. `ChatPage` 只渲染当前 selected conversation 并声明可见性；持久 read intent 由 `ChatThreadsController` 根据可见状态建立，不能依赖 Widget 的一次性 post-frame 回调。`ChatPage` 不得因为 conversation summary 变化反向拉取 history。
9. 所有 App 消息同步、timeline window、patch、read 和 send presentation 工作都绑定当前 `SessionEpoch(ownerDid, stableIdentityKey, generation)`；登出、清空会话或 A→B 身份替换必须推进 generation，并在旧 Future 完成前先使其失效。同一身份只刷新 JWT、昵称等可变字段时不推进 generation。
10. 普通消息 v2 同步对所有已认证账号和有效设备默认开启；App 不维护账号/设备灰度名单。
   `AWIKI_SYNC_V2_READ=false` 仅是全局应急回滚，不能改变 Core owner/cursor 语义，也不影响
   独立默认关闭的 P5/P6 E2EE 开关。
11. WebSocket 和 Android remote Push 都只是 hint-only sync trigger。两者都只能调度
    `MessageSyncCoordinator`；该协调器是 Core commit、conversation/timeline projection、
    normal message notification 和 Coding Agent notification 去重的唯一 owner。
12. Android Push 的后台/锁屏展示仍由 EMAS `NOTICE` 独占；只有 native 确认 Activity
    resumed、窗口有焦点且 opaque target 与当前 SessionEpoch owner 匹配时，ordinary direct/group
    `NOTICE` 才转成 in-app callback。该 callback 只触发 committed sync；App 在前台时全局静默，
    只更新 timeline、recents、排序和未读状态（离底部时复用聊天页“新消息”入口）。
    Push acknowledgement 和通知打开导航必须同时通过 SessionEpoch 与 tenant fence，旧身份或旧
    租户的异步完成不得确认事件或改变当前选择。

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
| conversation patch stream | Rust `im-core` runtime store | committed sync/local write invalidation；patch 保留 `ownerIdentityId` | `ConversationCorePort.watchConversationPatches`；App 用完整 session/account/auth generation fence 消费 |
| conversation timeline patch stream | Rust `im-core` runtime store | committed local message projection、sync、realtime incoming；patch 保留 `ownerIdentityId` | `ConversationTimelineMessageCorePort.watchConversationTimelinePatches` / `ChatThreadsController`；同 DID 换 generation 后旧 patch 失效 |
| unread count、unread mention、read-state 展示事实 | Rust `im-core` local state 和 read-state API | `markConversationRead` / sync apply / local projection | App 只消费 projected count，不拥有 checkpoint 或 read watermark 事实 |
| text / payload / attachment send/outbox/local echo | Rust `im-core` messages / attachments projection + send state | `sendConversationText` / `sendConversationPayload` / `sendConversationAttachment` / retry result | App 发送 intent 并渲染 core timeline row 的 pending/failed/sent；sending row 连续可见满 3 秒后才显示转圈，明确 send result 只可收敛已由 core patch 暴露的 row；附件可保留本地文件 preview 作为短生命周期 UI 状态，但不得用 memory pending、thread move 或本地 upsert conversation row 决定 correctness |
| realtime / backfill | Rust `im-core` sync/realtime committed projection | realtime hint 调度 `syncDelta`，conversation-after 补新，projection commit 后 patch | App 不从 realtime typed event 直接写 list/timeline truth；只消费 core patch/read model 并在 gap 时 repair |
| remote Push hint | Android native EMAS transport + `RemotePushMessageSyncCoordinator` | message/notification/open callback、activation、resume、registration refresh | 只以 `remote_push` 原因请求同一个 `MessageSyncCoordinator`；payload 不写 list/timeline，不携带 message truth |
| Core commit / projection / notification dedupe | `MessageSyncCoordinator` | WebSocket、remote Push、startup、resume、repair 等可靠触发合并后调用 Core sync | Core commit 后统一刷新 recents、Join inbox、timeline，并以 committed message identity 执行普通消息与 Coding Agent 通知去重 |
| remote Push presentation | Android native EMAS receiver + `MessageSyncCoordinator` | native foreground/target fence、provider callback kind、committed conversation visibility | 后台/锁屏由 EMAS `NOTICE` 展示；匹配账号的前台 ordinary notice 转 in-app callback 并静默同步，不显示 Toast、Banner 或系统通知 |
| remote Push acknowledgement / navigation | `RemotePushMessageSyncCoordinator` | Core sync receipt、opaque `mid`、future `exp`、canonical committed conversation | 仅在同 SessionEpoch/tenant 下同步、刷新和路由成功后确认；stale、offline、失败或不安全 hint 保留/降级且不能跨身份导航 |
| SDK message DTO | Flutter SDK / Rust `im-core` | SDK `messages`、`groups`、`realtime` API | 只允许 `awiki-me/lib/src/data/im_core/` 生产路径直接消费 |
| SDK DTO -> App message projection | `awiki-me` data mapper | `AwikiImCoreMappers.chatMessageFromCore`、`chatMessageFromSnapshot` | `ChatMessage` |
| message renderability | `awiki-me` domain model | `ChatMessage.hasRenderableContent` | adapters、providers、timeline、preview 回填共同使用 |
| message timeline window | `ChatThreadsProvider` / `ChatThreadsController` | `openConversation`、conversation timeline load、conversation timeline patch、conversation-after、patch gap / stream repair | `ChatPage` 只通过 `chatThreadProvider` 渲染当前 selected conversation window |
| App message session generation | `SessionProvider` / `SessionEpoch` | active identity set/clear/replacement；同身份 auth refresh 保持 generation | sync coordinator、chat history/patch/repair/read/send completion 在每次异步工作开始时 capture，完成时校验；旧 generation 不得写当前 state |
| text / Markdown / mention / attachment widget render | `awiki-me` presentation widgets | `ChatMessage` 字段和当前 bubble context | `chat/parts/chat_message_part.dart` |
| conversation preview | Rust `im-core` conversation summary + `awiki-me` mapper/overlay | SDK snapshot、conversation patch、latest renderable core message projection | `ConversationListProvider`、conversation workspace |
| control payload 会话预览可见性 | `awiki-me` mapper / realtime projection | SDK message 的 `body.text` + `payloadJson` | 只允许带显式可见文本的 control payload 更新 recents 预览；payload-only control 继续隐藏 |
| `hidden`、`pinned`、`muted` | `awiki-me` `ProductLocalStore` | `ConversationService.setThreadHidden`、`hideConversationFromRecents`、`restoreConversationToRecents` | `ImCoreConversationService` 加载 overlay 后过滤、排序和展示 |
| Direct `customTitle`、`avatarSeed` | `awiki-me` `ProductLocalStore` | `ProductLocalStore.upsertConversationOverlay` | Direct `customTitle` 只投影为 Persona 级本地备注，不再改写 Core `displayName`；`avatarSeed` 仍为 App overlay |
| 当前账号 Agent inventory topology | User Service 权威、AWiki Me `ProductLocalStore` v4 展示 cache | 版本化完整快照；App 只通过 `replaceAgentInventorySnapshot` 单事务替换 | Agent 页面；topology 不覆盖独立 status，也不替代 Core committed Agent control projection |
| 当前账号 Agent latest status | User Service 权威、AWiki Me `ProductLocalStore` v4 展示 cache | 独立 status version；`replaceAgentStatusSnapshot` 单事务替换 | Agent 页面将 status 按 `agentDid` 叠加到 topology；status 不能改变 `activeState` 或重新激活 Agent |
| 当前账号 Profile / Device Registry | User Service 权威、AWiki Me `ProductLocalStore` v4 展示 cache | `replaceProfileSnapshot` / `replaceDeviceRegistrySnapshot` 完整快照 + 单调版本 | 当前账号资料和设备管理 UI；不用于推断消息 owner、协议设备或身份绑定 |
| 本地临时隐藏水位 | `ConversationListController` | `deleteFromRecents` 成功前后维护 memory waterline | snapshot、refresh 和 patch apply 前过滤，旧 patch 不能重新插入 |
| 用户显式打开的空会话 | Rust `im-core` conversation registry | identity flow 先 `resolve/open`，再 `ensureConversation(conversationId)` | Core list/snapshot/patch 返回 committed row；App 不保留 locally-started bridge，也不构造 fake summary |
| recents read presentation waterline | `ConversationListController` presentation memory | refresh / fast-local / patch / repair / visible message watermark / read ack | 发布 recents 前统一投影：latest message watermark 只前进，read watermark 只前进；summary-only 更新不能清 unread；read watermark 覆盖的旧 unread 不能重新出现；旧的 0 unread 不能清掉更新消息；可见状态只在严格 canonical conversation 内推进 |
| Agent display / lifecycle projection | `awiki-me` application service | `AgentInventoryPort` / agent control projection | `ImCoreConversationService._applyAgentLifecycleProjection` |
| group display name / avatar | `awiki-me` group application/provider | group summary refresh | Widget 按相同 canonical `conversationId` 组合；不得回写 `ConversationSummary` |
| 可见会话 read intent | `ChatThreadsController` 可见状态 + 单调串行 read-intent drain | `ChatPage` 只声明挂载/隐藏；当前可见 summary/timeline 更新、用户回到底部 | 可见且有未读时立即建立 intent；history/lifecycle 未就绪只延后 drain，不丢 intent。每个 canonical conversation 同时最多一个 `markConversationRead(AppConversationReadRef, watermark)`；更高 watermark 单调合并并只前进。以 Core `effectiveWatermark` 确认本地持久提交；`pendingRemoteAck` 表示 local-first 已成功 |

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
| server sequence | `ChatMessage.serverSequence`，用于排序、thread-after 和 first-paint 判断；两条消息都具备 sequence 时它优先于 `createdAt`，混合/legacy row 才回退时间 |

`sendConversation*`、conversation timeline load/repair 和 timeline patch stream
在 adapter 边界还会校验返回的每条消息与 patch 的 `conversationId` 必须非空且
严格等于请求的 canonical ID；缺失或串入其他会话时直接 fail closed，不允许用
`threadId`、DID 或 patch 中另一条消息补成当前会话。

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

内联图片统一使用附件卡片外框；没有 caption 时只省略文本和分隔线，不允许退化为直接叠在聊天背景上的透明裸图。图片解码后的像素宽高必须先按当前屏幕 device pixel ratio 换算为自然逻辑尺寸，在 `compact 300 / desktop 320` 的媒体上限和实际父约束内等比缩小，不得为了占满上限而无条件放大。只有图片最长边小于 `120` 逻辑像素时才允许等比补到最小预览尺寸；极端长宽比继续保留完整内容，并由至少 `44×44` 的媒体外框保证可操作性。尺寸尚未探测完成时使用 `240×180` 的稳定占位。带 caption 的附件宽度由 caption 与媒体各自的自然宽度取较大值，分隔线只跟随最终宽度，不得参与或强制扩大宽度。

图片与 caption 的操作所有权必须分离：桌面端在图片命中区右键打开指针位置菜单，compact 端在图片命中区长按打开 `CompactActionSheet`，两端都只提供复制图片和另存为；单击图片仍沿用原附件预览/打开链路。复制和另存为只能读取 `AttachmentPreviewService` 已解析出的本地预览资源，不允许绕过 core/cache 根据 object URI 直接联网。caption 不进入图片菜单，只由自己的 `SelectionArea` 提供文本选择和复制；图片区域不得处在 caption 的文本选择手势树中。

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

Agent / Personal Agent control payload 是控制面事件，不是普通聊天消息。默认规则：

1. `ChatMessage.hasRenderableContent` 对 agent control payload 返回 false。
2. payload-only control 不进入普通聊天 timeline，也不触发普通消息通知。
3. control payload 带有显式 `body.text` 时，mapper 允许它更新 conversation preview，避免详情页可见状态文本和 recents “暂无消息”不一致。
4. control payload 的结构化语义交给 Agent control projection、runtime status、Personal Agent cards 或后续 application service 处理。
5. 不允许把 control payload raw JSON 作为普通聊天文案展示。

`realtimeUpdateFromCore` 对 control payload 的处理也遵守该边界：有可见 preview 才返回 conversation update；结构化 payload 放在 `RealtimeUpdate.agentControlPayload`，普通 `message` 为空。

### 8.1 Coding Agent 终态通知

`awiki.agent.status.v1` 的 Coding Agent 终态属于短生命周期通知投影，不是 conversation 或 timeline truth：

1. App 保留并继续投影 `pending / running / finished / failed` 运行状态；仅当 `state=finished` 且 `business_outcome` 严格属于 `completed / blocked / action_required` 时生成业务终态通知。`state=failed` 且没有业务 outcome 表示真实运行失败。畸形、未知、超限或含敏感摘要的 payload fail closed，不猜测结果。
2. `running / queued` 不通知。Coding Agent 普通消息和终态在 App 前台保持安静；后台终态调用既有本地系统通知。文案经 `AppMessage` 和现有 localization getter 解析，不显示 daemon 诊断。
3. 进程内以 `run_id + terminal kind` 去重，而不是只相信可能变化的 realtime delivery id；终态 key、终态 message ID 与普通 message ID 分别使用有序上限 512 / 512 / 256 的 recent ledger，并在身份清理时清空。稳定 `event_id` 仍是 transport replay 的协议幂等键；App ledger 只负责有界的进程内 replay protection，不替代 transport 持久幂等。
4. daemon 提供的 `final_message_id` 与普通消息的 logical/remote/local id 双向关联。旧 realtime reader 与 V2 Core committed-sync notification dispatcher 共享同一个 session-scoped 去重器：终态先到时立即显示语义终态并抑制随后匹配的普通最终回复通知；已由 canonical Agent inventory 识别的 Runtime Agent 普通消息先到时，App 最多暂存 64 个通知意图并等待 1 秒，窗口内匹配终态会取消普通通知并由 `completed / blocked / action_required` 语义通知胜出。窗口到期则释放普通通知，并抑制之后才到的匹配终态，保证只响一次；超过容量时最旧意图立即按普通通知释放，不丢通知。普通非 Runtime Agent 消息保持立即通知，Runtime Agent 非终态消息在 1 秒后保持原通知内容与前后台策略。
5. control payload 继续交给既有 Agent/Chat projection，但终态通知器不写 conversation list、timeline 或 message truth。普通 status 以及 payload-only control 仍不进入聊天气泡。
6. 本小节的 Coding Agent 语义终态仍只保证 App 在线或进程仍存活时的 realtime 加本地通知。
   Android direct-message Push 的 installation、同步与展示边界见下一节；它不把 daemon 终态
   payload 当作 Push 携带的 message truth，也不宣称 Coding Agent 终态已经具备真离线 Push。

通用系统通知同样不是聊天消息。Core 只有在完成 P3 envelope、service DID/proof、
audience、expiry 和业务 payload 验证并提交本地投影后，才向 App 发出
`system_notification_changed`。`AwikiImCoreMappers` 将它映射为纯同步信号：
`message`、`conversationHint`、`conversation` 和 `agentControlPayload` 必须为空。
`AppRuntimeController` 只安排一次 reliable message sync；sync 成功后，设备模块才能刷新
Core 的 typed local Join inbox。通知自带的 title/body、payload JSON 或 sender 不得生成
普通 banner、recents 行、timeline 气泡或 App 自己维护的通知业务状态。

### 8.2 Android remote Push

Android EMAS message/notification/open callback 与 WebSocket 一样，只表示本地 Core
projection 可能变脏。`RemotePushMessageSyncCoordinator` 将事件串行合并，并通过
`MessageSyncCoordinator.requestSync(reason: remote_push)` 请求同一条 Core committed-sync
路径。它不解析 Push title/body 来生成 `ChatMessage`，也不直接 upsert recents 或 timeline。

`MessageSyncCoordinator` 仍是唯一的 Core commit、conversation/Join/timeline 刷新和
notification dedupe owner。native receiver 在 `showNotificationNow` 之前只用三项安全事实做
fail-open 决策：Activity resumed、窗口有焦点、当前 session 派生的 `target_*` 与 envelope `ts`
相等；类型还必须是 ordinary `direct_message` / `group_message`。任一事实缺失、失焦、账号不匹配
或类型不支持时都返回 provider presentation，继续由 EMAS `NOTICE` 展示。这里不读取 WebSocket
在线状态，也不把 raw DID、conversation ID 或消息正文写入 native presentation state。

被 native 拦截的 notice 通过 `notification_received_in_app` 进入同一 committed-sync 路径；
`message_received` 也按 App presentation required 处理。已由 provider 展示的
`notification_received` / `notification_opened` 继续抑制 App duplicate；混合 batch 只要包含
provider-presented event 就选择抑制。该 policy 在 active/queued coalescing 和 automatic retry
中按 OR 传播，不跳过 normal message ledger、Runtime Agent final-message deduper 或 committed
projection。

前台 App presentation 全局静默：无论用户是否位于消息所属会话，都不显示 Toast、Banner 或系统
通知，只更新 timeline、recents、排序和未读状态；用户在当前聊天离开底部时继续由 ChatPage 现有
“新消息”入口提示。App 后台、锁屏、窗口失焦或 opaque target 不匹配时，native 不拦截，仍只
显示一次 EMAS `NOTICE`。

native delivery ID 只有在 typed sync receipt 表明 Core 成功、所有本地刷新完成、且通知打开
路由也成功后才能确认。打开事件只接受 `extraMap.mid` 的安全 opaque message reference 和
必填未过期 `extraMap.exp`；App 在 sync 后用 committed logical/remote/local message ID
独立派生 reference，匹配后只打开该 committed message 的 canonical conversation。其他
payload metadata、raw conversation ID、URL、title/body 都不能决定导航；无匹配时只显示会话
列表。

activation、resume、event drain、ack 和 navigation 全程绑定相同
`SessionEpoch(ownerDid, stableIdentityKey, generation)` 与 `StorageScopeId` tenant。
每个 await 前后都重新验证 fence；A→B、logout、tenant replacement 或 registration refresh
期间的旧完成只能保留事件待后续真实触发重试，不能确认 A 的 delivery、选择 B 的会话或把
A 的安装绑定到 B。

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

打开会话后，text/payload/attachment 首发、重试和 read/sync 都传入同一 canonical `AppConversationReadRef`；Core 用 directory 解析时写入的 owner-scoped Direct route 寻址 current DID。App 不得把 peer-scope 会话降级为 `dm:<targetDid>` write alias。`ChatThreadsController` 只从 canonical `conversationId` timeline、conversation timeline patch 或 committed projection repair 中获得更新消息。列表 preview 的 authoritative base 仍来自 `im-core` conversation summary projection；legacy alias、remote history best-effort page 或 realtime hint 都不能成为第二套 preview 真相。`ConversationListProvider` 是 recents state 的唯一发布边界，snapshot、fast-local、patch reset/upsert/remove/reorder、repair 和 read ack 都必须在发布前应用同一套 read presentation waterline；Profile/Group 展示信息在 Widget/View Provider 中组合，不回写 base summary。这个 waterline 只接受 latest message watermark 前进或 read watermark 前进；summary-only 更新不能提前清 unread，read watermark 覆盖的迟到 unread 不能重新出现，旧的 0 unread 不能清掉更新消息。真正的 read state 必须通过带 message watermark 的 `markConversationRead(AppConversationReadRef, watermark)` 提交，并以 Core 返回的 `effectiveWatermark` 确认本地持久提交；`pendingRemoteAck` 表示 Core 已完成 local-first 提交，不能被 App 误判为本地失败。

新加入设备采用 tail-only 消息语义：Agent Inventory 或显式打开只能建立 canonical Direct
route，不能证明 Message Service 已发布 durable thread binding。空 Direct 在首次
conversation-after 收到 `SYNC_THREAD_BINDING_REQUIRED` 时，data adapter 将稳定服务码投影为
typed binding-unavailable，presentation 将其视为“尚无加入后历史”并正常展示空会话；不得用
DID、Handle、Inventory 或 presentation thread 猜测/持久化 binding。若本地已有带
`serverSequence` 的消息仍缺 binding，则属于一致性错误并继续向用户/诊断层报告。

Conversation patch stream 必须串行应用；`reset` / `upsert` 在发布新会话行前先完成同一 owner/runtime scope 的本地 Persona Profile 读取，使会话列表和聊天页头的首个内容帧直接使用已缓存昵称。缓存读取失败时保留已有 Profile 并按统一 resolver 回退 Handle/DID，但不能为等待远端 Profile 阻塞 patch，也不能先发布 Handle 再用本地昵称覆盖。聊天页头即使暂时缺少 current DID，也必须能以 `peerPersonaId` 读取同一份 Profile 投影。

## 10. Timeline 和 Local-First 打开路径

Chat presentation 是单向的：

- `ConversationListProvider` 负责 recents / unread / badge 状态，base row 来自 core conversation read model，App 只叠加 product overlay 和 read presentation waterline。
- `ChatThreadsProvider` / `ChatThreadsController` 负责 conversation timeline window、merge、sort、repair，以及按 canonical conversation 串行合并 read intent，主 key 是 `ConversationSummary.conversationId` / `AppConversationReadRef`。
- `ChatPage` 渲染 selected conversation 并声明可见 / 隐藏状态；它可以在用户回到底部或新消息进入可见窗口时推进 intent，但持久 intent 的建立不能依赖 Widget 的 post-frame 边缘事件，也不得因 summary 更新主动补拉 history。

Chat presentation 同时是 owner/session-generation scoped：

- `SessionEpoch` 由规范化 owner DID、稳定本机 identity key 和单调 generation 组成。active identity 改变、登出或 clear 都会推进 generation；同一 identity 的 token/profile refresh 不会误伤正在进行的工作。
- `MessageSyncCoordinator` 只允许同一 epoch 的请求 single-flight/coalesce。A 的 active 或 delayed sync 不能满足 B 的 startup sync；A 完成后只有仍属当前 epoch 的结果可以刷新 recents、Join inbox、prewarm timeline 或更新 coordinator state。精确正文补齐由 Core 在 `syncNow` 中完成并提交本地 projection；App 不再根据 hydration ID 二次调用 `syncConversationAfter`，只在 Core commit 后执行 fast-local summary read、本地 timeline prewarm 和可见窗口刷新。
- `MessageSyncCoordinator` 将 patch preparation/Core 同步与 Core commit 后的 App 投影刷新分开捕获：认证拒绝立即终止并要求重新登录；普通可重试失败按连续 30 秒阈值升级红色提示；Join inbox 或列表刷新失败只标记 `projectionRefreshFailed`，不能触发网络同步失败重试或声称本地事实未改变。对外诊断只包含 stage/category/稳定 code/HTTP status/count/time 等脱敏字段。
- `ChatThreadsController` 在 epoch 改变时同步取消旧 patch subscriptions 和 timers，清空 pending history/read/repair、thread window、message route cache 与 composer draft。history、conversation-after、patch repair、read ack、text/attachment send 和 retry 都在 await 后再次校验启动时 epoch。
- Future、stream callback 或 timer 即使无法底层取消，旧 epoch 完成也只能安静结束；不得删除新 epoch 的 active marker、合并到新 timeline、更新新 recents preview、恢复旧 read intent 或显示旧错误。

打开会话的 first-paint 路径：

1. 从 selected conversation ID state 读取 `conversationId`，构造 `AppConversationReadRef`。
2. 启动或确认 `watchConversationTimelinePatches(conversationId)` subscription。
3. 从当前 memory conversation window 检查是否已有 `hasRenderableContent` 消息。
4. 如果 conversation 有 renderable `lastMessageSnapshot`，可用 snapshot 预热首屏。
5. 如果内存不足，再调用 `loadConversationTimeline(conversationId)` 读取 recent local projection。
6. memory / snapshot / local projection 命中后，首屏立即可渲染，并后台触发 `syncConversationAfter(conversationId)`。
7. remote history / thread legacy adapter 只作为迁移兜底；返回消息必须先持久化到 core projection，再通过 conversation timeline load/patch 成为 UI 事实。
8. 如果 patch key 与当前 window 不一致，应触发 repair/diagnostic，不得用易漂移的 summary 或 alias 规则静默 drop core 已返回的消息。

账号 session 激活后的 patch-ready 顺序固定为：

1. 以 `session generation + ownerIdentityId + accountId + device auth generation + ownerDid`
   建立 generation-specific committed patch subscription。
2. Core subscription 的首个 `reset` 从 canonical SQLite projection 生成，同时作为本
   generation 唯一一次有界 local seed；显式 legacy redb snapshot API 不参与 bound watch
   的初始 seed。
3. `preparePatchGeneration()` / `ensurePatchReady()` 完成后，协调器才执行首次可靠
   bootstrap/delta/reconcile；同 generation 的后续调用复用 ready single-flight，不再次 seed。
4. seed 期间到达的 patch 在同一 stream 中串行排队，reset 后继续应用，不通过第二次
   conversation refresh 补偿。
5. version gap / `repairRequired` 只合并为一次有界 repair；stream error/close 在下一
   microtask 重建 subscription 并等待新的 reset，避免在 stream callback 内取消自身。
6. Profile load、repair 和 timeline patch 在异步调用前后都重新校验 fence；即使 DID
   未变化，只要 session 或 device auth generation 前进，旧 patch 和旧异步结果也必须丢弃。

未带 typed account binding 的 legacy/test session 只保留“先订阅、一次 fast-local
seed”的兼容屏障；正式 v2 account session 必须走上述完整 fence，不允许从 DID 推断
`ownerIdentityId` 或 `accountId`。

Timeline merge 必须把“同一条本机发送消息的 durable server row”和“迟到的本地 echo/pending/failed row”视为同一展示实体：如果 mine、thread、sender、可见文本和时间窗口匹配，且其中一条已经是 `sent`，UI window 保留已发送的 server row，不再把迟到的本地失败 echo 渲染成第二个气泡。这个规则只属于 presentation 去重防线，不改变 `im-core` 作为 send/outbox/local projection 事实源的职责。

发送状态的 UI 降噪规则：core timeline row 进入 `sending` 后，气泡先不显示转圈且不预留左侧空白；同一 row 连续保持 `sending` 满 3 秒才显示 indicator。row 更新为 `sent` 或 `failed` 时 indicator widget 立即销毁。若 `sendConversationText` / `sendConversationPayload` 已返回明确终态，App 只允许用该 SDK 结果收敛当前 timeline 中已经存在、且 message id 或严格 pending match 对应的 core row；不得因此插入新的 memory-only message，也不得触发 full conversation refresh 或 remote history reconcile。

特殊边界：`dm:peer-scope:*`、legacy DID direct、old Flutter direct alias、handle 切换和 DID rotation 都必须在 `im-core` identity resolver / migration 中收敛到 canonical `conversationId`。AWiki Me 可以展示 alias/handle/DID，但不能用这些字段决定消息归属、read ack key 或 timeline patch key。旧 `ThreadRef` / raw thread history 能力只作为 compatibility adapter；App 主路径不得把 `unsupported_capability: thread-history` 暴露为可见错误。附件下载是明确的网络寻址例外：timeline 归属仍保持 canonical peer-scoped conversation，但下载请求必须使用该会话已解析的 direct peer reference，不能把不可逆的 `dm:peer-scope:*` storage thread 传给只支持 direct/group 的 attachment lookup。

会话列表、聊天头部、联系人、添加群成员候选、`@` 候选、群成员和群消息发送人属于同一个 Profile 展示投影消费面。持久投影由 `im-core` 按 storage scope、owner identity 和 `peerPersonaId` 隔离；当前 DID 只是 Persona 的 route。App `PeerDisplayProfileStore` 以 Persona 为主键，DID-only unresolved 项进入独立 bucket，不能把一个 DID 查询结果复制成另一个身份的 alias。以上消费面必须同时复用该投影的名称与头像；候选列表不得直接展示原始 conversation/roster 快照，也不得使用与 Persona 无关的固定占位头像。切换消息页、选择会话和联系人首页预览都不得触发远端 Profile 查询；完整关注/粉丝页和用户主动打开头像时才刷新远端资料，单个失败保留旧缓存且不能阻断其他条目。群会话 Composer 打开时通过 `GroupController.ensureGroupMembersLoaded` 合并同群冷加载并把 roster 发布到 `GroupState.membersByGroup`；`@` 的每次 query 只读取该应用层投影、叠加本地 Persona Profile 后过滤，禁止按字符重复调用 `group.list_members`。添加/移除成员和用户显式刷新仍通过 `GroupController.loadGroupMembers` 更新该投影。展示顺序为本地备注、昵称、完整 Handle、紧凑 DID、unknown；有本地昵称时首帧必须直接显示昵称，不得出现 `Unknown → 昵称` 或 `Handle → 昵称` 闪烁。群名的冷启动基线来自 `im-core` owner-scoped Group profile projection，并随 conversation snapshot/patch 携带；View 层可按同一 canonical `conversationId` 组合更新后的群资料，但不得改写 Core conversation identity。群资料刷新、添加成员和移除成员回调必须保留已选会话原有的 `conversationId`，不得用 `groupId` 重新拼接 `group:*`。

身份查找结果和群系统事件的主显示名使用明确的上下文顺序：“当前昵称 > 完整 Handle > DID”。DID 只是最后 fallback，UI 可使用紧凑格式显示；不得在 nickname 或 Handle 已知时优先显示 DID。这两类 UI 仍必须消费同一 Persona Profile 投影，Widget 不得自行拼接 fallback。

实时消息路径：

1. realtime notification / `sync` hint 与 Android remote Push 都只用于
   duplicate/gap/dirty 判断和调度 SDK sync。
2. App runtime 不直接 upsert 会话列表或 chat timeline authoritative state。
3. Rust `im-core` 对在线首条 Direct 先按 wire peer DID 完成权威 Handle lookup，并按“verified Persona projection → inbound message commit”的顺序写入；失败或 DID 不匹配时只进入 resolution backlog，不产生 DID conversation。
4. Rust `im-core` 在 sync/realtime/backfill 成功写入 SQLite local projection 后，runtime store 发 conversation patch 和 conversation timeline patch；realtime row 尚无 thread-local sequence 时使用接收侧时间而非发送方时间作为收敛期排序键。
5. AWiki Me 收到 patch 后按 canonical `conversationId` 更新 list/detail；alias prewarm 只可作为迁移优化或诊断，不能作为消息归属 correctness 机制。
6. metadata-only delta 可以先提交活动时间和未读数；Core 通过 durable conversation hydration hint 要求 coordinator 补齐正文。只有补齐结束后的 committed summary read 才发布最终预览，不能等用户打开会话才触发正文恢复。

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

聊天页执行持久已读上报时必须按 canonical `conversationId` 重新读取
`ConversationListProvider` 的最新 summary，并与进入可见态时保留的、尚未被
presentation waterline 清零的 snapshot 组合。导航传入的旧
`ConversationSummary(unreadCount: 0)` 不能阻止对最新可见消息 sequence 的 Core
watermark 上报；本地 badge 清零也不能替代持久 read ack。

read intent 是可见状态的 level-triggered orchestration，不是 Widget 的 edge event：

1. `markConversationVisible` 必须在同一个 Controller 调用中先记录 canonical 可见状态，再为已有未读建立 pending intent。
2. lifecycle 非前台、timeline 正在水合或当前尚无 renderable watermark 时保留 intent；history、patch、resume 或可见 timeline 前进后继续 drain，不使用定时重试。
3. 每个 canonical conversation 同时只能有一个 Core read commit；在途期间到达的更高 watermark 按 `threadSeq -> readAt -> messageId` 单调合并，前一个完成后再提交更高水位，禁止并发和回退。
4. `ConversationService.markConversationRead` 必须保留 Core 的结构化结果。只有 `effectiveWatermark` 覆盖 target 后，App 才把该 intent 记为本地已提交；`remoteAcknowledged=false + pendingRemoteAck=true` 仍是 local-first 成功，由 Core 负责后续远端补偿。
5. Core 异常或不完整结果保留 intent，等待下一次真实 lifecycle/history/patch 触发；不得在 UI 层强制清 durable unread、启动忙重试或把 presentation unread `0` 当成提交完成。
6. 会话隐藏会移除尚未开始的 visible intent；已进入 Core 的调用可以按 local-first 合约完成，但不能为隐藏会话继续产生更高水位。
7. 所有 intent、drain 和 Core completion 都必须绑定发起时的 `SessionEpoch`；identity 切换后立即清理 pending / committed presentation 水位，旧 epoch 的延迟完成不得清理或改写新身份状态。

`ConversationListState` 是 normalized store：`entitiesById` 只以 required canonical
`conversationId` 为 key，`orderedIds` 只保存展示顺序，`version` 与
reset/upsert/remove/reorder 在同一次 state assignment 中前进。空数据必须与
`initializing/stale/error` 正交；Core 加载失败显示可重试错误，不得伪装成真实空列表。

Peer 名称只由纯 `PeerDisplayNameResolver` 和 `peerDisplayNameProvider`
组合，固定优先级为“Persona 本地备注 > 当前昵称 > 完整 Handle >
历史 sender snapshot（仅未解析/Profile 缺失）> 紧凑 DID > unknown”。
会话列表、聊天页头、联系人、添加群成员候选、`@` 候选、群成员、群消息发送人和用户详情都消费
同一 ID-scoped provider，并通过 `peerAvatarUri` 复用相同头像投影；Widget 不得自己重写 DID/Handle 回退或使用脱离 Persona 的候选头像。会话本地 bundle
与 cached Persona profile 完成后才发布首个内容帧，避免
`Unknown/Handle -> 昵称` 闪烁。
身份查找结果和群系统事件使用“当前昵称 > 完整 Handle > DID”；DID 在 UI 中可紧凑显示，但只能作为最后 fallback。

如果 DID-only profile 先于 verified Persona route 到达，后续 Core
conversation/profile bundle 必须在发布会话行前把该投影迁入 Persona-keyed store。
若 App 已记录的 DID→Persona route 与后到 route 冲突，App 不移动展示资料也不覆盖
原 route；绑定冲突只能由 Core 的权威身份投影解析或诊断。

## 12. 不引入消息与会话双缓存

AWiki Me 不再新增 Flutter 侧 message/conversation/group 主数据 cache，也不引入 MMKV 作为 conversation snapshot 或 presentation truth。

原因：

- `im-core` SQLite 是 message、conversation、group、read-state 的主数据源。
- `im-core` redb snapshot 已覆盖冷启动 bootstrap 的非权威缓存需求。
- `ProductLocalStore` 保存产品 overlay、UI preference，以及 User Service 权威的
  Agent inventory/status、当前账号 Profile、Device Registry 版本化展示快照；这些账号域 cache
  不能保存消息、会话、群主数据、read watermark、消息 cursor 或 Core Agent control facts。
- `ChatThreadsProvider` 的内存 tail 是 UI 状态和 first-paint 加速，不是持久主数据源。

Product local DB v4 的账号域表全部按稳定 `owner_identity_id` 分区，并通过
`account_domain_sync_state(owner_identity_id, account_id, domain)` 固定账号绑定。App 只能在
SDK `ActiveSyncAccountBinding` 已可用并通过 session fence 后访问这些表；不得从 DID、Handle、
JWT、Vault context device ID 或 App installation UUID 推断 `account_id` / Protocol Device ID。
Session fence 还要求 Protocol Device ID 不得为保留兼容值 `default`，identity/device
generation 必须是大于 0、无前导零的 canonical positive decimal string。同一
`owner_identity_id` 已绑定其他 `account_id` 时读写 fail closed。

每个域的 replace 必须在一个 SQLite transaction 中执行“清旧 rows（允许清成空）→ 写完整
snapshot → 推进 domain version”。Inventory topology 与 latest status 使用不同表和版本：
topology replacement 不删除 status，status replacement 不修改 config/`activeState`。
Product cache 的 domain/inventory/status/profile/registry version 与 Registry snapshot
`auth_generation` 保存为任意精度 canonical non-negative decimal string，允许唯一的零值
`0`；它们不能转成 Dart number 或 SQLite INTEGER，也不得冒充 Session binding 中必须大于 0
的 generation。v3 的 `local_agent_states` 只允许在显式稳定 binding 和旧 owner DID 同时给出后
copy-on-read；迁移成功也保留旧行，直到单独清理策略获批。

## 13. 回归测试

当前必须保留以下测试覆盖：

- `tests/unit/application/messaging_conversation_service_test.dart`：验证 overlay 不进入 core 主数据、snapshot/fast list/enrichment 应用 App overlay、pinned 排序、hidden waterline、Agent lifecycle 和 runtime merge/hide。
- `tests/unit/data/im_core/awiki_im_core_mappers_test.dart`：验证 core DTO 到 App summary 的映射只通过 App 侧参数应用 overlay，并固定带显式可见文本的 control payload 可以更新 recents 预览、payload-only control 继续隐藏。
- `tests/unit/data/im_core/awiki_im_core_payload_mapper_test.dart`：验证 payload / mention 解析、合法 range 投影和无效 payload fallback。
- `tests/unit/chat_mention_send_test.dart`：验证有 valid mentions 时发送 payload，无 mentions 时继续走普通 sendText。
- `tests/unit/chat_mention_composer_test.dart`：验证 draft mention range 维护、编辑失效、候选插入，以及冷加载合并和连续 query 只使用一次群成员请求。
- `tests/unit/chat_page_test.dart`：验证聊天窗口渲染、read ack 边界、header 行为、sending indicator 的 3 秒延迟与明确终态清理等关键 widget 行为。
- `tests/unit/chat_provider_open_test.dart`：验证打开会话 local-first conversation timeline、conversation-after/remote fallback、conversation timeline patch version gap repair、stream closed repair/re-subscribe、read ack、文本 / payload / 附件 send intent 和附件 retry 都按 `conversationId` / `AppConversationReadRef` 走主路径；其中可见群聊必须在 Controller 自身建立持久 intent，不依赖 Widget 二次回调，并覆盖在途 `seq 5 -> seq 6` 串行合并和 Core `pendingRemoteAck` local-first 成功。
  - 其中 `dm:peer-scope:*`、legacy direct、old Flutter direct alias 和 handle/DID rotation 必须由 core/SDK canonical identity 收敛；App 不因 raw thread history unsupported 而把错误暴露成可见 UI 报错。
  - 身份隔离还必须覆盖 A 的 delayed local history、patch repair 和 send completion 在快速 A→B→C 后被丢弃，同时切换当下即清空旧 thread window、patch subscription 和 composer draft。
- `tests/unit/agents/agent_terminal_notification_test.dart`：用 fake time 验证三种业务终态、真实运行失败、严格 fail-closed、message-first / status-first、1 秒 timeout fallback、clear timer cleanup、有界 replay ledger 和普通最终回复关联。
- `tests/unit/message_sync_coordinator_test.dart`：除 single-flight、节流和 snapshot-required 外，验证 A active sync 不会 coalesce 或满足 B startup sync，旧 identity 的 delayed request 在快速切换后不会执行；Core sync commit 后必须启动新一代 fast-local read，不能复用提交前仍在运行的旧刷新；V2 committed incoming notification 与终态通知共享 message identity 去重，不因 reliable sync 投影再次提醒；后台消息发送者匹配当前 Agent inventory 时，系统通知标题必须使用 App 的本地化 Agent 展示名，而不是消息携带的内部 `skill-*` 名称。
- `tests/unit/message_sync_service_test.dart` 与 `tests/unit/message_sync_coordinator_test.dart`：固定 remote-push typed receipt 的六种 disposition、successful-sync 后 committed incoming identity、active/queued/automatic-retry presentation suppression OR 传播，以及抑制通知时仍更新 projection 与 dedupe ledger。
- `tests/unit/application/remote_push_message_reference_test.dart`：固定 opaque message/target reference 的 SHA-256 向量，并拒绝空白、控制字符、前后空格和超长输入。
- `tests/unit/application/remote_push_message_sync_coordinator_test.dart`：固定 pending native event 的串行 batch、provider-presented 与 app-presentation-required disposition、session target 安装/清除、真实触发重试、成功后 exact acknowledgement、opaque open matching、过期/畸形 hint 降级，以及 session/tenant stale 时不 ack、不导航。
- `tests/unit/application/remote_push_installation_coordinator_test.dart` 与 `tests/unit/data/push/user_service_push_installation_adapter_test.dart`：固定 authenticated installation upsert/disable、安全字段、response binding、registration refresh 和旧 session fencing。
- `tests/unit/session_provider_test.dart`：固定 clear、A→B 和快速身份替换推进 epoch，同一 identity 的 JWT/profile refresh 保持 epoch。
- `tests/unit/app_runtime_notification_test.dart`：验证 realtime notification / sync hint 只调度 SDK sync、dirty/gap/repair 和通知 / runtime 分发边界，不直接写 list/detail authoritative state；同时从 `loginWithLocalCredential` 身份切换入口证明新 session epoch 会自动调度自己的 `startup` reliable sync，并在不由测试手动调用 coordinator、sync service 或 conversation-after 的情况下把 committed unread 和 hydrated preview 发布到会话列表。通知路由只受 session epoch 约束，不能被同身份下并发的列表 refresh generation 误取消；还覆盖前台任意页面全局静默、后台终态通知、三种 outcome 的 message-first exact-once、status-first、timeout fallback 和 logout cleanup。Android remote Push 回归还固定 patch-ready 前不启动 sync、cold pending event 优先使用 `remote_push`、provider/App presentation disposition、opened exact conversation、unmatched list fallback、logout/identity switch stale fence、resume retention 与 registration refresh。
- `tests/unit/agent_terminal_notification_widget_test.dart`：验证所有业务终态与真实运行失败在前台均不形成 App 内横幅，并覆盖 message-first 语义胜出和 dispose timer cleanup。
- `tests/unit/conversation_list_provider_test.dart`：验证 base row 先于 enrichment 展示、patch upsert/remove/reorder/repair 全部按 canonical ID、clear 后不回填、snapshot bootstrap guard、local hidden waterline 不被旧 patch 冲破、不同 canonical ID 不因 DID/Handle 相同而合并、selected state 仅保存 ID，以及所有 recents 发布入口应用同一 read presentation waterline。
- `tests/unit/conversation_list_provider_test.dart` 还必须验证 patch-ready single-flight、订阅先于 seed、seed 期间 patch 不丢不重、stream error/close 单次重建，以及同 DID auth generation 切换后旧 patch / Profile 异步结果失效。
- `tests/unit/data/im_core/awiki_im_core_conversation_adapter_test.dart` 与 `awiki_im_core_message_adapter_test.dart`：验证 conversation/timeline patch 的 `ownerIdentityId` 不在 SDK→App 映射中丢失，并验证产品诊断只映射脱敏 mode/count/domain/retry/time 字段。
- `tests/e2e/flutter/app/app_smoke_test.dart`：验证真实 App UI 从完整 Handle 发起空私聊后，Core committed row 在首条消息前可见，recents 与 selected ID 始终指向同一个 canonical conversation；同时验证后台 committed Agent 消息通过系统通知 facade 投影时，标题使用 Agent inventory 的展示名。
- `tests/e2e/flutter/desktop_cli_peer/flows/attachment_flow.dart`：验证不同客户端账号发送附件时，关闭会话的 unread 精确 `0 -> 1`，从 recents 打开后精确 `1 -> 0`，并在 App presentation 重建后仍从 Core local read state 恢复为 `0`，同时保留 canonical 附件、下载字节和 digest 校验。
- `tests/e2e/flutter/desktop_cli_peer/flows/direct_message_flow.dart`：direct App + CLI peer E2E 在 CLI -> App 消息后，先等 conversation refresh 返回 `ConversationSummary`，再验证 list latest message 能在 `conversationId` 对应的 canonical timeline 中唯一出现；同正文双消息还必须在 realtime 首次可见、sync sequence 收敛、重连和重启后保持不同 canonical ID 与严格递增顺序。
- `tests/e2e/flutter/desktop_cli_peer/flows/group_message_flow.dart`：群消息流程必须覆盖 CLI 入站后总未读 `baseline -> baseline + 1`、App 重启后 group row 仍为未读、打开群聊后 Core read watermark 提交并使 conversation unread 与总未读共同收敛回 baseline。
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

本地状态启动先执行明确的版本边界：schema 1 到 26 的预发布 Core SQLite 文件集归档后
按当前 schema 重建；schema 27 及以上不得走该退场路径。release/0710 到 canonical schema
的启动顺序固定为：Vault 解锁 → Core
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
- 窄屏 / 移动聊天头部使用“返回箭头 + 来源页”并保持标题可点击，不显示 Agent 类型、安全协作标签或右侧竖向更多按钮。
- 移动端点击聊天标题进入完整用户 / 智能体或群聊资料子页；桌面端点击头像或标题打开完整资料 Dialog。两种形态复用同一份 provider 与资料内容组件。
- 普通消息左右两侧的发送者头像都是资料入口：自己的消息打开当前身份资料，其他消息打开实际发送者资料；该规则只依赖 `ChatMessage.isMine` 和发送者 canonical identity，因此 Direct、Group 和 Agent 会话使用同一条渲染路径。群消息不得回退为群资料或会话对端资料。
- 当前身份入口复用 `showCurrentIdentityDialog` 和 `ProfilePage`，与主导航 / 设置中的“我的资料”保持同一实现；对方用户与 Agent 继续复用 peer profile provider 和资料组件。自己可编辑、对方可关注 / 发消息、Agent 运行状态等能力边界不同，不把它们强行合并成同一个带业务动作的大组件；共同的资料卡、metadata 和链接样式继续由 `identity_profile_surface.dart` 统一维护。
- 直聊资料采用 shell-first 渲染：点击后立即基于 `ConversationSummary`、本地 runtime `AgentSummary` 和 DID 展示标题、头像、DID、类型与 Agent 收件箱入口；`peerProfileProvider` 的公开 profile、关系状态和主页 Markdown 返回后再增量补齐昵称、头像、handle、身份卡正文和关系标签。
- 公开 profile 或后续关系 / 主页 Markdown 加载失败不得阻塞资料页或 Dialog 打开，也不得清空已展示的基础信息；只在身份卡区域内提示资料暂不可用或继续保留已返回的 profile 内容。
- 群详情里的成员刷新能力不属于聊天头部入口，保留在群详情 / 群信息组件内。

相关回归覆盖在：

- `tests/unit/chat_page_test.dart`：除头部入口移除外，还固定头像信息弹窗必须先展示基础信息，并在 profile 返回后补齐资料。
- `tests/unit/conversation_workspace_test.dart`
- `tests/e2e/flutter/app/app_smoke_test.dart`
- `tests/e2e/flutter/app/ui_visual_verification_test.dart`
