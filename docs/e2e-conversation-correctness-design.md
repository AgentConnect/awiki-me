# AWiki Me 会话正确性 E2E 完善方案

> 状态：实施中（阶段 1-4 主链路已落地，真实两进程 restart gate 已通过）  
> 日期：2026-07-16  
> 范围：AWiki Me 会话、消息、未读、用户名展示和多入口会话创建  
> 依赖架构：[Conversation Presentation And Message Rendering Ownership](conversation-presentation-ownership.md)

本文记录对 suite manifest、case catalog、Flutter flow/robot/oracle、生产 UI 展示面以及 `awiki-system-test` 可复用能力的审计、落地设计和当前实施状态。具体远端运行证据以 `.e2e/desktop-cli-peer/<run-id>/reports/` 中的脱敏报告为准，不能由本文替代。

## 1. 结论

当前 E2E 不是“完全没有严格断言”。Direct exact-one、发送终态、未读 `+1 -> 0`、重试、空会话保留、联系人入口 canonical ID 和建群后会话保留已经有一定深度。

真正缺口是：当前测试更容易证明“动作被执行了”或“Provider/Core 中有数据”，但没有统一证明用户最终看到的产品状态同时满足：

1. **语义唯一**：同一 Persona 或 Group 只有一个会话，而不是只检查某个已知 ID 出现一次。
2. **结果精确**：消息集合、ID、内容、发送人、归属会话和顺序都精确一致。
3. **可见 UI 正确**：不能用 Provider 正确代替会话行、页头、badge 或 sender label 真正显示正确。
4. **跨页面一致**：同一 `peerPersonaId` 在会话列表、页头、联系人、群成员和群消息中使用同一显示投影。
5. **过程也正确**：不能只等到最终状态；需要发现 `Unknown -> Handle -> 昵称`、短暂重复行或未读回弹。

因此，长期方案不是增加更多截图或更多 `find.text()`，而是建立**三层精确预期 + 语义化 UI 观测 + 严格 Oracle + 稳定窗口**的会话正确性测试体系。

### 1.1 当前实施状态

| 能力 | 当前状态 | 可执行证据 |
|---|---|---|
| Persona/Group 语义 exact-one | 已落地 | Direct、Contacts、Group focused flow + Oracle 反例单测 |
| 完整消息集合、顺序、同正文不同 ID、跨会话泄漏、隐藏态 burst 恢复 | 已落地并捕获真实 App 错序 | `MSG-REG-001`、`GROUP-REG-001`、`MSG-SEQUENCE-E2E-001`；v7 run `20260716031319-hkfp48kim6` 在三条隐藏态消息恢复后失败于可见 UI `wrong_message_id_or_order`，报告准确归属该 case |
| 会话行标题/preview/unread 与零 badge | 已落地 | scoped row key + visible UI oracle |
| Direct 2 条、Group 1 条未读隔离及逐会话清除 | 已注册到 `full` | `UNREAD-MULTI-E2E-001` |
| Direct/Group 相对排序和重启后可见列表 | 已注册到 `full` | `CONV-LIST-E2E-001` |
| nickname 跨身份查找、Direct、Contacts、可见群成员、群事件/发送人一致 | 已注册到 `full` | `DISPLAY-NAME-E2E-001`；联系人行和群成员行均在首个可见标题错误时立即失败 |
| 用户从头像显式刷新 Profile 后，既有各展示面统一收敛且不分裂身份/会话 | 已注册到 `full` 并通过远端 | `DISPLAY-NAME-E2E-004`；v6 run `20260716022319-hkfnqm6sau` |
| 已缓存 nickname 重开会话首个可见标题无 Handle/DID 闪烁 | 已注册到 `direct` / `full` | `DISPLAY-NAME-REG-001` |
| 本地搜索/recents 重开空 Direct | 已落地 | Direct focused flow |
| 联系人首次创建空 Direct | 已通过 `awiki.info` focused remote | `CONTACT-FIRST-CONV-E2E-001`；run `20260715201637-hkfdmqwuh0` |
| 入站首消息创建 canonical Direct | 已通过 `awiki.info` focused remote | `INBOUND-FIRST-CONV-E2E-001`；run `20260715211223-hkff635twu` |
| Direct/Group/Contact/列表/未读/顺序/昵称组合 | v6 24-case strict full 通过；v7 加入隐藏态三消息 burst 后捕获 App 可见错序 | v6 run `20260716022319-hkfnqm6sau`（24/24 passed）；v7 run `20260716031319-hkfp48kim6` 失败于 `MSG-SEQUENCE-E2E-001` 的 `wrong_message_id_or_order`；更早 run `20260716000225-hkfjut3j6i` 还捕获过 `CONV-LIST-E2E-001` 会话相对顺序未更新 |
| 群连续消息 sender label | 已按可见消息簇验证 | 同一远端发送人的连续气泡只在消息簇首条显示一次昵称；群信息弹窗另行验证真实成员行，不能用 Provider 代替 |
| 无 nickname、具备完整 Handle 的 fallback actor | 已注册独立远端 suite，并捕获真实 App 显示错误 | `DISPLAY-NAME-E2E-002`；最新 run `20260716034018-hkfpv0cxix` 在身份查找首个主标题失败于 `visible_ui / identity_preview_primary_name_mismatch`，证明 App 使用了服务端 generated user name，而不是完整 Handle |
| nickname/Handle 均不可用的 DID-only actor | 确定性 UI contract 已落地；真实远端 fixture 未落地 | `DISPLAY-NAME-E2E-003` 保持 planned，不以普通 Handle actor 伪造通过 |
| 真实第二 Flutter 进程冷启动 | 已落地并通过 `awiki.info` remote | runner 顺序启动两个不同 PID 的 Flutter integration-test 进程，复用同一隔离 state root；最新 v7 run `20260716033433-hkfpparzyc` |
| Runtime Agent 卡片入口 | 未落地到 required gate | 生产入口只对已安装 daemon 下的 Runtime Agent 可达，需要独立 daemon fixture；不伪装成普通联系人入口覆盖 |
| 首个 fatal/timeout/unstable 结构化诊断 | 已落地 | `failure_observation.json` 记录脱敏 code、状态和 UI/App/Core/remote 分层；runner schema-v2 汇总 |
| assertion 级结构化 evidence | 会话正确性主用例已落地 claim mapping | schema-v2 attestation/report 输出稳定 `CASE-ID:snake_case` assertion；catalog `assertionContract` 把 canonical/list/unread/sequence/display/restart 的 exact oracle 与 negative guard 映射到实际 assertion，validator 拒绝 contract 漂移；其余非会话 case 仍待逐步补齐 |

顺序 Oracle 已在一次真实 Full 运行中捕获过瞬时
`wrong_message_id_or_order`：两条正文相同但 canonical ID 不同的入站消息均已进入
App projection，其中一条暂时缺少 `serverSequence` 且时间戳精度不同，导致可见顺序
短暂反转。随后 focused 与最新 Full 可通过，说明这是间歇性产品/投影问题而不是测试
固定失败。该断言保持 fail-closed，不降级成“最终包含即可”；Core/SDK canonical
timeline 排序契约及不完整 metadata 的收敛仍需独立根因修复。

此前一次 23-case Full 又捕获到另一个 App 侧问题：Direct、Group、Direct
交替入站后，目标 Direct 的 preview 和 unread 已更新，但 App
projection 中 Direct/Group 的相对顺序仍与最新消息不一致。这次失败来自
App 会话列表 Oracle，不是 CLI 断言。为了让下一次运行的诊断不再只显示
`not_observed`，相对顺序 Oracle 已补上结构化
`app_projection / fatal / conversation_relative_order_mismatch` 首失败证据。
v6 Full 曾在相同 `awiki.info` 环境通过全部 24 个 case，因此该问题被判定为
间歇性 App projection 风险，而不是固定测试失败；失败 Oracle 继续保留。

v7 随后增加了更接近真实恢复链路的压力：App 进入隐藏态，对端连续发送三条
消息而测试不等待逐条 UI 收敛，恢复后要求精确 `+3` unread、最新 preview、
canonical ID/正文顺序及无跨会话泄漏。run `20260716031319-hkfp48kim6`
中 Core SQLite 已保存三条连续 `server_seq`，但 App 可见 timeline 的 run-owned
序列立即触发 `wrong_message_id_or_order`；其中一条消息的可见排序时间被截断到秒，
与相邻消息的毫秒时间发生反序风险。这是新严格用例发现的 App 展示/投影问题，
不是 CLI 产品断言，也不能通过等待“最终都包含”来降级成通过。

独立 `display-name-fallback` 远端运行还捕获到一个新的 App 侧问题：测试
fixture 没有 nickname，但有稳定完整 Handle；服务端 Profile 把内部 generated
user name 作为 `display_name` 返回后，App 的身份查找结果把它直接当成主标题，
没有回退到完整 Handle。失败报告现在携带 `caseId`，所以该首失败被准确归属到
`DISPLAY-NAME-E2E-002`，而不是误报为 `not_run`。CLI 在该 suite 中只提供身份和
远端流量，不发布 nickname，也不作为显示名通过依据。

未完成项继续保留为明确边界；不得因为 focused flow 通过就宣称整个方案完成，也不得提前注册 `conversation-correctness` required suite。

## 2. 现状审计

`awiki-me/tests/e2e/suite_manifest.json` 当前有 14 个 suite；与本文最相关的 required product slice 是 `direct`、`contacts`、`inbound`、`group`、`attachment`、`display-name-fallback`、`full` 和 release-only `restart`。真实场景主要集中在 `tests/e2e/flutter/desktop_cli_peer/` 下的 flow、robot 和 oracle。

`awiki-system-test` 已有 exact ID、重复、严格递增字段、稳定窗口和 App report validator 等可复用能力，但当前没有把普通 AWiki Me Direct/Group/Full UI 作为自身 suite manifest 中的 required UI gate。这一点应通过结构化 App evidence 衔接，不应在 System Test 中再造一套 App driver。

### 2.1 已有能力

| 能力 | 当前状态 | 评价 |
|---|---|---|
| Direct 消息 exact-one | 已检查正文、remote ID、sender/receiver、send state | 较强 |
| Direct 未读 | 已检查 baseline `+1`、打开清零和再次 `+1` | 较强，但偏 Provider |
| 空 Direct 会话 | 首条消息前存在，App-shell rebuild 后保留 | 已覆盖单入口 |
| 联系人入口 | 会复用已由查找入口创建的 canonical Direct | 部分覆盖 |
| 群会话 | 建群、加成员和 rebuild 后会话保留 | 部分覆盖 |
| 附件 | 已检查元数据、digest 和下载字节 | 消息层较强 |

### 2.2 主要盲区

| 风险 | 当前缺口 | 可能的假绿 |
|---|---|---|
| 重复会话 | `requireExactlyOneConversation` 主要按预期 `conversationId` 计数，没有按 `peerPersonaId` / `canonicalGroupDid` 遍历所有行 | canonical 行一条，同时另有一条语义重复行，测试仍通过 |
| 消息错序 | 逐条检查 exact-one，但不比较整个有序序列 | `m1,m3,m2,m4` 仍通过 |
| 额外消息 | 不比较 run-owned 消息完整集合和总数 | 期望消息都在，但多出一条异常消息 |
| 列表 preview | 多数只检查 `ConversationSummary.lastMessagePreview` | Provider 正确，Widget 绑定了旧值或错字段 |
| 未读 UI | 正数有部分可见断言，清零后主要检查 Provider | badge 仍显示，但内部数值已清零 |
| 列表排序 | 没有多会话的精确排序断言 | 新消息到达后行不上移，或 replay 导致乱序 |
| 昵称一致性 | 远程 E2E 基本没有跨展示面验证 | 列表显示 Handle，页头显示 nickname，群里显示 DID |
| 昵称闪烁 | `pumpAndSettle` / 轮询只看最终状态 | 首帧出现 Unknown/Handle，稍后恢复后测试通过 |
| 多入口 | 联系人用例会先通过查找入口创建会话 | “联系人首次创建”仍可产生双会话 |
| 真正重启 | 当前 `restart()` 是同进程 Widget/App-shell rebuild | Core/runtime 重开后的重放、冷启动和缓存问题无法发现 |

另有一个需要立即校正的质量问题：`GROUP-REG-001` 的 catalog 声称验证消息“ordered”和 cross-group leakage，但当前实现只做了逐条 exact-one，没有顺序比较和第二群的泄漏检查。Catalog 不能比可执行 Oracle 更强。

审计还发现三个需要用测试锁定、但不应在本方案中顺手改代码的高风险点：

1. pending 合并逻辑可能把短时间内两条合法的相同文本误判为同一条；当前 E2E 始终使用不同文本，无法发现。
2. timeline comparator 当前先比较 `createdAt`，只在相同时才比较 `serverSequence`；在时钟偏差、backfill 或 reconnect 场景下必须由排序契约和顺序用例证明正确性。
3. 群邀请候选组合中存在按 DID 去重的路径，可能与 Persona/canonical identity 模型产生显示名不一致或 DID 轮换重复。

## 3. 目标和非目标

### 3.1 目标

1. 对会话、消息、未读和用户名建立可复用的 exact Oracle。
2. 同一个用例同时证明 Core truth、App projection 和 visible UI 一致。
3. 对重复、错序、错标题、错 preview、未读偏差和短暂错误状态 fail closed。
4. 将用户常用入口收敛到同一 Persona/Group 会话不变量。
5. 保持可落地：重用现有 WidgetTester + 真实 `awiki.info` + CLI peer，不引入 OCR、坐标点击或 VoiceOver 作为产品 Oracle。

### 3.2 非目标

1. 不用 App E2E 穷举 Core 的所有 replay/alias 组合；这些应由 `awiki-cli-rs2` 的确定性 Core/SDK 测试承担。
2. 不把截图、golden 或 OCR 当作文本和身份正确性的主 Oracle。
3. 不在生产代码中增加 mock 或为通过测试而增加降级逻辑。
4. 不对入口顺序做全排列；采用每入口首次创建 + 一条重复进入链路的 pairwise 覆盖。

## 4. 总体测试架构

### 4.1 三层 Oracle

每个产品用例都产生同一份 `ExpectedScenario`，并对比三层证据：

| 层 | 证明什么 | 示例 |
|---|---|---|
| Canonical truth | Core/SDK 中的权威本地投影正确 | `conversationId`、`peerPersonaId`、`groupDid`、ordered message IDs、unread |
| App projection | App 规范化状态没有二次分叉 | `entitiesById`、`orderedIds`、selected ID、display resolver 结果 |
| Visible UI | 用户真正看到的状态正确 | 行标题/preview/unread/顺序、页头、bubble 顺序、sender label |

CLI/RPC/server 只作为对端刺激和远端动作完成诊断，不能代替上述任何一层，也不在 AWiki Me E2E 中扩展为 CLI 产品正确性测试。Provider 正确同样不能代替 visible UI。

#### App 主断言边界

AWiki Me E2E 的产品 verdict 必须由 App 侧证据决定。CLI 在本仓库中只有三个职责：准备独立对端身份、制造入站消息/关系/群成员等远端刺激、提供最小的传输回执与故障分层信息。具体约束是：

1. 会话数量、canonical ID、列表顺序、title、preview、unread、消息顺序/去重和各页面名称一致性，全部由 App projection 与 visible UI 断言；CLI 成功不能让这些 case 通过。
2. App 发送时，必须先证明 App 的发送终态、气泡、归属会话和列表 preview 正确；CLI 收到回执只闭合真实远端传输，不扩展检查 CLI UI 或 CLI 本地产品行为。
3. CLI 向 App 发送时，CLI 返回的 message ID 是 run-owned 刺激标识；case 必须以 App 的会话行、badge、timeline、sender label 和已读转移作为主断言。
4. CLI 诊断失败可以让前置或传输闭环 fail closed，但不得用 CLI 查询结果替代缺失的 App UI 断言。CLI 自身详细功能正确性由 CLI 所属工程测试。

### 4.2 预期场景模型

每个 run 只保存脱敏、run-owned 的结构化预期：

```text
ExpectedScenario
  runId / caseId
  appActor / peerActors
  conversations[]
    canonicalConversationId
    peerPersonaId | canonicalGroupDid
    expectedTitle
    expectedPreview
    expectedUnread
  messages[]
    canonicalMessageId
    conversationId
    senderPeerPersonaId
    serverSequence
    type / bodyFingerprint / terminalState
  expectedDisplayNames[peerPersonaId]
```

消息顺序不能由测试自行发明。实施前必须先在 Core/SDK 文档中冻结 canonical timeline 排序契约；远程 E2E 按 SDK 返回的权威顺序验证 UI，不单独使用可能冲突的客户端时间戳。

### 4.3 语义化 UI 观测

在不改变产品行为的前提下，为关键显示元素增加 scoped key/semantics：

- conversation row title / preview / unread，key 包含 canonical `conversationId`；
- chat header title；
- message bubble / sender label，key 包含 canonical message ID 或稳定 local ID；
- contact title，key 包含入站 DID，并限制在目标联系人行作用域；
- group member title，优先包含 `membershipId`，缺失时使用 Persona/DID 稳定 fallback，并限制在群信息弹窗作用域；
- mention candidate title，key 包含 `peerPersonaId` / `membershipId`。

key 用于定位身份，文本仍必须独立检查。不应用全局 `find.text()` 证明某个 scoped 元素正确，否则页头中的文本可能错误地代替会话行通过断言。

### 4.4 严格等待模型

当前部分 poll helper 会捕获所有异常并继续等待，容易让短暂重复、错名字或错未读“自愈”后变绿。统一改为三态观测：

- `pending`：明确允许的加载状态，可继续等待；
- `pass`：完整精确匹配；
- `fatal`：重复身份、错 canonical ID、已出现的错标题、未读回退、错序或跨会话泄漏，立即失败，不允许继续等待。

达到 `pass` 后还要执行 `assertStableFor`，在限定窗口内反复检查状态不变，用于发现迟到 replay、第二条重复消息或未读回弹。

## 5. 必备 Oracle

### 5.1 会话语义唯一

`requireExactlyOneConversationForPersona` 必须同时断言：

1. 预期 canonical ID 恰好一条；
2. 该 `peerPersonaId` 下没有任何其他 Direct 行；
3. selected conversation、timeline、conversation row 和 Product overlay 指向同一 ID；
4. 不存在 legacy DID row 或其他 alias row。

Group 使用同样规则，但语义键为 `canonicalGroupDid`。这才能捕获“一条正确行 + 一条错误行”。

### 5.2 会话列表

`requireExactConversationRowUi` 验证：

- row 数量和 canonical ID；
- 标题精确文本；
- preview 精确文本及其来源 message ID；
- unread 精确数字，为 0 时 badge 必须不存在；
- 在 `orderedIds` 和 visible list 中的位置；
- selected row 与当前页头属于同一 canonical ID。

preview 至少覆盖纯文本、群消息、Mention、附件和不应显示的 control payload。

### 5.3 消息集合和顺序

`requireExactTimeline` 不做逐条“包含”，而是比较整个 run-owned 序列：

- 期望 ID 集合与实际 ID 集合精确相等；
- canonical message ID 全部唯一；
- 每条 `(id, conversation, sender, type, body, terminalState)` 精确相等；
- 按 Core canonical timeline 契约比较完整顺序；
- UI bubble 顺序与 canonical timeline 相等；
- 该 run 消息没有出现在其他会话；
- reconnect、backfill、rebuild/restart 后仍稳定。

### 5.4 用户名一致性

`requireConsistentPeerDisplayName` 按现有架构中的唯一优先级计算预期：

```text
local note
  > nickname
  > full Handle
  > historical sender snapshot (only unresolved/missing)
  > compact DID
  > unknown
```

对同一 `peerPersonaId` 一次性比对：

- 会话列表标题；
- 聊天页头；
- 联系人预览和“查看全部”；
- 用户详情；
- 群成员；
- 群消息 sender label；
- 群系统事件中的用户名；
- Direct 中任何需要显示 peer 名称的位置。

`@` 候选中的可插入文本属于消息寻址 surface，不与普通主显示名混为一个
Oracle。尤其 Agent 当前允许使用稳定 Handle 作为 `@handle` token；本轮只验证
候选身份唯一、可点击且结构化 target 正确，不用 nickname 断言改写协议寻址语义。

当 nickname 存在时，相同 scope 内还要明确断言 Handle、DID 和 `Unknown` 没有被当作主显示名。当 nickname 不存在时，所有显示面统一 fallback 到 full Handle。

身份查找结果和群系统事件的产品契约已明确为“昵称 > 完整 Handle > DID”。DID 是最后 fallback，在 UI 中可使用 compact formatter 缩略显示；不得在 nickname 或 Handle 已知时优先显示 DID。这两类显示仍必须从同一 Persona Profile 投影解析，不能由 Widget 自行拼接。

### 5.5 首帧和过程稳定性

对已有本地 Profile cache 的会话，不允许先 `pumpAndSettle` 再断言。要在点击/选中后逐帧采样：

- 允许 skeleton/blank 等明确的加载态；
- 第一个出现的文本必须是缓存 nickname；
- 任何一帧出现 `Unknown`、DID 或 Handle 作为主名称都立即失败；
- 后台 Profile 返回同值不应产生可见抖动。

## 6. 用例矩阵

不建议立即拆出大量独立 suite。保留现有 focused suite，新增一个聚合别名 `conversation-correctness`，并优先落地下列垂直用例：

| 优先级 | 建议 Case ID | 场景 | 必须检出的错误 |
|---|---|---|---|
| P0 | `CONV-CANON-E2E-001` | 同一 Persona 通过 identity lookup、联系人首次进入、Agent 卡片、入站首消息、本地会话搜索和 recents 重开 | 双会话、入口产生不同 ID、空会话丢失 |
| P0 | `GROUP-CANON-E2E-001` | 建群、加成员、群列表/群详情重开、首条消息前后 | 加人后行消失、同 Group 双会话 |
| P0 | `CONV-LIST-E2E-001` | 至少两个 Direct/Group 交替收消息 | 标题、preview、行顺序、selected row 错误 |
| P0 | `UNREAD-MULTI-E2E-001` | A/B 分别收到 2/1 条，打开 A，再 reconnect | 行数不准、总数不准、清 A 误清 B、未读回弹 |
| P0 | `MSG-SEQUENCE-E2E-001` | App/CLI 交错 + CLI burst + reconnect/backfill | 重复、缺失、额外、错序、跨会话泄漏 |
| P0 | `DISPLAY-NAME-E2E-001` | nickname 与 Handle/DID 明显不同，比对所有展示面，包括身份查找结果和群系统事件 | 页面间 nickname/Handle/DID 不一致 |
| P0 | `DISPLAY-NAME-E2E-002` | 无 nickname 但有稳定完整 Handle 的独立 actor，比对身份查找、Direct、Contacts、群成员、群事件和 sender label | generated user name、bare Handle、DID、Unknown 或不同展示面混用，而不是统一完整 Handle |
| P0 | `DISPLAY-NAME-E2E-003` | nickname/Handle 都不可用的 DID-only actor | 未在仅有 DID 时统一使用 DID fallback；真实 fixture 未提供前保持 planned |
| P0 | `DISPLAY-NAME-REG-001` | 已缓存 nickname 后重开会话，逐帧观测 | `Unknown/Handle -> nickname` 闪烁 |
| P1 | `PROCESS-RESTART-E2E-001` | 同一隔离 state root 下分两个 Flutter 进程创建与恢复 | 真实重启后重复、丢行、未读或 nickname 丢失 |

### 6.1 Direct 多入口最小覆盖

为避免全排列爆炸，用下列组合：

1. 每个有效创建入口各有一个“本地无会话 -> 首次创建”用例；
2. 一个连续用例按 `联系人 -> identity lookup -> recents -> 本地会话搜索` 反复进入同一 Persona；
3. 一个逆序用例从 lookup 或入站首消息开始，再从联系人入口重开；
4. 每步都做 Persona 语义 exact-one，不只在最后做断言。

会话列表搜索只过滤本地最近会话，它是“重开”入口，不是远程身份创建入口。`PeerProfilePage` 存在发消息控件，但在将其列为 required case 前，应先确认当前产品是否有可达的生产调用入口；不为不可达页面制造假覆盖。

Runtime Agent 的“打开聊天”是可达生产入口，但只会出现在已安装 daemon 创建出的 Runtime Agent 详情页。它依赖独立 daemon/runtime fixture，不属于普通用户 Persona 的基础入口矩阵；在 fixture 能稳定提供前保持 optional/planned，不能用 application service 直调伪造 UI 覆盖。

### 6.2 消息顺序最小覆盖

1. App 发 `A1`；
2. CLI 连续发 `C1,C2,C3`；
3. App 发 `A2`；
4. App 进入合法 inactive/hidden，CLI 再发 `C4,C5`；
5. App resume，使 realtime 与 catch-up/backfill 有机会重叠；
6. 连续发送两条正文相同但 client ID 不同的消息，必须保留为两条；
7. 在能显式控制 idempotency key 的 Core/CLI 链路重放同一请求，必须收敛为一条；
8. 对 Core 和 UI 的 run-owned 完整序列做精确对比；
9. reconnect 后在稳定窗口内重复检查。

确定性 replay、同一 idempotency key 重放、同毫秒时间戳和 pagination boundary 主要放在 Core/SDK 测试；App 远程 E2E 只保留一条代表性端到端收敛链路。

## 7. 真实重启方案

不使用 VoiceOver、OCR 或坐标点击。由 E2E runner 编排两个独立 Flutter integration-test 进程：

1. `phase-a`：使用 run 唯一 `AWIKI_E2E_APP_STATE_ROOT`，创建会话、消息、未读和 Profile cache，写入脱敏 handoff manifest 后正常退出；
2. runner 确认第一个进程已完全结束；
3. `phase-b`：新进程使用同一 state root 和同一构建产物，只从持久化状态恢复；
4. 再次执行语义 exact-one、exact timeline、unread 和 first-visible-name 断言；
5. 报告记录 App ref、CLI/Core ref、native content hash、构建 target 和 config fingerprint。

该用例已作为独立 `restart` suite 放入 release gate，不拖慢每次 PR。Phase A
只执行 `bootstrap.dispose()`，不能调用会清除 active identity 的 `logout()`；handoff
记录第一进程 PID、state-root digest 和精确 App 预期，Phase B 必须证明 PID 不同、
state root 相同、session 无重新登录恢复，并从可见 UI 验证 Direct/Group exact-one、
消息顺序、未读和 cached nickname。最新远端通过 run 为
`20260716033433-hkfpparzyc`。

## 8. 分层责任

| 层 | 必须承担 | 不应代替 |
|---|---|---|
| AWiki Me unit/widget | display resolver、Provider 规范化、row/preview/unread 绑定、逐帧禁止态、Oracle 自身的反例测试 | 真实 backend/CLI 收敛 |
| AWiki Me remote E2E | 真实可见操作、三层投影一致、多入口、列表、消息顺序和昵称跨页面 | 不能只调 application service 代替用户动作 |
| `awiki-cli-rs2` Core/SDK | alias/replay/idempotency/order 契约、semantic exact-one、SDK DTO 完整性 | 可见 Flutter UI |
| `awiki-system-test` | 真实 `awiki.info` fixture、CLI/RPC/backend truth、资源台账、App 结构化报告验证 | VoiceOver/OCR/坐标 App driver |

System Test 现有 exact ID、唯一字段、严格数字递增和 stability-window helper 可复用。但后端或 CLI 通过不能替代 AWiki Me 可见 UI 通过。

## 9. 用例隔离和远程数据

1. 每个 case 使用独立 App state root 和 CLI workspace。
2. 消息内嵌 run-unique 标识，报告仅保存 fingerprint，不保存原文和完整 DID。
3. 需要全局列表基数/顺序的 case 使用远程测试账号池中的隔离 actor；不允许把残留数据当成空 baseline。
4. 无公开删除 API 的远程资源继续记录为 `residual`，不伪装 cleanup 成功。
5. 如无法获得完全干净 actor，可用 run-owned 子集验证消息集合，但会话语义 exact-one 仍必须遍历当前本地投影的所有行。

## 10. 证据与诊断

每个 checkpoint 生成脱敏的 `ObservedProjection`，失败时保留：

- scoped visible UI snapshot：行、标题、preview、unread、顺序、页头和 bubble/sender label；
- App/Core canonical snapshot：会话语义键、canonical ID、message ID/sequence、read watermark；
- CLI/RPC 结果摘要；
- 最后一个 `pending` 或第一个 `fatal` 观测；
- realtime/backfill/reconnect/restart 来源和相对时间线；
- screenshot，仅用于人工辅助定位；
- App/CLI/Core source ref、native content hash、platform/arch 和配置指纹。

报告不能只记录非空 phase 字符串。每个 catalog 声明的 Oracle 都应对应一个已执行 assertion ID 和结构化证据；validator 要拒绝缺失、重复、未执行或次序错误的 assertion。

## 11. 落地顺序

### 阶段 1：先使测试不再假绿

1. 校正 `GROUP-REG-001` catalog 与实现不一致；未实现前不得声称 ordered/cross-group 已验证。
2. 实现三态 poll 和 `assertStableFor`，不再吞掉 fatal invariant violation。
3. 实现 Persona/Group 语义 exact-one、exact timeline 和 scoped row Oracle。
4. 为 Oracle 增加反例/变异测试：人为插入重复行、交换消息顺序、改错一个展示面名字、未读 `+1`、错 preview，必须全部变红。

### 阶段 2：加强现有垂直用例

1. Direct/Group/Contact 从按 ID exact-one 升级为按 Persona/Group 语义 exact-one。
2. Direct/Group/Attachment 同时检查可见 row title、preview、unread 和清零后 badge 消失。
3. 将完整集合、ID 唯一、顺序和跨会话泄漏检查加入 Direct/Group flow。
4. 加入两会话 unread/list isolation 用例。

### 阶段 3：多入口和显示名一致性

1. 增加所需 scoped semantics，不改变产品逻辑。
2. 覆盖联系人首次创建、identity lookup、Agent 卡片、入站首消息、本地会话搜索/recents 重开和群列表/群详情重开。
3. 增加 nickname、完整 Handle fallback、DID-only fallback、身份查找结果、群系统事件、跨页面一致性和已缓存 nickname 首帧用例；不同 fallback actor 分开登记，不能用一个 fixture 同时证明两种前置条件。
4. Profile 变更后，通过用户显式头像刷新验证各展示面同步收敛；普通 tab/会话切换不应成为高频远程刷新。

### 阶段 4：远程报告和真进程重启

1. AWiki Me 输出结构化 `ObservedProjection` 和 assertion evidence。
2. `awiki-system-test` 管理隔离 fixture/backend truth，并验证 App 报告。
3. runner 实现两进程 restart phase，运行在同一隔离状态目录和同一构建产物上。
4. 在 suite manifest/catalog 中注册 `conversation-correctness`，只有在所有 P0 case 真正可执行时才标记 required。

## 12. Gate 策略

| Gate | 内容 |
|---|---|
| PR | Oracle 反例、Provider/widget contract、scoped UI binding、首帧禁止态；全部确定性、无远程依赖 |
| Focused remote | 改动会话/消息/profile 后运行相应 P0 slice |
| Nightly | `conversation-correctness` 完整 `awiki.info` App + CLI peer 用例 |
| Release | Nightly 全部内容 + 真实两进程 restart + App/CLI/Core source attestation |

## 13. 完成标准

下列条件全部满足后，才能认为本方案完成：

1. 人为注入“同 Persona 第二会话行”时，会话 Oracle 必须失败。
2. 人为复制、删除或交换任何两条 run-owned 消息时，timeline Oracle 必须失败。
3. 仅将会话行、页头、联系人或群 sender 中任一显示名改错，display-name Oracle 必须失败。
4. preview 指向旧消息、unread 差 1、清零后 badge 未消失或打开 A 误清 B 时，测试必须失败。
5. 任一入口返回不同 canonical conversation ID，或空会话在首条消息前消失，测试必须失败。
6. nickname 已缓存时任一观测帧出现 Unknown/Handle/DID 作为主名称，测试必须失败。
7. Catalog 中的每个 exact oracle/negative guard 都有对应的已执行 assertion evidence，不再允许只靠 phase 字符串证明。
8. 所有 P0 用例在远程 `awiki.info` 上通过，且失败报告能区分 UI 绑定、App projection、Core canonical 和远程服务问题。
