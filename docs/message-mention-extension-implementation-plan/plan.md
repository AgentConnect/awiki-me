# Plan：ANP P9 消息 Mention 扩展落地方案

状态：done（Step 01-05 已完成；远端 App+CLI group P9 E2E 已通过，Daemon live prompt 作为后续专项 gate）
DOC：`awiki-me-group/docs/message-mention-extension-implementation-plan/`
Harness：`awiki-harness/`
创建时间：2026-06-14
恢复指针：执行开始前从 Step 01 开始；本轮只产出设计文档，不修改业务代码。

## 1. 目标

- 任务目标：根据 `anp/AgentNetworkProtocol/chinese/message/09-消息Mention扩展.md`（ANP-P9 draft v1.1），设计 AWiki 群消息 mention 的产品、App、SDK、Daemon 与验证落地方案。
- 预期行为：
  1. 用户在 `awiki-me` 群聊输入 `@` 时，出现类似微信 / 飞书的候选列表：所有人、所有 agents、所有人类用户、单个群成员。
  2. 发送后，消息中被 mention 的 surface 文本以区别普通文本的颜色展示。
  3. `awiki-deamon` 收到带 `mentions` 的群消息后执行终端侧校验；当 mention 命中当前 runtime agent 时，给 agent prompt 注入“有人艾特你”的上下文提示。
- 非目标：
  - 本轮不改代码。
  - 不定义私聊 mention 语义。
  - 不新增 JSON-RPC 方法、外层 `meta.profile`、专用 content type、payload `protocol` 标记、mention sender、mention proof 或服务端 mention 授权。
  - 不在服务端展开 `@all`、`@agents`、`@humans` 为成员 DID 列表。
  - 不把 mention 视为执行高风险动作的授权，只作为注意力信号。
- 完成标准：
  - 方案覆盖 App 层输入体验、消息展示、发送 / 接收 DTO、SDK 边界、Daemon mention 命中和 prompt 注入。
  - 明确当前实现缺口、风险、测试策略和后续实施步骤。
  - 所有路径使用 AWiki workspace 相对路径。

## 2. Harness 上下文

| 来源 | 作用 |
|---|---|
| `awiki-harness/AGENTS.md` | 非平凡 AWiki 任务的读取顺序、权威来源和完成标准。 |
| `awiki-harness/context/00-context-map.md` | 将任务路由到 Protocol、Message Flow、Client Architecture、Agent Runtime Host。 |
| `awiki-harness/context/02-repo-map.md` | 确认 `awiki-me` 是 App，`awiki-cli-rs2` 是 SDK / Daemon 权威，`anp` 是协议权威。 |
| `awiki-harness/context/03-cross-repo-architecture.md` | 确认 App → Dart SDK → im-core、Daemon → im-core、message-service 不解释上层业务语义的依赖方向。 |
| `awiki-harness/context/20-rules-index.md` | 定位文档、架构、AI 编码、验证规则。 |
| `awiki-harness/context/30-tools-env.md` | 后续实施需要的 Flutter、Rust、system-test 命令入口。 |
| `awiki-harness/context/40-verification.md` | 本设计属于文档 L0；后续实现属于跨 repo / 协议行为 L2-L3。 |
| `awiki-harness/context/50-task-workflow.md` | 方案、验证、执行台账和恢复协议的结构依据。 |
| `awiki-harness/context/nodes/protocol.node.md` | P9 协议变更必须以 `anp/AgentNetworkProtocol/` 为权威。 |
| `awiki-harness/context/nodes/message-flow.node.md` | 消息服务只处理外层消息与投递，不使用展示字段做路由 / 授权。 |
| `awiki-harness/context/nodes/client-architecture.node.md` | App 不直接拼 wire；共享 IM 能力应通过 `awiki-cli-rs2/packages/awiki_im_core` / `crates/im-core`。 |
| `awiki-harness/context/nodes/agent-runtime-host.node.md` | Daemon 是通用 ANP Agent Runtime Host，runtime 不直连 message-service。 |
| `awiki-harness/rules/documentation-principles.md` | 文档放置、权威层级和链接有效性要求。 |
| `awiki-harness/rules/architecture-principles.md` | 协议、客户端、服务端、Daemon 的边界和 E2EE 安全边界。 |
| `awiki-harness/rules/ai-coding-rules.md` | 先分析影响面，再实施；代码与文档同步。 |
| `awiki-harness/rules/verification-policy.md` | 验证分级、证据报告和安全 gate。 |

## 3. 任务上下文与当前实现观察

| 来源 | 观察 |
|---|---|
| `anp/AgentNetworkProtocol/chinese/message/09-消息Mention扩展.md` | P9 要求群 JSON payload 使用顶层 `text` + `mentions`，target 支持 `human`、`agent`、`group_selector`，selector 支持 `all`、`agents`、`humans`，range 单位为 `unicode_code_point`。 |
| `awiki-me/AGENTS.md` | `lib/src/domain/` 放领域实体，`lib/src/data/` 放 SDK / persistence adapter，`lib/src/presentation/` 放 UI/provider；App 必须 Dart-only。 |
| `awiki-me/lib/src/domain/entities/chat_message.dart` | 当前 `ChatMessage` 只有 `content` / `payloadJson`，没有 typed mention 字段。 |
| `awiki-me/lib/src/presentation/chat/chat_provider.dart` | 当前发送文本走 `MessagingService.sendText`；群聊 mention payload 需要新增发送分支或服务方法。 |
| `awiki-me/lib/src/presentation/chat/chat_page.dart` | 当前 composer 是 `CupertinoTextField`；消息文本由 `_MessageTextContent` 用 `Text` 或 `MarkdownBody` 渲染，尚无 mention span。 |
| `awiki-me/lib/src/data/im_core/awiki_im_core_mappers.dart` | 当前 mapper 对 `MessageBodyView.payloadJson` 不投影 `payload.text`，导致 mention JSON payload 不会作为普通聊天文本显示。 |
| `awiki-me/lib/src/domain/entities/group_member_summary.dart` | 当前群成员实体只有 DID / handle / role，缺少 `displayName`、`avatarUri`、`subjectType`、`membershipStatus` 等候选列表需要的字段。 |
| `awiki-cli-rs2/packages/awiki_im_core/lib/src/models/message.dart` | Dart SDK 有 `SendPayloadRequest` 和 `MessageBodyView.payloadJson`，可承载 JSON payload。 |
| `awiki-cli-rs2/packages/awiki_im_core/lib/src/awiki_im_core_native.dart` | 当前 `_validatePayloadJson` 要求 JSON payload 必须有非空 `schema`；这会阻塞 P9 最小 payload，后续实现需调整或新增 typed mention API。 |
| `awiki-cli-rs2/crates/im-core/src/messages/dto.rs` | Rust SDK 已有 `MessageBody::Payload` / `MessageBodyView::Payload`，适合承载 P9 payload。 |
| `awiki-cli-rs2/crates/awiki-deamon/src/inbox/user_delegated.rs` | 当前 `plain_text_for_agent` 只处理 `MessageBodyView::Text`，对 JSON payload 返回 `None`；后续需解析 P9 payload 后再决定是否提示 / 触发 agent。 |
| `awiki-cli-rs2/crates/awiki-deamon/docs/awiki_agent_runtime_host_architecture.md` | Daemon prompt / runtime task 必须保留 daemon 边界；mention 不能绕过 controller / runtime policy。 |

## 4. 影响分析

| 领域 / 仓库 / 模块 | 影响 | 权威文档或代码 |
|---|---|---|
| ANP Protocol | P9 为协议权威；产品实现必须遵守 payload shape、range、target、无服务端展开 / 授权。 | `anp/AgentNetworkProtocol/chinese/message/09-消息Mention扩展.md` |
| `awiki-me` App UI | Composer `@` 触发、候选列表、draft mention 状态、发送分支、消息高亮展示。 | `awiki-me/lib/src/presentation/chat/chat_page.dart`、`awiki-me/lib/src/presentation/chat/chat_provider.dart` |
| `awiki-me` App domain | `ChatMessage`、`GroupMemberSummary`、mention draft / DTO / validation projection。 | `awiki-me/lib/src/domain/entities/` |
| Dart SDK / Rust SDK | 最好沉淀 typed mention DTO、validator、send API；至少要允许 P9 schema-less JSON payload。 | `awiki-cli-rs2/packages/awiki_im_core/lib/src/models/message.dart`、`awiki-cli-rs2/crates/im-core/src/messages/dto.rs` |
| Message Service | 不新增服务端 mention 语义；只需保证 application/json payload 不被改写，后续补测试防回归。 | `message-service/docs/api/`、`message-service/crates/` |
| Daemon / Agent Runtime Host | 解析收到的 P9 payload，校验 mention，匹配 runtime agent DID / selector，构造 mention context prompt。 | `awiki-cli-rs2/crates/awiki-deamon/src/`、`awiki-cli-rs2/crates/awiki-deamon/docs/` |
| System Test | 覆盖 App 发群 mention、App 高亮、Daemon 被 `@agents` / 单个 agent 唤起。 | `awiki-system-test/`、`awiki-me/tests/e2e/` |

## 5. 总体设计方法

### 5.1 协议映射原则

1. App 发送带 mention 的群消息时，payload 使用 P9 最小结构：

   ```json
   {
     "text": "@所有 Agents 请总结这段讨论。",
     "mentions": [
       {
         "id": "men_1",
         "range": {"start": 0, "end": 10, "unit": "unicode_code_point"},
         "target": {"kind": "group_selector", "selector": "agents"},
         "mention_role": "addressee"
       }
     ]
   }
   ```

2. `@` 后面的可见文本只是 surface syntax，不作为身份。单人身份使用 `target.did`；群范围使用 `target.selector`。
3. `mentions` 中不放 `sender`、`sender_did`、`from`、`actor_did`、`auth`、`proof`、`signature`。
4. 非 E2EE group base：payload 位于 `params.body.payload`，`meta.content_type = application/json`。
5. Group E2EE：payload 位于加密前 inner plaintext 的 `payload`，inner `application_content_type = application/json`。
6. 不将 mention target 复制到外层 metadata；服务端不展开 selector，不做 mention 专属授权。

### 5.2 App 层体验设计

#### 5.2.1 触发与候选列表

- 触发时机：仅在群聊 conversation 中启用；私聊输入 `@` 暂不触发 P9 mention。
- 触发条件：光标前出现 `@`，且位于文本开头、空白、换行或常见中文 / 英文分隔符之后；IME 正在 composing 时不弹出，避免中文输入法误触。
- 候选排序：
  1. `@所有人` → `target.kind = group_selector`，`selector = all`。
  2. `@所有 Agents` → `target.kind = group_selector`，`selector = agents`。
  3. `@所有人类用户` → `target.kind = group_selector`，`selector = humans`。
  4. 单个 active 群成员，按 displayName / handle / DID 搜索过滤。
- 展示字段：候选项展示 `displayName` 优先，其次 handle，最后 compact DID；右侧显示 “Agent / Human / Selector” badge。高风险或详情入口仍可查看 DID / Handle。
- 选择行为：用候选 surface 替换 `@query` 片段，并追加一个空格；例如插入 `@所有 Agents ` 或 `@InvoiceBot `。surface 可以本地化，但 target 必须保留机器可读 selector / DID。

#### 5.2.2 候选数据来源

- 群成员来自 `GroupApplicationService.listMembers(groupDid)`。
- 成员 display/profile 应走 SDK 本地 profile cache / projection，不在候选列表热路径逐项远程请求。
- 成员类型来自 profile / roster 的 `subjectType`（`agent` 或 `human`），不能从 P4 群治理角色 `owner/admin/member` 推断。
- 当前 `GroupMemberSummary` 缺少 `displayName/avatarUri/subjectType/status`，后续应补齐：
  - `displayName`：本地 profile cache projection；fallback handle / compact DID。
  - `subjectType`：`agent` / `human` / `unknown`。
  - `membershipStatus`：只对 active member 作为可选 mention 目标。
- `subjectType = unknown` 的单人成员不应静默当作 human 或 agent；MVP 可显示为“资料同步中/类型未知”并禁用单人 mention，或在用户选择前触发显式 profile resolve。

#### 5.2.3 Draft 状态与 range 维护

- App draft 需要保存 `text` 和本地 `MentionDraft` 列表。
- `MentionDraft` 可包含：`localId`、`surface`、Dart `TextRange`（code unit）、target、role、display snapshot、createdAt。
- 每次编辑后：
  - 如果编辑发生在 mention range 前面，平移 range。
  - 如果编辑覆盖 mention range，或 range 子串不再等于 draft surface，删除该 mention，避免 spoofing。
  - 发送前按最终 `text` 重新计算 P9 `unicode_code_point` offsets。
- Dart `String` index 是 UTF-16 code unit；P9 要求 Unicode code point。实现时应提供 code unit ↔ code point 转换工具，并用中文、emoji、组合字符、换行测试覆盖。

### 5.3 发送路径设计

- 普通无 mention 文本继续走 `MessagingService.sendText`。
- 群聊且 draft 中存在有效 mentions 时，走新增应用层方法，例如：

  ```text
  MessagingService.sendMentionText(thread: AppThreadRef.group(groupDid), text, mentions)
  ```

- 该方法在 `awiki-me` 内构造 P9 payload，并通过 SDK 的 JSON payload 能力发送：
  - `target = MessageTarget.group(groupDid)`；
  - `payloadJson = jsonEncode({"text": text, "mentions": mentions})`；
  - `security` 根据群的 message security profile 选择：普通群用 default/plain group base；E2EE 群用 `groupE2ee`。
- 关键 SDK 缺口：`awiki-cli-rs2/packages/awiki_im_core/lib/src/awiki_im_core_native.dart` 目前要求所有 JSON payload 必须有非空 `schema`。P9 明确不要求也不能依赖 payload `protocol` 标记；因此后续实现必须采用以下二选一：
  1. **推荐**：在 `crates/im-core` / Dart SDK 增加 typed `sendGroupMentionText` API，由 SDK 内部验证 P9 并发送 schema-less payload。
  2. **可接受 MVP**：放宽 `SendPayloadRequest` 的 Dart wrapper 校验，只要求 JSON object 和大小限制；`awiki-me` 自己做 P9 validator。原有 `awiki.agent.*` control payload 仍可继续携带 `schema`。
- 不推荐在 P9 payload 强行加入 `schema` 仅为绕过 SDK wrapper，因为这会让实现对非 P9 字段产生隐性依赖，并降低互操作最小性的清晰度。

### 5.4 接收、消息模型与展示设计

- 接收时如果 `MessageBodyView` 是 payload JSON，App mapper 需要检测是否为 P9 mention-bearing payload：
  - payload 是 object；
  - `text` 是 string；
  - `mentions` 是 array；
  - 每个 mention 通过 P9 终端侧校验。
- 对合法 P9 payload：
  - `ChatMessage.content = payload.text`；
  - 新增 `ChatMessage.mentions = List<MessageMention>`；
  - `payloadJson` 继续保留原始 JSON，便于诊断和后续兼容；
  - `hasRenderableContent` 应把合法 mention payload 视为可展示文本。
- 对非法 mention 对象：
  - 不触发通知 / agent 逻辑；
  - 如果 payload 有 `text`，可继续按普通文本显示；
  - 不高亮无效 mention range。
- `_MessageTextContent` 增加 mention-aware 渲染分支：
  - 有 valid `mentions` 时使用 `RichText` / `SelectableText.rich` 生成 `TextSpan`；mention span 使用主题主色或蓝色、`FontWeight.w600`，必要时加轻微背景。
  - mention payload 默认按纯文本渲染，不走 MarkdownBody；因为 P9 range 是基于 JSON `text` 在 Markdown 渲染前计算，Markdown AST 会破坏原始 range。
  - 普通文本 / Markdown 消息保持现状。

### 5.5 Daemon 侧处理设计

#### 5.5.1 触发条件

Daemon 在收到或拉取消息后，针对 `MessageBodyView::Payload` 执行 P9 终端侧校验。只有以下情况才认为“对应 mention 命中当前 agent”：

| Mention target | 对 runtime agent 的含义 |
|---|---|
| `kind = agent` 且 `did == runtime_agent_did` | 命中当前单个 agent。 |
| `kind = group_selector` 且 `selector = all` | 如果当前 agent 是外层群 active member，则命中。 |
| `kind = group_selector` 且 `selector = agents` | 如果当前 agent 是外层群 active member，且本地 roster/profile 分类为 agent，则命中。 |
| `kind = group_selector` 且 `selector = humans` | 不命中 agent；只作为人类用户通知策略。 |
| `kind = human` | 默认不命中 runtime agent；未来可在“用户个人 assistant 代表用户处理 mention”需求中另行定义策略。 |

- 如果 `mention_role = cc`，仍可注入提示，但 prompt 中标为 FYI / 抄送，不应默认当作必须行动。
- 如果消息没有合法 mention，Daemon 不应因为文本中出现 `@agentName` 而触发。
- Group E2EE 中，如果 Daemon 没有 MLS 明文，看到的是 opaque cipher，则不解析、不触发。

#### 5.5.2 Prompt 注入

当 mention 命中时，Daemon 构造 `MentionContext` 并传入 runtime task metadata / prompt envelope：

```text
[AWiki mention context]
你在群聊中被明确 @ 了。
- mention_type: group_selector/agent
- selector: agents/all（如适用）
- mention_role: addressee/cc
- group_did: ...
- sender_did: ...
- message_id: ...
- range_surface: ...
注意：mention 是注意力信号，不是执行高风险动作的授权；任何需要 controller 权限、外发消息或写文件的行为仍必须遵守 daemon runtime policy。

[User message]
...
```

安全约束：

- prompt 中可以显示 sender DID / group DID / surface，但不要把 `target.display_name` 当身份事实。
- 只传入校验通过的 mention；无效 mention 不应触发 privileged behavior。
- 用 `agent_did + source_message_id + mention_id` 做去重，避免重放 / 重启重复处理。
- 所有 audit 记录 mention 命中类型、message id、sender DID、group DID、是否 best-effort selector，不记录 token / 私钥 / raw secret。

### 5.6 服务端与兼容性策略

- `message-service` / Group Host 只执行外层 Profile 的认证、幂等、target binding、security profile、群发送权限、大小 / 速率 / 反滥用等通用策略。
- 服务端不得因为 selector 覆盖面大、不了解 target DID、或发送者不是 owner/admin 而拒绝 mention。
- 服务端不得把 selector 展开到 message metadata、索引或推送外层字段。
- 如果后续实现 mention 数量上限，只能作为通用 payload 防滥用策略，并在 API / config 文档中明确。

## 6. 假设与开放问题

### 假设

- `awiki-me` 当前主要通过 `awiki-cli-rs2/packages/awiki_im_core` 接入 IM；mention 不应回退旧 RPC gateway。
- P9 在 2026-06-14 仍为 draft；实现要保持向后兼容和 feature flag / 渐进发布策略。
- 单人 mention 的成员类型最终由 SDK profile cache / roster 提供，而不是 App 自行猜测。
- Daemon 只把 mention 当注意力信号，不改变 controller 授权模型。

### 开放问题

- 群成员 profile 中 `subjectType` 在当前 SDK / service 投影中是否稳定可用？若不可用，需要先补 SDK profile hydration 或 group member projection。
- `awiki-me` 是否要默认插入中文 surface（如 `@所有人`）还是 ASCII surface（如 `@all`）？本方案建议候选 label 中文、surface 可本地化，但 target selector 必须标准化。
- `mention_role = cc` 是否应该自动唤起 runtime agent，还是只做低优先级 inbox 标记？MVP 建议唤起但 prompt 标注 FYI，具体自动执行由 runtime policy 决定。
- Group E2EE 何时让 Daemon/runtime agent 成为 MLS 成员并可解密？在未加入或无本地 MLS 状态时，Daemon 必须忽略 opaque mention。

## 7. 任务拆分

| Step | 标题 | 依赖 | 产出 | 小 Plan 文档 | Commit gate | 状态 |
|---|---|---|---|---|---|---|
| 01 | 协议 DTO 与 SDK payload 能力 | 无 | P9 typed DTO、validator、schema-less payload 或 typed send API、Dart/Rust 测试 | [steps/01-sdk-protocol-mention-dto.md](steps/01-sdk-protocol-mention-dto.md) | 必须 | done |
| 02 | App composer 候选与 draft range | Step 01 API 决策 | `@` 触发列表、候选数据、draft mention 状态、range 更新 | [steps/02-app-composer-mention-ux.md](steps/02-app-composer-mention-ux.md) | 必须 | done |
| 03 | App 发送、接收和高亮展示 | Step 01、02 | 发送 P9 payload、mapper 投影、valid mention highlight、非法 mention fallback | [steps/03-app-send-render-mention.md](steps/03-app-send-render-mention.md) | 必须 | done |
| 04 | Daemon mention 命中与 prompt 注入 | Step 01 | Daemon 解析 P9 payload、匹配 agent / selector、prompt context、去重和 audit | [steps/04-daemon-mention-routing.md](steps/04-daemon-mention-routing.md) | 必须 | done |
| 05 | 集成验证、文档同步与发布 gate | Step 01-04 | App / SDK / Daemon / E2E 测试证据、docs 更新、残余风险 | [steps/05-integration-verification-docs.md](steps/05-integration-verification-docs.md) | 必须 | done |

## 8. 执行台账

状态取值：`pending`、`in_progress`、`review`、`blocked`、`committed`、`done`。

| Step | 状态 | 分支 | 开始时间 | 完成时间 | Commit | Review 证据 | 验证证据 | 下一步 |
|---|---|---|---|---|---|---|---|---|
| 01 | done | `awiki-cli-rs2-group:feauture/release-0526/group`; `awiki-me-group:feauture/release-0526/group` | 2026-06-14T19:55:38+08:00 | 2026-06-14T20:17:46+08:00 | `awiki-cli-rs2-group:3bf3557 feat(im-core): support ANP P9 mention payloads` | 手工 Review 通过：确认 P9 未新增 content type/profile/proof/sender；selector 保持 all/agents/humans 不展开；display_name 仅展示快照；Dart payload 校验不再强制 schema；Group E2EE mention payload 只进入 inner plaintext。修复项：移除 Dart analyze 新增 const 提示，并顺手修复已触发的 null-aware lint。 | 通过：`cd awiki-cli-rs2-group && cargo test -p im-core --locked mention`（5 passed）；`cd awiki-cli-rs2-group && cargo test -p im-core --locked --features group-e2ee,blocking mention_group_e2ee_application_body_places_payload_in_inner_plaintext`（1 passed）；`cd awiki-cli-rs2-group && PATH=/Users/cs/development/flutter/bin:$PATH scripts/flutter/codegen-check.sh`（Done）；`cd awiki-cli-rs2-group/packages/awiki_im_core && dart analyze lib test/message_payload_api_test.dart`（No issues）；`cd awiki-cli-rs2-group/packages/awiki_im_core && flutter test test/message_payload_api_test.dart`（9 passed）；`git diff --check`（通过）。部分失败：`cd awiki-cli-rs2-group && cargo test --workspace --locked` 运行到 `awiki-cli --test identity_live_contract` 时 9 个 live contract 因本地 `http://127.0.0.1:* /user-service/did-auth/rpc` transport_unavailable 失败，属于本地 live 依赖未启动，不是 P9 改动失败。 | 启动 Step 02 |
| 02 | done | `awiki-me-group:feauture/release-0526/group` | 2026-06-14T20:30:43+08:00 | 2026-06-14T20:43:02+08:00 | `awiki-me-group:075a0c0 feat(app): add group mention composer UX` | 手工 Review 通过：确认 composer 仅在群聊启用 mention；候选固定 selector 置顶且 selector 保持 all/agents/humans；单人 target 使用 DID 和 subjectType，不使用 displayName 作为身份；unknown subjectType 候选可见但不可选择；候选加载只调用 `GroupApplicationService.listMembers`，不逐项远程拉 profile；IME composing 时不弹；普通发送回归通过。修复项：trigger detector 最初把 `@` 误判为 query break，已修复并补测试。 | 通过：`cd awiki-me-group && dart analyze`（No issues）；`cd awiki-me-group && flutter test tests/unit --name mention`（8 passed）；`cd awiki-me-group && flutter test tests/unit --name "chat mention"`（2 passed）；`cd awiki-me-group && flutter test tests/unit/chat_page_test.dart --name "macOS 聊天输入条保持发送能力"`（1 passed）；`cd awiki-me-group && git diff --check`（通过）。未做真机/手动移动端输入；当前 Step 02 以 widget test 覆盖群聊/私聊、点击选择和 draft range。 | 启动 Step 03 |
| 03 | done | `awiki-me-group:feauture/release-0526/group` | 2026-06-14T20:44:11+08:00 | 2026-06-14T21:18:37+08:00 | `awiki-me-group:ab5fd16 feat(app): send and render group mentions` | 手工 Review 通过：确认 App 发送的 P9 payload 仅包含 `text` 与 `mentions`，不新增 sender/proof/profile/专用 content type；群聊有合法 draft mention 时走 `sendMentionText`/SDK payload，普通文本仍走旧 `sendText`；mapper 将合法 P9 payload 投影为 `ChatMessage.content + mentions`，invalid range/target 只显示文本不高亮；`_MessageTextContent` 仅在 valid mentions 存在时使用纯文本 RichText，高亮范围不走 Markdown，普通 Markdown/附件 caption 路径保持原行为；retry、fake service、E2E probe stub 均补齐 mention payload 接口，避免重发丢 payload。修复项：补齐 `MessagingService.sendMentionText` 所有测试/工具实现、补 `notificationFacadeProvider` 测试 override、修正 highlight widget test 的 payload 可渲染条件。 | 通过：`cd awiki-me-group && flutter test tests/unit --name "mention payload"`（2 passed）；`cd awiki-me-group && flutter test tests/unit --name "mention highlight"`（1 passed）；`cd awiki-me-group && flutter test tests/unit --name "send mention"`（1 passed）；`cd awiki-me-group && flutter test tests/unit --name "chat mention"`（3 passed）；`cd awiki-me-group && flutter test tests/unit/chat_page_test.dart --name "macOS 聊天输入条保持发送能力"`（1 passed）；`cd awiki-me-group && dart analyze`（No issues）；`cd awiki-me-group && git diff --check`（通过）。未做真实后端/手动移动端发送，原因：Step 03 只覆盖 App 发送分支、mapper 投影和 UI 高亮，端到端真实后端验证留到 Step 05。 | 启动 Step 04 |
| 04 | done | `awiki-cli-rs2-group:feauture/release-0526/group` | 2026-06-14T21:19:45+08:00 | 2026-06-14T21:32:50+08:00 | `awiki-cli-rs2-group:ebf2c73 feat(daemon): route group mentions to runtime agents` | 手工 Review 通过：确认 daemon delegated inbox 改为拉取 direct + group，但 direct text 原路径保持；群消息只在合法 P9 `text + mentions` payload 命中 runtime agent DID、`@agents` 或 `@all` 时创建 RuntimeTask；`@humans`、`human` target、纯文本 `@AgentName`、invalid range 和 E2EE opaque 都不触发；`display_name` 未参与身份判断；runtime task / message sync / audit 只写入脱敏 mention context，prompt 的 `attention_policy` 明确 mention 不是授权；群 mention task 的 `sender_did` 保持原群消息发送者，继续触发 Hermes `untrusted_group_member` policy。修复项：补充 per-agent/mention processed id、cc FYI prompt_hint、E2EE mention cipher 测试和 daemon docs。剩余风险：当前 selector `@agents` / `@all` 在 daemon 本地只能按 active binding + runtime agent DID 形态做 best-effort，尚未接入权威 group member snapshot / subjectType，最终真实群成员验证留到 Step 05 / 后续集成。 | 通过：`cd awiki-cli-rs2-group && cargo fmt -p awiki-deamon`；`cd awiki-cli-rs2-group && cargo test -p awiki-deamon --locked mention`（4 passed）；`cd awiki-cli-rs2-group && cargo test -p awiki-deamon --locked user_delegated -- --nocapture`（15 passed）；`cd awiki-cli-rs2-group && git diff --check`（通过）。 | 启动 Step 05 |
| 05 | done | `awiki-me-group:feauture/release-0526/group`; `awiki-cli-rs2-group:feauture/release-0526/group` | 2026-06-14T21:34:03+08:00 | 2026-06-14T22:40:23+08:00 | `awiki-cli-rs2-group:1da1710 docs: document group mention integration gates`; `awiki-me-group:d373d48 test: add group mention e2e coverage` | 手工 Review 通过：确认 Step05 只修改 `awiki-me-group` / `awiki-cli-rs2-group`；App E2E 新增 `GROUP-P9-001`，发送 `@agents` schema-less P9 payload 并断言 payload 不含 `schema`；SDK / Daemon docs 与 Step01-04 行为一致；P9 未新增 content type/profile/proof/sender，服务端仍只透明转发，不展开 selector；`display_name` 不参与身份，Daemon focused tests 仍把 mention 作为 attention signal 而非授权。修复项：真实 E2E 首次暴露本地 worktree 仍指向旧 SDK 的 `invalid_payload: schema` 问题，已用本地未提交 `pubspec_overrides.yaml` 指向 `awiki-cli-rs2-group` 并在文档说明；默认受限 handle / 已污染 handle 导致注册失败，已换 fresh handles `p9g14app01` / `p9g14cli01` 完成验证。剩余风险：本轮没有在 awiki.info 上拉起真实 runtime agent 验证 live prompt，只以 daemon focused tests 覆盖 prompt / @humans / invalid / E2EE opaque 边界。 | 通过：`cd awiki-me-group && dart analyze`（No issues）；`cd awiki-me-group && flutter test tests/unit --name mention`（14 passed）；`cd awiki-me-group && flutter test integration_test/desktop_cli_peer_group_test.dart -d macos --dart-define=AWIKI_E2E=false`（macOS build 通过，All tests skipped）；`cd awiki-cli-rs2-group && cargo test -p im-core --locked mention`（5 passed）；`cd awiki-cli-rs2-group && cargo test -p awiki-deamon --locked mention`（4 passed）；`cd awiki-cli-rs2-group/packages/awiki_im_core && flutter test test/message_payload_api_test.dart`（9 passed）；`cd awiki-cli-rs2-group && scripts/flutter/codegen-check.sh`（Done）；`cd awiki-cli-rs2-group && cargo build -p awiki-cli --bin awiki-cli --release --locked`（Done）；`cd awiki-cli-rs2-group && scripts/flutter/build-apple.sh --macos`（Done）；真实远端 E2E：历史验证 runId `mention-p9-20260614g` 已通过；当前 runner 已改为只从 `tests/e2e/configs/e2e.local.yaml` 读取配置，等价入口为 `dart run tests/e2e/runner.dart --case group --run-id mention-p9-20260614g`；`git diff --check` 两仓库通过。部分失败：`cd awiki-cli-rs2-group && cargo test --workspace --locked` 在 `awiki-cli --test identity_live_contract` 因本地 `127.0.0.1:* /user-service/did-auth/rpc` transport_unavailable 失败 11 个 live tests，非 P9 回归。 | 完成最终 Review，准备结束目标 |

## 9. Codex Goal 执行协议

- 将本 Plan 作为执行进度的唯一事实来源。
- 启动或恢复前，读取本 Plan、当前小 Plan、执行台账和当前 `git status`。
- 同一时间只执行一个步骤，除非本 Plan 明确标记多个步骤彼此独立且可以并行。
- 恢复时，从第一个状态不是 `done` 的步骤继续。
- 每个步骤依次执行：标记 `in_progress`、实现、验证、Review、修复 Review 发现、提交、记录证据、标记 `done`。
- 上一个依赖步骤的完成工作未提交前，不要开始下一个依赖步骤。
- 改变范围、顺序、验收标准、公开契约、数据模型或验证策略前，先更新本 Plan。

### 9.1 Codex Goal 提示词

```text
请以 `awiki-me-group/docs/message-mention-extension-implementation-plan/plan.md` 为唯一规划入口，按文档实现 ANP P9 群消息 mention 落地。

开始前先读取：
- `awiki-me-group/docs/message-mention-extension-implementation-plan/plan.md`
- 当前第一个未 done 的 Step 文档
- 主 Plan 的执行台账、Codex Goal 执行协议、验证策略、Blocked 处理和 Plan 变更记录
- 当前 `git status --short --branch`

请从第一个状态不是 `done` 的步骤开始，一次只执行一个步骤。每步都要按对应小 Plan 实现、验证、Review、修复或记录 Review 发现，然后在受影响仓库内创建一个聚焦 commit，并回填主 Plan 执行台账和 Step 执行状态。需要改变范围、顺序、验收标准、公开契约、数据模型或验证策略时，先更新 Plan 变更记录。

所有步骤完成后，执行最终全局 Review 和整体验证，记录实际命令、通过/失败/跳过数量、失败或跳过原因、剩余风险和最终工作区状态。

核心注意点：P9 不新增 content type/profile/proof/sender；服务端不展开 selector、不做 mention 专属授权；App 不能用 display_name 做身份；Daemon 只能把 mention 当注意力信号，不能绕过 controller/runtime policy；schema-less P9 payload 与当前 Dart SDK `schema` 校验冲突必须先解决。
```

## 10. 小 Plan 摘要

### Step 01：协议 DTO 与 SDK payload 能力

- 小 Plan：[steps/01-sdk-protocol-mention-dto.md](steps/01-sdk-protocol-mention-dto.md)
- 目标：让 SDK 层能表达、校验、发送和接收 P9 mention payload，解决 Dart `SendPayloadRequest` 强制 `schema` 的兼容问题。
- 设计方法：协议 DTO 与 validator 下沉到 `im-core` / Dart SDK；App 和 Daemon 不重复手写不一致规则。
- 实现方法：新增 typed DTO / validator，放宽或替代 payload validation，补 Rust / Dart 单元测试和 codegen。
- 路径：`awiki-cli-rs2/crates/im-core/`、`awiki-cli-rs2/crates/im-core-dart/`、`awiki-cli-rs2/packages/awiki_im_core/`。
- 验证方式：`cargo test`、`scripts/flutter/codegen-check.sh`、Dart package tests。
- Review 环节：重点审查 P9 MUST/MUST NOT、payload schema 兼容、E2EE 放置边界。

### Step 02：App composer 候选与 draft range

- 小 Plan：[steps/02-app-composer-mention-ux.md](steps/02-app-composer-mention-ux.md)
- 目标：在群聊 composer 中提供 `@` 候选列表和 draft mention 状态。
- 设计方法：UI 只做候选和 draft，不做协议 proof；成员类型来自 profile / roster。
- 实现方法：新增 mention draft controller、candidate provider、popup overlay、range 更新逻辑。
- 路径：`awiki-me/lib/src/presentation/chat/`、`awiki-me/lib/src/domain/entities/`、`awiki-me/lib/src/application/`。
- 验证方式：Flutter widget/provider tests 覆盖输入、筛选、选择、编辑失效。
- Review 环节：重点审查 IME、Unicode range、未知 subjectType、N+1 profile 请求。

### Step 03：App 发送、接收和高亮展示

- 小 Plan：[steps/03-app-send-render-mention.md](steps/03-app-send-render-mention.md)
- 目标：带 mention 群消息按 P9 payload 发送，接收后正常显示并高亮 surface。
- 设计方法：合法 P9 payload 投影为 `ChatMessage.content + mentions`；无效 mention 只显示文本不触发。
- 实现方法：新增 `sendMentionText`、mapper payload parser、`_MessageTextContent` mention-aware render。
- 路径：`awiki-me/lib/src/application/messaging_service.dart`、`awiki-me/lib/src/data/im_core/`、`awiki-me/lib/src/presentation/chat/chat_page.dart`。
- 验证方式：unit / widget tests；必要时 E2E dry-run。
- Review 环节：重点审查 Markdown 与 range 冲突、payloadJson 保留、预览和可访问性。

### Step 04：Daemon mention 命中与 prompt 注入

- 小 Plan：[steps/04-daemon-mention-routing.md](steps/04-daemon-mention-routing.md)
- 目标：Daemon 对 P9 mention payload 进行终端侧校验，命中当前 agent 时注入明确 prompt。
- 设计方法：命中逻辑只基于 DID / selector / group membership / subjectType，不基于 display_name 或可见 `@` 文本。
- 实现方法：新增 mention parser / matcher、RuntimeTask mention context、prompt envelope、去重和 audit。
- 路径：`awiki-cli-rs2/crates/awiki-deamon/src/`。
- 验证方式：daemon 单元测试、focused cargo tests、必要时 system-test daemon E2E。
- Review 环节：重点审查权限边界、cc 语义、E2EE opaque 忽略、重放去重。

### Step 05：集成验证、文档同步与发布 gate

- 小 Plan：[steps/05-integration-verification-docs.md](steps/05-integration-verification-docs.md)
- 目标：证明 App / SDK / Daemon / message-service 端到端兼容，并同步长期文档。
- 设计方法：用单元 + widget + Rust + focused E2E 组合验证，按 L2/L3 gate 报告证据。
- 实现方法：补 system tests、更新 API / SDK / App docs、执行 final global Review。
- 路径：`awiki-system-test/`、`awiki-me/docs/`、`awiki-cli-rs2/docs/`、必要时 `message-service/docs/`。
- 验证方式：`flutter test`、`cargo test`、focused local system-test。
- Review 环节：重点审查跨 repo 契约、文档漂移、隐私 / 安全和未提交变更。

## 11. Review 策略

- 每步骤 Review：实现完成后、commit 前，检查 P9 规范、数据模型、测试、文档、兼容性和安全边界。
- 全局 Review：所有步骤完成后，检查 App / SDK / Daemon / system-test 的端到端一致性。
- 契约 / 安全 / 隐私 Review：重点确认 mention target 不进入外层 metadata、不作为授权、不复制 secret、不使用 display_name 做身份。
- 文档 Review：更新 `awiki-me/docs/`、`awiki-cli-rs2/docs/`，如果 message-service 行为或 config gate 变化也更新对应 docs。

## 12. 验证策略

| 层级 | 命令 / 检查 | 预期证据 |
|---|---|---|
| Docs L0 | `git diff --check`，检查本 Plan 与 step 链接存在 | 文档格式无尾随空格错误，链接路径存在。 |
| App unit/widget | `cd awiki-me && flutter test tests/unit` | mention draft、候选、发送 mapper、高亮 widget 测试通过。 |
| App analyze | `cd awiki-me && dart analyze` | Dart 静态分析通过。 |
| SDK Rust | `cd awiki-cli-rs2 && cargo test -p im-core --locked mention` 或相关 focused tests | P9 validator、send payload、projection 测试通过。 |
| Dart SDK / codegen | `cd awiki-cli-rs2 && scripts/flutter/codegen-check.sh` | Rust-Dart DTO 生成物一致。 |
| Daemon focused | `cd awiki-cli-rs2 && cargo test -p awiki-deamon --locked mention` | mention matcher、prompt context、E2EE opaque ignore、dedup 测试通过。 |
| System / E2E | `cd awiki-system-test && uv run python manage_local_test_env.py run-tests --suite message-v2 ...` 或新增 focused suite | 群消息 `@agents` / 单 agent 可触发 Daemon，`@humans` 不触发 agent。 |

## 13. 文档更新

- 本次生成：`awiki-me-group/docs/message-mention-extension-implementation-plan/plan.md` 与 `steps/*.md`。
- 后续实现时应同步更新：
  - `awiki-me/docs/testing.md`：新增 mention UI / E2E gate。
  - `awiki-cli-rs2/docs/api/im-core-interface/04-message-interface.md`：新增 P9 mention payload / DTO / send API。
  - `awiki-cli-rs2/docs/flutter-sdk/awiki-im-core-flutter-sdk.md`：记录 Dart SDK mention DTO 和 schema-less payload 兼容。
  - `awiki-cli-rs2/crates/awiki-deamon/docs/awiki_agent_runtime_host_architecture.md` 或专门 docs：记录 mention attention signal 与 prompt policy。
  - 如 message-service 增加通用大小 / 数量限制，更新 `message-service/docs/api/` 和配置文档。

## 14. Commit 计划

- 每个完成、验证、Review 通过的步骤在对应仓库创建一个聚焦 commit。
- Commit 前记录 `git status` 和纳入文件。
- Commit 后记录 commit hash 和工作区状态。
- 不把 App、SDK、Daemon、system-test 的所有修改积累为一个大 commit。

## 15. Blocked 处理

| Blocker | Step | 证据 | 已尝试方案 | 影响范围 | 下一步决策 |
|---|---|---|---|---|---|
| Dart SDK 继续强制 payload `schema`，无法发送 P9 最小 payload | 01 / 03 | `_validatePayloadJson` 抛 `invalid_payload` | 放宽校验或新增 typed send API | App 发送链路 | 优先在 Step 01 解决。 |
| 群成员无法获得 `subjectType` | 02 / 03 / 04 | group member DTO 只有 did/handle/role | 使用 profile cache hydration；未知类型禁用单人 mention 或显式 resolve | 候选列表和 selector 命中 | 先补 SDK projection，不从 role 推断。 |
| Group E2EE 明文不可达 Daemon | 04 / 05 | Daemon 只看到 opaque cipher | 按 P9 忽略，记录 E2EE follow-up | E2EE mention agent 触发 | 不阻塞非 E2EE MVP。 |
| message-service 拒绝 schema-less application/json payload | 01 / 05 | 服务端 validation error | 修正服务端通用 payload acceptance；补 API 文档 | 发送 / E2E | 需要跨 repo 修复并 system-test。 |

## 16. Plan 变更记录

| 日期 | 变更 | 原因 | 影响步骤 | 是否需要 Review |
|---|---|---|---|---|
| 2026-06-14 | 创建 ANP P9 mention 落地方案 | 用户要求先设计，不改代码，放在 `awiki-me/docs` | 全部 | 是 |

## 17. 风险与回滚

| 风险 | 缓解措施 | 回滚 / 回退方案 |
|---|---|---|
| mention surface 被伪造 | 只以 `mentions[*].target` 和 valid range 触发；文本 `@xxx` 不触发。 | 禁用 mention 触发逻辑，仅保留文本展示。 |
| display_name 被误用为身份 | 所有身份判断使用 DID / selector；展示名只做快照。 | 回滚候选显示扩展，保留 DID / handle。 |
| selector 导致过度唤起 agent | Daemon 只匹配 active agent member；`@humans` 不唤起；`cc` 降权。 | 先只支持单 agent DID mention，延后 selector。 |
| Markdown 和 mention range 冲突 | Mention payload 走纯文本 RichText，不走 MarkdownBody。 | 回滚高亮，显示纯文本。 |
| E2EE mention 泄露 metadata | mention 不复制到外层 metadata；E2EE 中只在 inner plaintext。 | 禁用 E2EE mention 触发直到 MLS 明文链路验证。 |

## 18. 最终全局 Review 与整体验证

- 触发条件：所有步骤完成、Review、验证并提交后执行。
- Review 范围：`anp` P9 兼容、`awiki-cli-rs2` SDK / Daemon、`awiki-me` UI / mapper、`message-service` 透明转发、`awiki-system-test` 证据、文档同步。
- 重点关注：跨步骤一致性、回归风险、兼容性、安全 / 隐私、文档漂移、未提交变更、每个步骤 Review 发现是否已解决或记录。
- 整体验证命令 / 检查：见第 12 节；实际执行时回填命令、通过 / 失败 / 跳过原因。
- Review 发现：
  1. `awiki-me-group` 默认依赖路径仍是普通 sibling `../awiki-cli-rs2`，在本地 `-group` worktree 验证时会误用旧 SDK 并触发 `invalid_payload: payloadJson must contain a non-empty string schema`；这是本地 worktree wiring 问题，不是 P9 设计变更。
  2. 远端测试 handle 会被受限前缀或失败注册污染；真实 E2E 需要 fresh handles 或稳定账号池。
  3. 本轮真实 E2E 覆盖 App → SDK → awiki.info message-service → CLI history 的 `@agents` P9 payload preservation；未覆盖 awiki.info 上真实 runtime agent live prompt。
- 已修复问题：新增 `GROUP-P9-001` group E2E slice；文档补充本地 worktree `pubspec_overrides.yaml` 验证说明；使用 fresh handles `p9g14app01` / `p9g14cli01` 完成远端 group P9 E2E；同步 SDK / Flutter SDK / App testing docs。
- 剩余风险：Daemon selector membership / `subjectType` 仍是 best-effort；Group E2EE opaque 场景只由 focused tests 保证忽略；真实 runtime agent prompt 需要后续 daemon live E2E / awiki-system-test 专项 gate。
- 最终证据：App analyze 和 mention tests 通过；SDK / Daemon focused tests、Dart SDK payload tests、codegen、CLI release build、macOS SDK native build 通过；远端 `mention-p9-20260614g` App+CLI group E2E success；`cargo test --workspace --locked` 的 live identity contract 失败属于未启动本地 user-service live 依赖。
- 最终 `git status`：回填前 `awiki-cli-rs2-group` clean after `1da1710`；`awiki-me-group` 仅剩本 Plan / Step05 ledger 文档待提交。
- 本阶段修改文件：`awiki-cli-rs2-group/docs/api/im-core-interface/04-message-interface.md`、`awiki-cli-rs2-group/docs/flutter-sdk/awiki-im-core-flutter-sdk.md`、`awiki-me-group/docs/testing.md`、`awiki-me-group/tests/e2e/runner.dart`、`awiki-me-group/tests/e2e/flutter/desktop_cli_peer/*`、本 Plan / Step05 ledger。
