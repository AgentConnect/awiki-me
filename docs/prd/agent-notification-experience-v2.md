# AWiki Me Agent 分级消息与通知体验 PRD v2

状态：`Frozen for design and local implementation`

日期：2026-08-11

适用基线：`release/0714`

首期范围：可信 Agent 向用户发送 Direct 结构化消息；AWiki Me 展示分类型聊天卡片，并在满足策略时提供一次短促、有界的“紧急呼叫”提醒。

## 1. Executive Summary

本需求在既有 AWiki 消息事实链路上增加一层受控的结构化展示与分级通知语义，而不是建立第二套消息或通知事实。

首期只新增一个用户可见 canonical schema：`awiki.agent.message.v1`。消息的 `kind` 只允许 `message | task_result | alert`，通知语义 `level` 只允许 `normal | urgent`。产品与 UI 将 `kind=alert + level=urgent` 命名为“紧急呼叫”；不新增 `urgent_call` kind，避免 kind 与 level 表达同一事实。

“紧急呼叫”是一次有界的高打扰提醒：醒目的聊天卡片，以及在平台与用户设置允许时的一次短促声音和一次振动。它不是 VoIP 来电，不持续响铃，不使用 full-screen intent，不主动唤醒屏幕，不绕过 DND/专注模式，也不使用 Apple Critical Alert。

消息正文、会话归属、未读、列表摘要和导航目标只来自 `im-core` 已提交的 canonical message。WebSocket、remote Push、provider callback 和 reserved notification control 都只能作为同步或展示提示，不能创建 timeline truth。

首期采用 Android-first：App 前台可见且能执行本地策略时，可根据可信 Agent、用户 opt-in、mute、新鲜度和限流决定 normal/urgent presentation；App 不在前台时，后台唯一可见展示 owner 是 Message Service 的隐私安全 generic normal Push。杀进程场景的可信 urgent 提升和会话 mute 一致性保持 `BLOCKER`，不得以 DID path、sender 名称或 payload 自报字段猜测。

## 2. 背景与问题

当前 AWiki Me 已支持普通文本、Markdown、Mention、附件卡片、前台静默、后台系统通知、会话 mute 和 canonical conversation 点击路由，但存在以下缺口：

1. 不同 Agent 消息类型没有统一、版本化的卡片语义。
2. 任意 `awiki.*` JSON 当前会被 Core/App 的 broad classifier 当作 control，直接添加 Widget 特例会导致 timeline、recents 和 unread 分裂。
3. App notification facade 当前使用单一高优先级 channel、随机 native ID，并统一触发 screen wake，无法表达 normal/urgent 或 replay exact-once。
4. Message Service 对 JSON、附件、E2EE 和不安全输入使用 generic Push 文案；Push worker 当前只解析 Android installation。
5. App killed 时无法读取当前账号 active Agent inventory、会话 mute 和本地 opt-in，因此不能安全提升 urgent。
6. 旧客户端会隐藏新的 `awiki.*` visible schema；自动 capability fallback 尚无权威输入，不能通过“双发 JSON + 文本”规避。

## 3. 目标与成功标准

### 3.1 产品目标

1. Agent 可以通过现有 AWiki Skill → `awiki-cli msg send` → `im-core` 链路发送受控结构化消息。
2. AWiki Me 按 `message`、`task_result`、`alert` 展示稳定、可本地化、可测试的聊天卡片。
3. `alert + urgent` 在满足全部 gate 时显示“紧急呼叫”样式，并只产生一次有界声音与振动。
4. 相同 logical event 在 CLI 重试、WebSocket、HTTP sync、Push callback 和进程恢复后，最多形成一条 canonical message 和一个 active user-visible notification identity。
5. title、route、Agent 品牌、附件和通知级别不能被发送方 payload 越权控制。
6. 服务端 Push 不泄露 structured summary/detail、raw JSON、完整 DID、签名或凭证。

### 3.2 完成标准

整体功能只能在相应平台和状态拥有真实证据后标记完成：

- schema、Core classifier、App mapper/card、policy、receipt、channel、Push privacy 和兼容 gate 均有确定性测试；
- Android 前台、后台、杀进程、权限拒绝、声音、振动、点击和 replay 有命名真机证据；
- WebSocket + Push 同时到达仍为 exact-one；
- muted、untrusted、opt-out、expired、rate-limited 和 stale SessionEpoch 均 fail closed；
- 报告明确区分 `PASS / FAIL / BLOCKER / UNVERIFIED / SKIPPED`。

Provider acceptance、outbox `done`、Debug build、fake notification facade、Widget 存在或测试进程退出码为 0，都不能单独证明用户看见了通知。

## 4. 非目标

首期明确不包含：

- VoIP/持续来电体验；
- full-screen intent、screen wake、DND bypass、Apple Critical Alert；
- Group structured/urgent；
- E2EE structured message 或 E2EE notification preview；
- structured attachment、payload object URL 或“附件消息 + control 消息”双消息关联；
- 任意 deep link、payload-provided conversation、URL 或 provider channel；
- Coding Agent lifecycle 必达钩子；
- iOS server-side remote delivery 闭环；
- App killed 时的 trusted urgent 提升或可靠 mute；
- 自动 mixed-version capability fallback；
- merge、Push、Release、部署、生产配置或真机操作授权。

## 5. 用户与用户故事

### 5.1 角色

- 用户：AWiki Me 当前账号 owner，控制通知权限、紧急呼叫开关和会话 mute。
- 可信 Agent：sender DID 精确存在于当前账号、当前 SessionEpoch 的 active Agent inventory。
- 普通发送方：经过消息协议认证，但不满足当前 active Agent trust gate。
- AWiki Skill/CLI：负责显式授权、固定 identity/target、输入校验、dry-run 和发送结果表达。
- AWiki Me：负责 validated card、presentation policy、receipt、native submission 和 canonical route。
- Message Service：负责消息/Push outbox、installation resolve、generic privacy envelope 和 provider adapter。

### 5.2 用户故事

1. 作为用户，我希望普通 Agent 消息、任务结果和告警在聊天中有清晰但一致的卡片样式。
2. 作为用户，我希望只有我允许的可信 Agent 才能触发“紧急呼叫”。
3. 作为用户，我静音一个会话后，希望 App 不再产生该会话的本地声音、振动或系统通知。
4. 作为用户，我希望紧急提醒只响和振动一次，不因重连、重放或打开 App 再次触发。
5. 作为用户，我拒绝系统通知权限后仍能在聊天中看到消息，并能从设置页理解和恢复权限。
6. 作为用户，我点击通知时只会进入消息真实所属的 canonical conversation。
7. 作为安全负责人，我希望 raw payload、detail、凭证、路径和内部 ID 不进入 Push 或诊断日志。
8. 作为旧版本用户，我不应收到一条看不见的 structured message；发送端必须先满足 minimum-app-version gate。

## 6. 产品术语与事实边界

### 6.1 Message truth

只有 Core committed message 可以贡献：

- timeline message；
- recents/summary；
- unread/read state；
- canonical conversation；
- notification click target；
- attachment target。

### 6.2 Presentation intent

`kind` 和 `level` 是 committed message 内的受控展示语义。`level=urgent` 只是请求；App 必须重新评估 trust、opt-in、mute、age、rate-limit、permission 和当前 presentation owner。

### 6.3 Reserved hidden notification

`awiki.agent.notification.v1` 仅保留为 non-public/reserved hidden schema。本期：

- Skill/CLI 不发送；
- 不生成第二条 message；
- 不贡献 timeline、summary、unread 或 search；
- 不生成独立 Push；
- 不作为 route 或 title 来源。

## 7. 唯一可见 Wire Contract

### 7.1 示例

```json
{
  "schema": "awiki.agent.message.v1",
  "event_id": "evt_task_20260811_001",
  "task_name": "AWiki Me 代码检查",
  "kind": "task_result",
  "level": "normal",
  "content": {
    "summary": "代码检查已完成",
    "detail": "发现 2 个需要处理的问题。"
  },
  "action": {
    "type": "open_conversation"
  }
}
```

### 7.2 字段定义

| 字段 | 必填 | 规则 | 产品含义 |
|---|---:|---|---|
| `schema` | 是 | 固定 `awiki.agent.message.v1` | 精确 visible schema |
| `event_id` | 是 | 8–160 字符；`^[A-Za-z0-9][A-Za-z0-9._:-]{7,159}$` | logical event 与 presentation 幂等键 |
| `task_name` | 是 | 所有 kind 必填；trim 后非空；单行；最多 120 Unicode scalar | Coding Agent 任务显示名；仅为展示上下文，不是 ID、路由或授权事实 |
| `kind` | 是 | `message | task_result | alert` | 卡片基础样式 |
| `level` | 是 | `normal | urgent` | 请求的通知语义，不是系统 priority |
| `content.summary` | 是 | trim 后非空；单行；最多 240 Unicode scalar | 卡片主摘要；App-local safe preview 的唯一候选 |
| `content.detail` | 否 | trim 后非空；最多 2000 Unicode scalar；允许换行 | timeline-only 详情；永不进入 provider Push |
| `action.type` | 是 | 固定 `open_conversation` | 只声明动作类别，不携带目标 |

整个 compact UTF-8 JSON 最大 8192 bytes，所有 object 均为 `additionalProperties=false`。
`agent_name` 不属于 payload；Agent 显示名只能来自接收端已验证的 sender/Agent profile，
不得由 payload 自报，也不得用 `task_name`、summary 或 conversation 标题猜测。

### 7.3 组合语义

| kind | level | 产品名称 | 卡片语义 |
|---|---|---|---|
| `message` | `normal` | 消息 | 中性信息卡 |
| `task_result` | `normal` | 任务结果 | 结果卡；不从文案猜 success/failure |
| `alert` | `normal` | 告警 | 醒目但非高打扰告警卡 |
| `message` / `task_result` | `urgent` | 紧急消息 | 保留原 kind 信息层级，使用 urgent presentation chrome |
| `alert` | `urgent` | 紧急呼叫 | 最强视觉层级和一次有界提醒 |

首期核心用户故事只要求 `alert + urgent` 达到“紧急呼叫”；其他 kind 的 urgent 输入仍经过同一 gate，不创建新的 kind。UI 不得根据 summary 中“紧急”“立刻”等自然语言自行提升 level。

### 7.4 Runtime safety filter

除 JSON Schema 外，发送端和接收端还必须拒绝或安全降级：

- C0/C1 controls；`detail` 仅允许规范化换行；
- bidi override/isolate、不可见格式控制和 NUL；
- fenced raw logs、明显凭证/Token/私钥文本；
- 绝对本地路径、`file://`、object URL；
- title、sender、conversation/thread/target、URL、attachment、channel、sound、wake、DND、provider priority 等越权字段；
- 非 object、未知/额外字段、超限或 malformed JSON。

known visible schema 如果 invalid/unsafe，不显示 raw JSON、summary 或 detail；Core 仍将其作为一条 user-visible unsupported message 计入一次 summary/unread，App 使用本地化 generic placeholder，强制 normal、禁用 action。

unknown future `awiki.*` 继续作为 hidden control，不进入普通 timeline。

## 8. 发送与兼容契约

### 8.1 当前 caller

```text
用户授权
  -> AWiki Skill
  -> awiki-cli identity pin + full Handle/DID resolve
  -> msg send dry-run
  -> msg send exactly once
  -> im-core SendMessageRequest::Payload
  -> Message Service
  -> recipient im-core committed projection
  -> AWiki Me validated card/presentation policy
```

不得新增第二套发送栈、裸 RPC、App-side wire builder 或 Push-to-message mapper。

### 8.2 授权与幂等

- 普通 structured send 需要用户明确授权 target 和内容。
- `level=urgent` 需要额外明确的高打扰意图；不得从模糊措辞自动推断。
- Skill 必须固定当前 sender identity，使用完整 Handle 或已验证 DID，不自动调用 `id use`。
- 使用 argv 调用 CLI，不拼接 shell；先 dry-run，再最多真实发送一次。
- 同一 `event_id` 必须复用稳定 `client_message_id` 和 `idempotency_key`。
- 结果不明确时不得换 ID、不得盲目重试；先从权威 history 对账。
- CLI `ok + accepted/final_acceptance + message.id` 只证明服务接受，不证明 App 或系统通知可见。

### 8.3 Mixed-version

旧 App 会把 `awiki.agent.message.v1` 当作 hidden control，因此首期必须使用 minimum-app-version gate：

- 只有接收环境已被权威发布/版本门禁确认为支持 exact schema 时，才允许 structured send；
- capability 无法确认时，typed API 返回稳定 `receiver_capability_unverified`，不发送；
- 不自动“双发 structured + plain fallback”；
- 如用户改为发送 plain text，应作为一次新的、明确授权的普通消息操作，不复用原 structured send 的成功声明。

自动 receiver capability discovery/fallback 保持 `BLOCKER`，需要独立权威输入与兼容设计。

## 9. 聊天卡片体验

### 9.1 共同结构

卡片只消费 validated App domain model，包含：

- kind 图标与本地化标签；
- `summary`；
- 可选 `detail`；
- urgent badge/chrome；
- 现有 message bubble context 中的 sender/time/read 状态；
- 点击区域打开当前 committed message 的 canonical conversation。

卡片不得展示或读取 payload 中的 title、sender、conversation、URL 或 attachment。

### 9.2 样式语义

- `message`：中性色，强调摘要，不暗示成功或风险。
- `task_result`：结果色与结果图标，但不从自由文本推断成功/失败。
- `alert + normal`：警示色、清晰边框，不发起高打扰声音/振动。
- urgent：在基础 kind 上增加统一 urgent chrome；`alert + urgent` 标签固定为“紧急呼叫”。
- invalid visible：本地化 unsupported placeholder，不复用任何 payload 色彩或文案。

### 9.3 前台行为

- normal：沿用全局静默；只更新 timeline、recents 和 unread。
- urgent 且 gate 通过：提交卡片，并产生一次 App-owned 的短促声音与一次振动；若用户不在目标会话，可显示一个可点击的 in-app urgent callout。
- 用户确认的 `alert + urgent` callout 采用覆盖 App 内容区的全屏视觉状态，类似来电提醒；它只存在于当前 App 进程和 Widget 树内，不是 Android `full-screen intent`、VoIP/CallKit、锁屏窗口或唤屏能力。
- 当前会话已经可见时，不再创建第二个 tray notification；card/callout 和 presentation receipt 必须使用同一 event identity。
- Reduce Motion 开启时取消脉冲/呼吸动画，但保留颜色、图标、文字和声音/振动策略。

## 10. Notification Policy

### 10.1 Urgent gate

按以下顺序评估：

1. exact schema 与 runtime safety valid；
2. sender DID 精确命中当前账号、当前 SessionEpoch 的 active Agent inventory；
3. 当前账号“允许紧急呼叫”显式开启，默认关闭；
4. conversation 未 mute；
5. Core committed accepted/receive time 不超过 15 分钟；
6. 15 分钟滚动窗口内每 sender 不超过 3 次；
7. 15 分钟滚动窗口内每 account 不超过 6 次；
8. 当前平台权限与系统设置允许。

Handle、display name、DID path、payload 自报字段、旧 identity cache 或 sender 看起来像 Agent 都不能提升 trust。

### 10.2 Gate 结果

| 条件 | message/card | presentation |
|---|---|---|
| 全部 urgent gate 通过 | 保留原卡片，显示 urgent chrome | App 前台一次有界 cue/callout；后台不晋升 provider NOTICE |
| untrusted、未 opt-in、过期、超限 | 保留原卡片 | 降级 normal |
| conversation mute | 保留原卡片 | App-owned presentation 完全抑制 |
| permission denied | 保留原卡片 | 不调用受限 native presentation；设置页提示恢复路径 |
| schema invalid/unsafe | generic placeholder | normal 或静默，不执行 action |
| foreground normal | 正常提交 | 静默并写 terminal receipt |
| provider already presented | 正常提交 | 不创建第二条 App-owned notification |
| App 非前台且 WS/Core 先提交 | 正常提交 | 写 `deferred_provider` terminal receipt；不创建 App-owned native notification，等待唯一的 provider NOTICE |

### 10.3 声音与振动边界

- 只允许一次短促 sound cue 和一次有界 vibration pattern；不循环、不定时重播。
- replay、重连、App resume 和 crash recovery 必须复用同一 stable native ID，replace/no-op。
- Android channel、iOS/macOS 系统通知、静音键、DND/专注模式、通知总开关和用户自定义设置始终具有最终决定权。
- 不承诺在系统静音、DND、权限拒绝或 OEM 限制下发声/振动。

## 11. App 状态矩阵

| 输入与状态 | Timeline | Foreground | Background / App alive | App killed |
|---|---|---|---|---|
| 普通 text/attachment | 现有 bubble/card | 全局静默 | existing normal notification | provider generic normal |
| structured normal | kind card | 静默 | provider generic normal；WS/Core-first 仅 defer | provider generic normal |
| structured urgent，App 为 presentation owner 且 gate 通过 | urgent card | 一次 in-app sound/vibration + 可选 callout | 不在后台晋升；provider generic normal | 不可评估 trust，generic normal |
| structured urgent，trust/opt-in/age/rate 不通过 | card 保留 | normal/静默 | provider generic normal | generic normal |
| 任意 structured message + mute | card 保留 | 前台抑制 App-owned presentation | provider 无权威 mute 输入，`BLOCKER` | provider 无权威 mute 输入，`BLOCKER` |
| provider NOTICE 已展示 | commit 后显示 card | 前台拦截路径按本地策略 | 不重复 App notification | provider generic normal |
| invalid visible | generic placeholder | 静默 | generic normal 或静默 | generic normal |
| hidden/reserved control | 不显示 | 无 | 无独立通知 | 无独立 Push |

后台展示权唯一归 provider NOTICE：WS/Core-first 只提交 canonical message 并 durable defer，provider-first 与同时到达也不得再创建 App-owned native notification。这样消除两套 native ID 的重复通知竞态；代价是“后台 urgent 必达”和“杀进程 mute 必达”都不能在首期宣称通过。

## 12. Platform Matrix

| 平台 | 首期能力 | 明确边界 | 状态 |
|---|---|---|---|
| Android | App 前台的有界 urgent cue/callout；Message Service generic normal NOTICE；stable receipt 与点击 | core channel only；不 full-screen/wake/DND bypass；后台只由 provider 展示，不能可靠提升 urgent/mute | Android-first；真机 `UNVERIFIED` |
| iOS | App-local alert/badge/sound 与卡片；遵循系统授权、静音和专注模式 | Message Service worker 当前未解析 iOS installation；无 Critical Alert | remote delivery `BLOCKER`；local 真机 `UNVERIFIED` |
| macOS | App-local Notification Center 与卡片 | 无本轮 remote killed-process Push 承诺 | `UNVERIFIED` |
| Windows/Web | 卡片可复用 shared presentation；保持现有能力 | 本轮不新增 urgent native acceptance | out of acceptance scope |

Android channel：

- `awiki_me_messages_v2`：provider structured normal，`Importance.default`、无声音、无振动；
- `awiki_me_urgent_v1`：保留为 typed facade 的 inactive seam，定义为 `Importance.high` 与一次短促 sound/vibration；当前 v1 生产协调器没有后台调用点，不预创建、不用于 provider NOTICE；
- 现有 `awiki_me_messages`：仅旧版本兼容，不原地修改其不可变 importance，不用于新的 structured flow。

## 13. Privacy、Security 与 Diagnostics

### 13.1 Push privacy

- structured JSON、附件、E2EE、ciphertext、system/control 和 unsafe input 的 provider title/body 使用 generic privacy 文案。
- Message Service 不复制 `summary`、`detail`、raw JSON、完整 DID、签名或内部字段到 Push。
- Push envelope 只携带版本化 opaque event/target/identity/thread/message refs 和 expiry。
- 点击后必须先 Core sync/commit，再用 opaque `mid` 匹配 committed message，最后打开 canonical conversation；unmatched/expired/ambiguous 只回 conversation list。

### 13.2 Presentation receipt

发送 exact-once 与展示 exact-once 分开：

1. Skill/CLI：稳定 `client_message_id + idempotency_key`；
2. Message Service/Core：canonical message ID 与 event receipt；
3. AWiki Me：`(owner_identity_id, event_id)` presentation receipt；
4. native：owner + event 派生稳定 provider ID。

App ledger 只保存：

- owner hash；
- event hash；
- full digest 与稳定 native ID；
- 单调 disposition；
- 时间与低敏 reason code。

禁止保存 payload、summary、detail、DID、conversation ID、message body 或凭证。每 owner 最多 4096 条，terminal receipt 保留 7 天；非 terminal claim 不因容量清理被删除。

推荐状态：

```text
claimed
  -> suppressed_foreground
  -> suppressed_muted
  -> presented_app
  -> provider_presented
  -> deferred_provider
  -> downgraded_normal
```

`deferred_provider` 是 WS/Core-first 的 terminal ownership 记录：它声明 App 不会创建后台 native notification，不声明 provider 已成功展示。

状态必须单调；先 durable claim，再 native submit。崩溃恢复复用同一 stable ID。

### 13.3 Diagnostics

日志与指标只允许低基数、无内容字段，例如：

- schema classification；
- requested/effective level；
- gate reason code；
- presentation disposition；
- platform/channel class；
- latency、count、age bucket。

不得记录 raw exception、正文、payload、完整 identity、Token、路径或 provider secret。

## 14. Ownership

| Concern | 唯一 owner | 禁止的替代 owner |
|---|---|---|
| schema 名、字段、闭合枚举、线级限制 | `awiki-cli-rs2/docs/architecture/contracts/` | AWiki Me、Message Service、Skill、system-test 自建权威 schema |
| validator、visible/control classifier、message/conversation/unread/summary/send/outbox | Rust `im-core` | Widget、CLI handler、Push callback |
| identity pin、full Handle resolve、dry-run、JSON envelope | `awiki-cli` 薄适配层 | Skill 裸 RPC、第二发送栈 |
| card domain model 与 kind renderer | AWiki Me domain/presentation | SDK DTO Widget 直渲、Message Service |
| trust、mute、foreground、age、rate-limit、receipt | AWiki Me `MessageSyncCoordinator` 下的 presentation policy service | Notification facade、provider payload |
| native/local submit | typed AWiki Me `NotificationFacade` | mapper、Widget、remote sync coordinator |
| structured background visible notification | Message Service / EMAS provider NOTICE | App `NotificationFacade`、WebSocket/Core commit path |
| Push outbox、installation、privacy envelope | Message Service `im-push` | AWiki Me payload、User Service lookup in worker |
| provider request | Message Service EMAS adapter | App server credentials |
| WebSocket/Push/startup/resume 收敛 | AWiki Me `MessageSyncCoordinator` | realtime/Push callback 直接写 UI |
| 跨仓行为与真实 oracle | `awiki-system-test` + AWiki Me E2E | source guard 冒充行为测试 |

本 PRD 是产品与 ownership 决策入口，不复制 JSON Schema 为第二权威。字段发生不兼容变化时，发布后必须新增 `awiki.agent.message.v2`，不能原地放宽 v1。

## 15. API/Core Handoff

### 15.1 必须复用

- 现有 `msg send --payload/--payload-file`；
- `--client-message-id`、`--idempotency-key`、`--dry-run`；
- `SendMessageRequest::Payload` 与现有 Direct send/outbox；
- Core SQLite committed projection、reliable sync、conversation/timeline patch；
- AWiki Me `MessageSyncCoordinator`；
- Message Service `im-push::notification_from_job`、outbox lease 和 provider adapter。

### 15.2 Core/API 要求

1. 在 `im-core` 建立唯一 typed `AgentMessageV1` validator/classifier。
2. classification 顺序固定：

```text
exact awiki.agent.message.v1
  -> valid visible / invalid visible
known control or unknown awiki.*
  -> control
other JSON
  -> existing behavior
```

3. valid visible 贡献一次 timeline、summary、unread；invalid visible 贡献一次 generic placeholder；unknown `awiki.*` 保持 hidden。
4. Core/Flutter SDK 暴露 validated structured projection，AWiki Me Widget 不直接解析 raw JSON。
5. generic payload API 可以保留，但不能绕过 exact schema validator 或成为第二 owner。
6. 首期 typed Agent send 只允许 Direct、plain transport-protected；Group、E2EE 和 structured attachment 返回稳定 unsupported code。
7. minimum-app-version gate 不满足时，在发送副作用前返回 `receiver_capability_unverified`。
8. source/realtime/sync 重放收敛到相同 event/message；不按正文去重。

### 15.3 Fake seam

允许使用：

- fake clock；
- fake active Agent inventory；
- fake preference/mute store；
- fake receipt store；
- fake typed notification facade；
- fake Push provider/directory。

这些 seam 用于确定性测试，不证明真实 Push、真机声音/振动、系统权限或用户可见性。

## 16. UI/UX Handoff

UI 实现前必须生成并由用户选择以下恰好三套方向：

### 16.1 Quiet Signal

延续现有聊天气泡，用细色条、轻量图标和标题区区分 kind；urgent 使用红色 signal rail 与短促 pulse。优点是最贴近当前 AWiki Me、阅读干扰小。

### 16.2 Action Ledger

采用任务账单式卡片，强化 label、summary、detail 和状态层级。优点是信息密度高，适合 Agent 任务流；代价是卡片更像工作台。

### 16.3 Callout Strip

normal card 保持轻量，urgent 在卡片顶部增加高对比“紧急呼叫”条和呼吸边框。优点是识别最强；代价是视觉侵入最高。

三套方向都必须包含：

- `message`、`task_result`、`alert normal`、`alert urgent`；
- compact/mobile 深浅色；
- incoming/outgoing context；
- detail 缺失、超长、换行和本地化；
- foreground urgent callout；
- 设置页的 opt-in、mute、permission denied/allowed；
- 动态字体、屏幕阅读器、色彩非唯一编码和 Reduce Motion。

用户选择前不得编码卡片视觉或动效；可以先实现与视觉无关的 schema、Core classifier 和 typed domain contract。

## 17. Acceptance Matrix

### 17.1 Schema/Core

- `ANOT-CONTRACT-001`：valid 三种 kind、两种 level、字段边界通过。
- `ANOT-CONTRACT-002`：extra field、超限、controls、bidi、secret/path/log 输入 fail closed。
- `ANOT-CORE-001`：exact visible exception 早于 broad `awiki.*` control。
- `ANOT-CORE-002`：valid visible 的 timeline/recents/unread 一致且 exact-one。
- `ANOT-CORE-003`：invalid visible 只显示 generic placeholder，不显示 raw JSON。
- `ANOT-CORE-004`：unknown future `awiki.*` 继续 hidden。
- `ANOT-CORE-005`：reserved notification schema 不贡献 timeline/unread/Push。

### 17.2 API/Skill

- `ANOT-API-001`：identity pin、完整 target resolve、argv、dry-run 和成功 oracle。
- `ANOT-API-002`：相同 event 使用稳定 client/idempotency identity；ambiguous result 不重试。
- `ANOT-API-003`：urgent 需要显式授权。
- `ANOT-API-004`：Direct-only；Group/E2EE/attachment 明确 unsupported。
- `ANOT-COMPAT-001`：minimum-app-version 未满足时零副作用拒绝，绝不双发。

### 17.3 App/Card/Policy

- `ANOT-UI-001`：三种 kind 与 urgent chrome 消费 validated domain model。
- `ANOT-UI-002`：payload title/conversation/URL 不影响展示或导航。
- `ANOT-POLICY-001`：trusted/untrusted、opt-in、mute、age、sender/account rate-limit 全组合。
- `ANOT-POLICY-002`：foreground normal 静默；foreground urgent 只触发一次。
- `ANOT-RECEIPT-001`：stable ID、replay、crash resume、collision fail closed、retention。
- `ANOT-EPOCH-001`：旧 identity/tenant/SessionEpoch 不展示、不 ack、不导航。
- `ANOT-A11Y-001`：动态字体、屏幕阅读器、对比度、Reduce Motion。

### 17.4 Push/Platform

- `ANOT-PUSH-001`：structured JSON 始终 generic provider title/body。
- `ANOT-PUSH-002`：opaque envelope 不包含 DID、正文、summary/detail、message ID 原文。
- `ANOT-PUSH-003`：provider-presented + WebSocket + App callback 最终一个 active notification identity。
- `ANOT-ANDROID-001`：provider normal v2 channel 独立且静音；urgent v1 仅验证 typed inactive seam；不改旧 channel importance。
- `ANOT-ANDROID-E2E-001`：命名真机 foreground/background/killed/cold-open。
- `ANOT-ANDROID-E2E-002`：命名真机一次短声、一次振动、permission denied、mute/replay。
- `ANOT-MACOS-E2E-001`：Notification Center 可见性与点击。
- `ANOT-IOS-E2E-001`：在 server remote delivery blocker 关闭后，验证 foreground/background/killed/open。

## 18. 阶段、灰度与回滚

### Phase 0：PRD 与视觉门禁

- 冻结本 PRD、唯一 schema owner 和 acceptance IDs。
- 生成三套视觉并等待用户选择。

### Phase 1：Contract/API/Core

- JSON Schema、typed validator/classifier、Core projection、CLI/Skill typed send、minimum-app-version gate。
- 保持现有 text/attachment/status/control 行为不回归。

### Phase 2：AWiki Me 卡片与本地 presentation

- 选定 UI；typed facade、policy、stable ID、hash-only receipt、active normal provider channel 与 inactive urgent channel seam。
- 完成 App 前台的 local urgent cue/callout；后台固定 provider-only generic normal，不实现 local urgent。

### Phase 3：Android generic Push 与 exact-one

- Message Service structured JSON generic normal mapping。
- provider-presented suppression、WebSocket/Push convergence、点击 fence。
- 执行 Android 真机验收。

### Phase 4：Future blockers

- recipient-bound offline trust/preference/mute input；
- killed-process trusted urgent；
- iOS installation resolve/server delivery；
- automatic mixed-version capability negotiation；
- Group/E2EE/structured attachment 独立版本。

### 灰度

- 首期不是账号百分比灰度，而是 minimum-app-version + exact schema feature gate。
- schema sender 默认关闭；只有确认接收端版本满足门槛后开启。
- urgent opt-in 默认关闭；normal structured 与 urgent presentation 使用独立开关。
- Android channel 一旦创建，其行为受用户控制；更改不可变 channel 行为必须使用新 channel ID。

### 回滚

- 关闭 sender structured feature，停止产生新 v1；不得双发 fallback。
- 关闭 urgent presentation 时，已 committed structured message 仍按 normal card/notification 展示。
- 保留 decoder，不能因回滚让已接收 v1 消失。
- 不删除 Core messages 或 presentation receipts。
- 不原地修改旧 Android channel。

## 19. 状态与证据边界

### PASS

- PRD v2 的消息类型、唯一 visible schema、urgent 定义、ownership、隐私、兼容与阶段边界已冻结。
- 最新四仓 worktree 基于当前 `origin/release/0714` 建立，可进入本地实现。

### BLOCKER

1. App killed 时缺少 recipient-bound、可撤销、可离线验证的 Agent trust 与用户 preference/mute 输入，不能安全提升 urgent 或保证 mute。
2. Message Service Push worker 当前固定解析 Android installation；iOS remote delivery 未闭环。
3. receiver automatic capability discovery/fallback 没有权威输入；首期只能 minimum-app-version gate。

### UNVERIFIED

- Android/iOS 真机声音、振动、权限、后台/杀进程、OEM 限制和 cold-open；
- macOS Notification Center；
- mixed-old-client 真实兼容；
- deployed Message Service/EMAS Push；
- 用户实际看到、听到或感受到提醒。

## 20. 权威参考

- [Conversation presentation ownership](../conversation-presentation-ownership.md)
- [Android remote Push](../android-remote-push.md)
- [iOS remote Push](../ios-remote-push.md)
- [IM Core SDK architecture](../../../awiki-cli-rs2/docs/architecture/im-core-sdk-architecture.md)
- [IM Core public API](../../../awiki-cli-rs2/docs/api/im-core-public-api.md)
- [Flutter SDK](../../../awiki-cli-rs2/docs/flutter-sdk/awiki-im-core-flutter-sdk.md)

实施时必须同步上述权威文档；Harness 中仍将 Push 标为 `DEFERRED` 的摘要也必须按当前子仓实现与真实证据边界更新，避免发布结论冲突。
