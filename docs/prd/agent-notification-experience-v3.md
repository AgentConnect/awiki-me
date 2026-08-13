# AWiki Agent 分级消息与 Android 存活后台全屏通知 PRD v3

状态：`Frozen contract candidate - alive-background only`

日期：2026-08-12

适用基线：`release/0714`

基线记录：本次合同核对时 `origin/release/0714` 为
`a1151e3029e767b51bddccc2f089e8b02e318173`。当前 App candidate 仍需在实现前做
preservation-first 基线移植；本文不授权 rebase、merge、commit 或覆盖既有 dirty 修改。

版本关系：本文件只替代 v2 中 Android structured urgent 的 foreground/background presentation
边界。未明确替代的 public schema、卡片、隐私、兼容和安全规则继续沿用 v2；v2 保留为历史记录。

## 1. 决策摘要

本阶段只实现以下闭环：

- App 前台：继续使用 AWiki Me Widget 树内的全屏 urgent overlay；
- App 后台但进程存活：收到 EMAS `MESSAGE` dirty hint 后，由 App 完成 Core sync/commit 和当前
  认证账号 policy，再决定提交 Android full-screen intent notification；
- full-screen special access 缺失：降级为同一 stable ID 的高优先级声振通知；
- App process dead、用户划掉后进程已退出、killed、force-stop 和 OEM 冻结：本阶段不展示
  urgent，不补响，明确为非目标与 `BLOCKER`。

唯一可见消息 schema 保持 `awiki.agent.message.v1`，不增加、不删除、不放宽任何字段。EMAS
`MESSAGE` 只是无内容、可重复、可丢失的不可信同步提示；raw Push、provider 类型、extra 字段或
服务端“urgent”分类都不能授权 full-screen、声音或振动。

存活后台最终 presentation owner 是 AWiki Me：只有 App 看到 Core 已提交的 valid structured
message，并从当前认证 recipient scope 获得 trust、urgent opt-in、mute、age、rate-limit 和 session
结论后，才可展示。Message Service 只负责选择 transport 和发送 opaque dirty hint，不作最终
presentation 授权。

本功能不是电话、VoIP 或闹钟。不得使用 CallStyle、Telecom、call/alarm category、exact alarm、
alarm/voice-call audio usage、后台直接 `startActivity()`、DND bypass 或 Notification Policy Access。

## 2. 范围与非目标

### 2.1 本阶段范围

1. Direct、transport-protected、valid `awiki.agent.message.v1`。
2. `level=urgent` 的前台 overlay 和 Android 存活后台 FSI/fallback。
3. `message | task_result | alert` 三种 kind；`alert + urgent` 产品名继续为“紧急呼叫”。
4. App Core commit 后的 trust/opt-in/mute/age/rate/permission policy。
5. foreground/background race、WS/Push/replay exact-one、30 秒 cue、stop 与 canonical click。
6. Android 14+ full-screen special access 和 Google Play 风险边界。

### 2.2 明确非目标

- process dead、killed、force-stop 或 OEM 冻结后的 urgent 展示；
- 进程死亡后由厂商 auxiliary `NOTICE`、popup Activity 或新 transport 唤醒 verifier；
- killed-process native-first ticket、离线验签或 Flutter 启动前 receipt；
- Group、E2EE、structured attachment；
- iOS/macOS/Windows/Web 新增 urgent native 行为；
- DND bypass、Apple Critical Alert、Android overlay permission、后台直接启动 Activity；
- Coding Agent lifecycle 必达；
- commit、push、PR、部署、迁移、安装、设备权限修改或真实消息发送。

process-dead urgent 是后续独立版本的 `BLOCKER`，不能借本阶段实现顺带开启。用户下次启动 App 时
Core 可正常同步并显示 card，但不得补 full-screen、铃声或振动。

## 3. 不变的 public wire contract

唯一用户可见 schema 仍为：

```json
{
  "schema": "awiki.agent.message.v1",
  "event_id": "evt_task_20260811_001",
  "task_name": "AWiki Me 代码检查",
  "kind": "alert",
  "level": "urgent",
  "content": {
    "summary": "需要立即处理",
    "detail": "请打开会话查看详情。"
  },
  "action": {
    "type": "open_conversation"
  }
}
```

字段、枚举、长度、`additionalProperties=false`、runtime safety filter、Direct-only、
minimum-app-version 和 sender 授权沿用 v2。特别是：

- 不新增 `urgent_call` kind；
- payload 不新增 `full_screen`、`sound`、`channel`、`sender`、`conversation`、URL、provider
  priority 或 permission 字段；
- `level=urgent` 是 presentation request，不是授权事实；
- `awiki.agent.notification.v1` 继续 reserved/hidden，不发送、不贡献 timeline/unread/Push；
- transport 改为 `MESSAGE` 不创建第二条 AWiki message，也不改变 send acceptance。

只有 im-core committed message 可以贡献 timeline、recents、unread、canonical conversation、click
target 和 validated structured projection。Push 不能创建、替换或补写 message truth。

## 4. Transport 决策

### 4.1 当前阶段必须选择 `MESSAGE`

当前 Receiving Home 没有可信的 im-core validated projection。Message Service 因此不得复制完整
`awiki.agent.message.v1` decoder/validator；它只允许做一个闭合的、非授权性的 transport candidate
识别：

```text
Direct
AND transport-protected
AND content-type == application/json
AND bounded JSON root is object
AND root.schema is exact string "awiki.agent.message.v1"
AND root.level is exact string "urgent"
```

该识别器只读上述 transport/profile/content-type 和两个 exact discriminator，不验证 object closure、
extra fields、`event_id`、`task_name`、`kind`、`content`、`action`、长度、controls、bidi、secret/path
filter 或字段组合。它不是 public schema validator，不产生 `valid_agent_message` 事实，也不能被 App
用作 presentation authorization。完整 validation/classification 继续唯一归 im-core。

| transport candidate | EMAS transport | provider visible notification | App behavior |
|---|---|---|---|
| exact schema + exact urgent discriminator（无论其余 v1 字段最终 valid/invalid） | `MESSAGE` only | 无 | 仅 dirty hint；App Core 完整验证，valid 才进入 policy，invalid fail closed |
| exact schema + non-urgent/missing/invalid level | 既有 `NOTICE` | generic normal 或既有 quiet 行为 | App Core 完整验证；不得提升 urgent |
| ordinary text/attachment | 既有 `NOTICE` | 既有 privacy-safe notification | 不变 |
| malformed JSON / unknown schema | 既有 fail-closed normal/quiet policy | generic 或无 | 不得由文案猜 urgent |

一个 urgent transport candidate 只能选择一个 provider transport：不得同时发送 `MESSAGE + NOTICE`。
双发会让 provider NOTICE 绕过 App mute/opt-in policy，并与 App FSI 形成两个 native identity。

Message Service 选择 `MESSAGE` 只表示“存在一个候选 structured urgent，接收端应同步”；它不证明
sender trusted、用户 opt-in、conversation unmuted、消息新鲜或 App 在后台。App 必须忽略 raw Push
中的 title/body/level/schema/sender/conversation/route/permission；只接受 allowlisted opaque sync refs
和 expiry，随后从 Core committed message 重建全部事实。

若 Message Service 无法安全完成上述闭合 discriminator 识别，必须 fail closed 到 normal/quiet 既有
行为，不得从 JSON substring、summary 文案或 provider metadata 猜测。候选随后被 im-core 判为
invalid 时，`MESSAGE` 本身不可见，App 只执行 invalid-visible 的既有 placeholder/quiet 语义，零
overlay、FSI、sound 或 vibration。

### 4.2 为什么本阶段不使用 `NOTICE`

EMAS `NOTICE` 由 SDK或厂商通道直接创建可见通知，App 无法在展示前完成 Core commit、recipient
policy 和 presentation receipt。因此它不适合作为 structured urgent 的存活后台 transport。
normal 通知继续使用 NOTICE，是因为 normal 不要求 App 提升为高打扰展示。

### 4.3 官方证据与 process-dead 边界

阿里云官方合同明确：进程终止即 offline；`MESSAGE` offline 时不能交付。offline notification 走
厂商第三方 auxiliary channel；辅助通知不会在到达时调用 App `onNotification`，而 `NOTICE` 不能
自定义 notification `PendingIntent`。这些限制正好形成阶段边界：

- process + Flutter channel alive：`MESSAGE` 可作为 dirty hint，本阶段实现；
- process dead：`MESSAGE` 不可用，明确非目标；
- 不将 `MESSAGE` 转 notification，不配置 urgent auxiliary popup，不以 NOTICE 兜底 urgent；
- 不尝试在 process-dead 路径添加 verifier、receipt、FSI 或声振。

官方依据：

- EMAS message/notification 与 offline 语义：<https://help.aliyun.com/en/document_detail/614897.html>
- 辅助通知不触发到达时 `onNotification`：<https://help.aliyun.com/document_detail/477864.html>
- `NOTICE` 不能自定义 `PendingIntent`：<https://help.aliyun.com/document_detail/58554.html/>
- 厂商 auxiliary Activity 路径：<https://help.aliyun.com/en/document_detail/434685.html>

## 5. Lifecycle predicate

### 5.1 精确状态定义

一次 App-owned 存活后台 presentation 只有在以下条件同时成立时 eligible：

```text
process_alive
AND flutter_engine_attached
AND remote_push_method_channel_attached
AND active_authenticated_session_exact
AND native_activity_resumed == false
AND dart_app_lifecycle != resumed
AND current_presentation_claim_not_terminal
```

具体要求：

- `process_alive` 只表示当前 OS process 存在，不从 provider 状态或历史 heartbeat 推断；
- Flutter engine 与 remote Push MethodChannel 必须已 attach，能把 `MESSAGE` 交给当前 coordinator；
- session fence 必须精确绑定 tenant、storage scope、owner identity/DID、account、device auth generation
  和 App session generation；
- native `Activity.onPause/onResume` 状态与 Dart lifecycle 必须双重确认；任一未知、异常或互相矛盾
  都 fail closed，不 FSI；
- `inactive/hidden/paused/detached` 不能只凭枚举视为后台；`detached` 或 channel detached 属于非目标；
- window focus 不是 owner，也不能单独判前后台。

本合同把“存活后台”定义为 Activity 已 paused、App process/Flutter channel 仍存活且 session 可用。
Activity stopped 可以属于该范围，但必须仍满足上面的 engine/channel/session predicate。

### 5.2 Foreground/background race

`MESSAGE` 到达、Core sync、policy I/O 和 native submit 之间可能发生 lifecycle 切换：

1. 到达时只记录 dirty hint，不 claim presentation；
2. Core commit 后以 `(owner scope, event_id, canonical message identity)` durable claim；
3. policy 完成后、提交 native surface 前重新读取 native + Dart lifecycle 和 session fence；
4. 若此时 foreground：同一 claim 转 foreground owner，只允许 App overlay/cue；零 tray/FSI；
5. 若仍满足 alive-background predicate：同一 claim 进入 FSI/fallback；
6. 若 engine/channel/session 丢失或状态不明：terminal suppress/defer，不在重启后补响；
7. native submit 后 Activity resume：取消/replace 同一 native ID，停止后台 cue；必要时显示同一 event 的
   foreground card/overlay，但不得第二次响铃或振动。

任一时刻只有一个 owner disposition；不得以两个独立 ledger 分别记录 overlay 与 native notification。

## 6. Recipient policy 与 owner map

### 6.1 App 最终 policy

App 必须在 Core committed valid v1 projection 后，按以下固定顺序评估：

1. exact schema/runtime safety valid 且 `level=urgent`；
2. committed sender DID 精确命中当前认证 recipient scope、当前 SessionEpoch 的 active Agent inventory；
3. User Service 账号私有 urgent preference 为 `enabled`；`unset/disabled/error = deny`；
4. canonical conversation 未 mute；mute 必须来自当前认证账号的权威同步状态；
5. committed authoritative receive/accepted time 不在未来且不超过 15 分钟；
6. 15 分钟窗口每 sender 不超过 3 次、每 account 不超过 6 次；
7. session/lifecycle predicate 精确；
8. notification permission、urgent channel 与 full-screen access 按第 8 节决定展示或降级。

Handle、display name、DID path、payload 自报字段、Push transport/type 或 provider extra 都不能提升
trust。policy store/read 异常一律 fail closed。Message Service 不需要在本阶段新增 trust/preference/
mute 服务端 presentation 裁决；这些事实由 App 在当前认证 recipient session 中消费。User Service
仍是 trust/preference/mute 数据权威，App 是 alive-background presentation 决策 owner。

### 6.2 唯一 owner map

| Concern | 唯一 owner | 禁止的替代 owner |
|---|---|---|
| public schema/validator/classifier | im-core contract owner | Widget、Push callback、Message Service 第二套 schema |
| minimal urgent transport candidate discriminator | Message Service | 把 discriminator 结果升级为 schema valid 或 presentation allow |
| message/conversation/timeline/unread/route | im-core committed projection | raw Push、Activity extras |
| recipient trust/preference/mute facts | User Service account state | provider payload、sender 文案、本地猜测 |
| urgent transport selection/outbox/provider request | Message Service | User Service、App 第二发送队列 |
| foreground/background lifecycle truth | AWiki Me native + Dart session-fenced lifecycle | provider online flag、window focus alone |
| alive-background final policy/presentation | AWiki Me MessageSyncCoordinator 下的 policy service | Message Service、EMAS NOTICE、raw Push receiver |
| native FSI/fallback submit | typed AWiki Me NotificationFacade/native adapter | Widget、Push callback 直接 notify |
| foreground overlay/cue | AWiki Me presentation coordinator | Message Service/provider |
| presentation receipt/stable native ID | AWiki Me owner-scoped durable store | random ID、provider delivery ID、内存-only dedupe |
| cross-repo/device oracle | awiki-system-test + named AWiki Me E2E | build/API/provider accepted 冒充 E2E |

Message Service 是 transport owner，不是本阶段后台 presentation owner。EMAS `MESSAGE` callback 只能
调用统一 sync coordinator，不能直接调用 notification facade、cue controller 或 navigation。

## 7. Exact-one 与 receipt

### 7.1 Presentation identity

稳定 identity 必须由以下 committed facts 派生：

- exact owner/storage scope；
- sender identity；
- canonical message identity；
- validated `event_id`；
- schema version。

相同 identity 在 WS、HTTP sync、EMAS MESSAGE、App resume 和 policy reconciliation 中复用同一 receipt
和 native ID。provider delivery ID 只用于触发 ack，不得作为 presentation identity。相同 event_id
映射到不同 canonical message 时为 collision，fail closed。

### 7.2 单调 disposition

```text
claimed
  -> presented_foreground_overlay
  -> presented_foreground_cue
  -> presented_background_fsi_requested
  -> presented_background_fallback
  -> suppressed_muted
  -> suppressed_untrusted
  -> suppressed_opt_out
  -> suppressed_expired
  -> suppressed_rate_limited
  -> suppressed_permission
  -> suppressed_channel
  -> suppressed_lifecycle_unknown
  -> suppressed_process_detached
  -> suppressed_collision
```

先 durable claim，再做任何 cue/overlay/native submit。提交后使用同一 stable native ID replace/no-op，
并设置 only-alert-once。crash/reconnect/replay/resume 不得重响；process-dead 后重启看到非 terminal
claim 时也只 sync/card 和 terminal suppress，不补 urgent。

receipt 只保存 owner/event/message digest、stable native ID、低敏 reason、时间和 cue state；不保存
payload、summary、detail、task name、DID、conversation、Token 或 provider secret。terminal 至少保留
7 天、每 owner 至多 4096；非 terminal claim 不因容量清理而丢失。

### 7.3 到达顺序

| 顺序 | 结果 |
|---|---|
| WS/Core-first，Activity paused | committed message claim/policy 后可 FSI；稍后 MESSAGE 只 ack/no-op |
| MESSAGE-first | dirty sync → Core commit → policy；raw hint 不展示 |
| WS + MESSAGE 同时 | sync 合并；一个 claim、一个 native ID |
| foreground 到达后 pause | foreground owner一旦 terminal，不因 pause 再 FSI |
| background decision 中 resume | lifecycle recheck 转 foreground或 suppress；不双响 |
| native submit 后 resume | cancel/replace同一 ID并 stop；不重新播放 overlay cue |
| process/channel detached | 不展示；重启后不补响 |

## 8. Android permission、channel 与 FSI fallback

### 8.1 公开 API 与用户控制

实现只使用：

- manifest `USE_FULL_SCREEN_INTENT`；
- Android 13+ `POST_NOTIFICATIONS`；
- Android 14+ `NotificationManager.canUseFullScreenIntent()`；
- 用户从 AWiki 设置页显式点击后打开 `ACTION_MANAGE_APP_USE_FULL_SCREEN_INTENT`；
- 新的不可变 urgent channel，importance high；
- explicit、immutable、package-bound `PendingIntent` 指向 non-exported Activity。

不得在消息到达时自动打开特殊权限设置。DND、静音模式、音量、channel importance/sound/vibration、
锁屏可见性和 OEM 策略具有最终决定权。不得申请 Notification Policy Access、设置 bypass DND，或
用 App player 绕过被用户静音/禁用的 channel modality。

### 8.2 决策矩阵

| Notification permission | urgent channel | FSI access | App behavior |
|---|---|---|---|
| allowed | enabled/high | allowed | 同一 stable ID 提交 FSI notification；系统决定实际 Activity/heads-up |
| allowed | enabled/high | denied/unavailable | 不附加 FSI；同一 ID 高优先级声振 heads-up/tray fallback |
| allowed | silent/low | 任意 | 按用户 channel 展示；不以 App cue 恢复被禁 modality |
| allowed | blocked | 任意 | suppress，前台设置页提示恢复；不后台 cue |
| denied | 任意 | 任意 | 无 Activity/tray/后台 cue；receipt `suppressed_permission` |
| unknown/error | 任意 | 任意 | fail closed；不猜 allowed |

Android 14+ 默认自动授予仅面向核心功能是电话/视频通话或闹钟的 App。AWiki 不属于该类别，只能
依赖用户明确授予并始终提供 fallback。Google Play 会审查权限与核心用途；没有真实 Play Console
证据时发布资格为 `UNVERIFIED`。审核不允许时，production flavor 必须移除/禁用 FSI 并走 fallback，
不得伪装 call/alarm。

官方参考：

- Android 14 secure FSI：<https://developer.android.com/about/versions/14/behavior-changes-14#secure-fsi>
- Android full-screen notification：<https://developer.android.com/develop/ui/compose/notifications/create-notification#full-screen>
- Google Play FSI policy：<https://support.google.com/googleplay/android-developer/answer/16558241?hl=en>

## 9. Overlay、Activity、cue、stop 与 click

### 9.1 前台

- other conversation：App 内全屏 overlay + 最长 30 秒 cue；零 tray/FSI；
- target conversation visible：card + 一次有界 cue，零第二 overlay/tray/FSI；
- normal：静默提交 card；
- mute：card 保留，零 cue/overlay。

### 9.2 存活后台

- FSI allowed：提交 FSI notification；锁屏通常进入专用 Activity，解锁时系统可能仅 heads-up；
- FSI denied：同一 ID 高优先级 fallback；
- 专用 Activity 必须 non-exported，不信任 Intent 文案/route；内容来自 receipt 对应的 Core committed
  projection，匹配前只显示本地化 generic 文案；
- Activity 不是来电 UI，不使用接听/拒接、电话号码或电话 category。

### 9.3 30 秒 cue 与停止

高打扰 cue 最长 30 秒。所有 modality 必须先通过 notification/channel/DND policy；channel 被用户
静音时不得用 App ringtone/vibrator 绕过。

以下事件幂等立即 stop：

- “立即处理”；
- “关闭”、Back、Activity finish；
- 点击或移除 notification；
- 30 秒 timeout；
- App resume 或进入 target conversation；
- owner/session/lifecycle fence 失效；
- process teardown。

cue state 单独记录 `not_started | active | stopped_action | stopped_dismiss | stopped_timeout |
stopped_resume | stopped_fence | stopped_process`，不得通过改 disposition 重播。

### 9.4 Click route

点击只携带 opaque message ref。顺序固定：stop cue → cancel/replace stable ID → 激活同一账号 session
→ Core sync/commit → 由 committed identity 重新派生 opaque ref → exact match 后进入 canonical
conversation。missing、expired、unmatched、ambiguous 或 stale tenant/session 只进入 conversation list，
不使用 Push/payload route，不 mark read。

## 10. 状态矩阵

| 状态 | Owner | valid authorized urgent | FSI denied | mute | process transition |
|---|---|---|---|---|---|
| foreground, other conversation | App foreground coordinator | overlay + bounded cue | 不影响 overlay | suppress cue/overlay | terminal foreground 不因 pause 重播 |
| foreground, target visible | App foreground coordinator | card + bounded cue | 不影响 | suppress cue | 同上 |
| Activity paused + process/Flutter/channel alive | App alive-background policy | FSI notification | same-ID high priority fallback | suppress | detach before submit 则 suppress |
| lifecycle native/Dart disagreement | 无 eligible owner | suppress | suppress | suppress | 不猜状态 |
| process dead/killed | 本阶段无 owner | 不展示、不补响 | 不适用 | 不适用 | 下次启动只 sync/card |
| force-stop/OEM frozen | 本阶段无 owner | 不承诺 delivery | 不适用 | 不适用 | 用户重启后只 sync/card |
| provider MESSAGE replay | 无新 owner | same receipt no-op | same ID no-op | no-op | 不重响 |
| normal NOTICE | provider normal owner | generic normal only | 不适用 | 沿用 normal 合同 | 不进入 urgent policy |

## 11. 对 Message Service 的精确 handoff

1. public `awiki.agent.message.v1` 零变化；复用 canonical Direct commit、outbox lease、installation
   directory 和 EMAS adapter，不建第二消息事实或第二队列。
2. 不复制 v1 schema validator。只按第 4.1 节六个条件做 minimal transport candidate 识别；命中
   exact schema + exact urgent discriminator 即选择 `PushType=MESSAGE`，结果始终标为 candidate，
   不能发布/持久化为 `valid_agent_message`。其他 structured normal/ordinary 保持现有 NOTICE。
3. urgent MESSAGE 不配置 `AndroidRemind`、offline conversion、vendor popup 或同时 NOTICE；进程死亡
   时允许不交付，这是本阶段明确语义。
4. MESSAGE title/body/ext 仅使用 generic/opaque sync hint：版本、delivery/event/target/message opaque
   refs 和 expiry；不含 schema、level、summary/detail、task name、DID、conversation ID、URL 或权限。
5. App ack 只证明 dirty hint 已处理；provider accepted 不证明 Core commit、FSI、声音或振动。
6. retry 复用稳定 delivery identity；不得通过重新选择 NOTICE 提升“到达率”。
7. focused tests 必须覆盖 exact urgent discriminator → MESSAGE only、normal → NOTICE、候选但其余
   schema invalid → MESSAGE invisible + App Core reject、extra/invalid kind/content/action 不在 Message
   被判 valid、malformed/unknown 不提升、零双发、privacy allowlist、retry identity 和 offline
   conversion disabled。

Message Service 本阶段无需新增 recipient trust/preference/mute presentation authority。它无法从 Push
层授权 FSI；App 必须在当前认证 recipient session 中最终裁决。

## 12. 对 AWiki Me / Android 的精确 handoff

1. 实现前 preservation-first 将 App candidate 对齐
   `origin/release/0714@a1151e3029e767b51bddccc2f089e8b02e318173`；保留所有既有 dirty
   sound/vibration 工作，不 reset/clean/覆盖。
2. `onMessage` 只将 allowlisted opaque hint送入统一 `MessageSyncCoordinator`；不得直接 notify、cue、
   overlay 或 navigate。
3. Core commit 后复用 validated projection、current agent inventory、authenticated preference、canonical
   mute overlay/state、age/rate store 与 owner/session fence；raw Push 不参与 policy。
4. 实现第 5 节 native+Dart 双 lifecycle predicate，并在 claim 前、policy 后、native submit 前重验。
5. foreground overlay 与 background FSI/fallback 共用一份 owner-scoped receipt 和 stable native ID；
   WS/MESSAGE/resume/replay/race 只能终结一次。
6. Android 14+ 使用 `canUseFullScreenIntent()`；FSI 缺失走 same-ID fallback；notification/channel 拒绝
   则 suppress，绝不后台 App cue 绕过。
7. cue 最长 30 秒；第 9 节所有路径 stop；Activity/click 只经 Core exact canonical route。
8. 不增加 killed/process-dead receiver、native-first verifier、vendor popup 或 cold-start urgent replay；
   相关路径保持 untouched。
9. unit/instrumentation tests 必须覆盖 lifecycle disagreement、resume race、WS/MESSAGE orders、claim crash、
   permission/channel/FSI combinations、DND modality、stop 和 route negative cases。

## 13. 验收矩阵

状态只允许 `PASS / FAIL / BLOCKER / UNVERIFIED / SKIPPED`。真机 evidence 必须记录 device/OS、
package/version、APK SHA-256、App/Core/Service candidate SHA、process PID、Flutter channel、Activity/Dart
lifecycle、session fence、notification permission、channel、FSI access、DND/ringer、receipt disposition、
Activity 可见、sound、vibration、stop time 和 route。

### 13.1 Contract / transport

| ID | Case | Oracle |
|---|---|---|
| `ANOT-V3-CONTRACT-001` | public schema | v1 byte/semantic contract 零变化 |
| `ANOT-V3-TRANSPORT-001` | exact schema + exact urgent minimal discriminator | one MESSAGE, zero NOTICE, offline conversion disabled；不产生 schema-valid 事实 |
| `ANOT-V3-TRANSPORT-002` | structured normal/ordinary | existing NOTICE behavior unchanged |
| `ANOT-V3-TRANSPORT-003` | urgent candidate 但其余 v1 字段 invalid/unsafe | MESSAGE 不可见；App Core reject；零 presentation |
| `ANOT-V3-TRANSPORT-004` | malformed/unknown/non-urgent | 不由 substring、文案或 provider metadata 提升 urgent |
| `ANOT-V3-OWNER-001` | Message worker source/behavior audit | 无第二完整 v1 decoder/validator；im-core 是唯一 valid classifier |
| `ANOT-V3-PRIVACY-001` | MESSAGE envelope | 只含 closed opaque allowlist，无内容/身份/route/permission |
| `ANOT-V3-TRUTH-001` | forged/raw Push urgent fields | zero presentation，必须等 Core valid commit |

### 13.2 Policy / lifecycle

| ID | Case | Oracle |
|---|---|---|
| `ANOT-V3-POLICY-001` | trusted + opt-in + unmuted + fresh + within rate | allow candidate presentation |
| `ANOT-V3-POLICY-002` | untrusted/opt-out/unset/muted/expired/rate/error | 分别 fail closed |
| `ANOT-V3-LIFECYCLE-001` | Activity paused + process/Flutter/channel/session alive | eligible alive-background |
| `ANOT-V3-LIFECYCLE-002` | native/Dart disagreement or channel detached | suppress，不猜后台 |
| `ANOT-V3-RACE-001` | background decision → resume | one owner；不双 FSI/overlay/cue |
| `ANOT-V3-RACE-002` | foreground commit → pause | foreground terminal；不补 FSI |

### 13.3 Exact-one / Android

| ID | Case | Oracle |
|---|---|---|
| `ANOT-V3-EXACT-001` | WS first → MESSAGE | one claim/presentation；MESSAGE ack/no-op |
| `ANOT-V3-EXACT-002` | MESSAGE first → Core | raw hint zero display；commit 后一次 |
| `ANOT-V3-EXACT-003` | simultaneous/replay/retry | one stable ID、one cue、one overlay/FSI |
| `ANOT-V3-EXACT-004` | crash after claim | process resume/start 不补 urgent，不重响 |
| `ANOT-V3-ANDROID-001` | foreground other/target conversation | overlay或card按矩阵，零 tray/FSI duplicate |
| `ANOT-V3-ANDROID-002` | alive background locked + FSI allowed | 专用 Activity、one ID，sound/vibration 分列 |
| `ANOT-V3-ANDROID-003` | alive background unlocked + FSI allowed | 记录 Activity/heads-up 实际结果，不夸大 |
| `ANOT-V3-ANDROID-004` | FSI denied | 无 Activity；same-ID high priority fallback |
| `ANOT-V3-ANDROID-005` | notification denied/channel blocked | zero Activity/tray/background cue |
| `ANOT-V3-ANDROID-006` | DND/ringer/channel silent | 无 bypass；各 modality 与系统设置一致 |

### 13.4 Stop / click / excluded states

| ID | Case | Oracle |
|---|---|---|
| `ANOT-V3-STOP-001` | action/close/Back/remove/timeout/resume/fence loss | 幂等 stop，最长 30 秒，资源释放 |
| `ANOT-V3-CLICK-001` | valid opaque ref | Core exact match 后 canonical conversation |
| `ANOT-V3-CLICK-002` | missing/expired/unmatched/ambiguous/stale session | conversation list only，不使用 payload route |
| `ANOT-V3-EXCLUDED-001` | process killed/dead | zero urgent display；重启只 card，不补响 |
| `ANOT-V3-EXCLUDED-002` | force-stop/OEM frozen | `SKIPPED`/`BLOCKER`，不声明支持 |
| `ANOT-V3-PLAY-001` | Play permission declaration/review | 真实 Console 证据；否则 `UNVERIFIED` |

## 14. 阶段门禁与回滚

### Gate 0：合同与基线

- 本 PRD frozen candidate；
- App preservation-first 对齐最新 release；
- Message/App 各形成 immutable candidate；
- reviewer 检查 owner、schema、privacy、lifecycle、exact-one 和 excluded states。

### Gate 1：Message transport

- minimal exact-schema + urgent transport candidate → MESSAGE only；normal → NOTICE；
- privacy-safe opaque envelope；
- offline conversion/vendor popup disabled；
- focused tests green。

### Gate 2：App alive-background loop

- MESSAGE dirty sync → Core commit → recipient policy → lifecycle recheck → FSI/fallback；
- receipt/race/permission/channel/cue/click tests green；
- process-dead path untouched。

### Gate 3：命名真机

- 仅 foreground 与 alive-background matrix；
- killed/force-stop 只验证没有误实现补响，不尝试使其交付；
- Play policy/production flavor 单独决定。

回滚：关闭 Message Service urgent MESSAGE routing 后，structured urgent 可按冻结的 generic normal/quiet
回滚策略处理，但不得同时双发。关闭 App urgent presentation 后，committed message 仍显示 card。
保留 decoder/receipt，不能删除消息或更换 identity 重发；Android channel 行为变化必须新建 channel。

## 15. 当前证据状态

### PASS

- public `awiki.agent.message.v1` 零变化；
- alive-background scope、App final owner、MESSAGE dirty-hint 与 lifecycle predicate 已冻结；
- minimal urgent transport candidate → MESSAGE-only、normal NOTICE、零双发决定已冻结；im-core 保持
  唯一完整 v1 validator/classifier；
- exact-one、permission/channel/FSI fallback、30 秒 stop/click 和 excluded-state matrix 已冻结；
- Android 14、Google Play 与 EMAS offline/NOTICE/PendingIntent 官方边界已核对。

### BLOCKER

1. process dead/killed/force-stop urgent 不在本阶段实现，后续需要独立 transport/安全/产品合同。
2. App candidate 尚未包含最新
   `origin/release/0714@a1151e3029e767b51bddccc2f089e8b02e318173`，实现前必须
   preservation-first 移植。

### UNVERIFIED

- P0110/Android 14+ foreground 与 alive-background FSI/fallback；
- MESSAGE proprietary channel 的真实存活后台到达、WS race 与 exact-one；
- sound、vibration、DND、channel、30 秒 stop 与 click route；
- provider/server deployment、Google Play review 与用户实际感知。

本文件没有授权代码、schema、其他文档、commit、push、PR、部署、迁移、安装、设备权限或消息操作。
