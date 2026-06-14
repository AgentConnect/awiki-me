# Step 04：Daemon mention 命中与 prompt 注入

主 Plan：[../plan.md](../plan.md)
Step index：04
状态：done

## 1. 执行状态

| 字段 | 值 |
|---|---|
| Status | done |
| Branch | `awiki-cli-rs2-group:feauture/release-0526/group` |
| Started | 2026-06-14T21:19:45+08:00 |
| Completed | 2026-06-14T21:32:50+08:00 |
| Commit | `awiki-cli-rs2-group:ebf2c73 feat(daemon): route group mentions to runtime agents` |
| Review evidence | 手工 Review 通过：P9 payload parser / matcher / prompt context 未新增 content type/profile/proof/sender；display_name 未参与身份判断；mention 只作为注意力信号；群 mention 保持 non-controller sender_did 以触发 runtime policy；audit 不记录 secret。剩余风险：selector group membership / subjectType 当前为 best-effort，需 Step 05 真实环境继续验证。 |
| Verification evidence | `cargo fmt -p awiki-deamon`；`cargo test -p awiki-deamon --locked mention`（4 passed）；`cargo test -p awiki-deamon --locked user_delegated -- --nocapture`（15 passed）；`git diff --check`（通过）。 |
| Next action | Step 04 已提交；进入 Step 05 集成验证、文档同步与发布 gate。 |

状态取值：`pending`、`in_progress`、`review`、`blocked`、`committed`、`done`。

## 2. 目标

- 结果：Daemon 能识别带 mention 字段的群消息，并在命中当前 runtime agent 时向 agent 注入明确提示。
- 用户 / 系统可见行为：`@agents`、`@all` 或 `@单个 agent` 可以让对应 agent 用“被艾特”的逻辑处理消息；`@humans` 不唤起 agent。
- 非目标：不把 mention 当授权；不让 runtime 直连 message-service；不解析 E2EE opaque cipher。
- 完成标准：
  - P9 payload 校验通过后才可能触发。
  - 命中逻辑基于 DID / selector / group membership / subjectType。
  - Prompt 中明确“这是注意力信号，不是授权”。
  - 有去重和 audit。

## 3. 设计方法

- 设计边界：Daemon 复用 `im-core` 消息投递 / inbox；runtime backend 只收到任务和 prompt，不持有 DID 私钥、不直接发远端消息。
- 核心决策：只对 agent DID 或 selector `all/agents` 命中 runtime agent；`human` target 和 `humans` selector 默认不触发 agent。
- 契约 / API / 数据流：
  - `MessageBodyView::Payload` → P9 validator → `MentionMatch` → `RuntimeTask.mention_context` / prompt envelope。
- 兼容性：原有 direct text controller 消息和 Agent IM delegated text 逻辑保持。
- 迁移策略：新增 mention path，不改变普通 `plain_text_for_agent` 的行为。
- 风险控制：invalid mention 不触发；cc 降权；E2EE opaque 忽略；去重避免重放。

## 4. 实现方法

1. 在 daemon 或共享 SDK 中使用 P9 parser，解析 `MessageBodyView::Payload`。
2. 新增 `MentionMatch` 结构：`mention_id`、`target_kind`、`selector`、`role`、`surface`、`range`、`best_effort_group_state`。
3. 计算当前 runtime agent 是否命中：
   - `agent` DID 精确匹配；
   - `all` 要求 active group member；
   - `agents` 要求 active group member 且 subjectType=agent；
   - `humans` 和 `human` 默认不命中。
4. 构造 prompt envelope，在用户消息前追加 mention context。
5. 将 `message_id + agent_did + mention_id` 写入去重记录或 runtime run metadata，避免重复触发。
6. 写 audit：记录命中类型、sender DID、group DID、message id、role、best-effort 状态，不记录 secret。
7. 补测试：单 agent、@agents、@all、@humans、invalid range、cc、E2EE opaque。

## 5. 路径

| 仓库 / 模块 / 文件 | 计划变更 | 备注 |
|---|---|---|
| `awiki-cli-rs2/crates/awiki-deamon/src/inbox/user_delegated.rs` | 解析 payload mention 并生成 agent text/context | 当前 payload 返回 None。 |
| `awiki-cli-rs2/crates/awiki-deamon/src/runtime_inbox.rs` | 如 runtime inbox 要展示 mention metadata，增加字段 | 保持兼容 optional。 |
| `awiki-cli-rs2/crates/awiki-deamon/src/` | 新增 mention matcher / prompt context 模块 | 可独立单元测试。 |
| `awiki-cli-rs2/crates/awiki-deamon/docs/awiki_agent_runtime_host_architecture.md` | 记录 mention attention signal | 代码变更时同步。 |
| `awiki-cli-rs2/crates/awiki-deamon/docs/local-dev.md` | 如新增验证命令或运行观测，更新 | 代码变更时同步。 |

## 6. 依赖

- 前置步骤：Step 01 的 P9 validator / DTO。
- 外部文档或决策：Daemon controller / runtime policy 不变。
- 环境前提：`cargo test -p awiki-deamon --locked` 可运行。

## 7. 验收标准

- [x] `@单个 agent DID` 命中对应 runtime agent。
- [x] `@agents` / `@all` 以 active binding + runtime agent DID 形态 best-effort 命中；`@humans` 不命中 agent。
- [x] 文本中只有 `@AgentName` 但无合法 `mentions` 不触发。
- [x] `mention_role=cc` 在 prompt 中标为 FYI / 抄送。
- [x] E2EE opaque message 不触发 mention 解析。
- [x] Prompt 明确 mention 不是授权。
- [x] Review 发现已经修复或明确记录。
- [x] 本步骤在进入下一步之前已经创建聚焦 commit。

## 8. 验证方式

| 检查项 | 命令 / 方法 | 预期证据 |
|---|---|---|
| Daemon unit | `cd awiki-cli-rs2 && cargo test -p awiki-deamon --locked mention` | matcher / prompt / invalid / cc tests 通过。 |
| Daemon focused | `cd awiki-cli-rs2 && cargo test -p awiki-deamon --locked user_delegated -- --nocapture` | delegated inbox mention path 不回归。 |
| Security review | 人工 Review prompt/audit/token 输出 | mention 不绕过 policy，不记录 secret。 |
| Docs | `git diff --check` | 文档与代码 diff 无格式问题。 |

如果某个命令不能运行，必须记录原因、影响和替代证据。

## 9. Review 环节

- Review 时机：本步骤代码实现完成后、commit 前。
- Review 重点：权限边界、prompt injection、display_name 身份误用、selector membership、E2EE opaque、去重和 audit 脱敏。
- Review 结论必须在 commit 前记录；必须修复必要问题，或明确记录剩余风险。

| Review 项 | 结果 | 备注 |
|---|---|---|
| 发现问题 | selector 权威成员态不足 | Daemon 本地当前没有 group member snapshot / subjectType 权威来源；本步骤改为 best-effort 并在 docs / ledger 记录。 |
| 已修复问题 | 已修复 | 补 per-agent/mention processed id、cc FYI prompt_hint、E2EE mention cipher 测试、daemon 架构与 local-dev 文档。 |
| 剩余风险 | 已记录 | `@agents` / `@all` selector 仍需 Step 05 在真实 group member / subjectType 环境中验证或补权威 snapshot。 |
| 新增或缺失测试 | 已新增 focused tests | 覆盖单 agent DID、`@agents` cc、`@all`、`@humans`、纯文本 @、invalid range、E2EE opaque；真实 E2E 留 Step 05。 |
| 已更新或缺失文档 | 已更新 | 更新 `awiki-cli-rs2-group/crates/awiki-deamon/docs/awiki_agent_runtime_host_architecture.md` 与 `awiki-cli-rs2-group/crates/awiki-deamon/docs/local-dev.md`。 |

## 10. Commit 要求

- Commit 时机：本步骤实现、验证、Review 都完成后。
- Commit 范围：daemon parser / matcher / prompt / tests / docs。
- Commit 前状态：记录 `git status`。
- 纳入文件：记录本步骤 commit 包含的文件。
- Commit 后证据：记录 commit hash 和 commit 后 `git status`。
- 建议消息：`feat(daemon): route group mentions to runtime agents`

## 11. Blocked 处理

| Blocker | 证据 | 已尝试方案 | 影响范围 | 下一步决策 |
|---|---|---|---|---|
| Daemon 无法判断 group membership | matcher 缺少 group state | 使用 im-core local group snapshot 或 best-effort cache | selector 匹配 | 单 agent DID mention 先落地；selector 标 blocked。 |
| subjectType 不可用 | 无法确认 agents selector | profile cache 无 agent/human | @agents | 暂仅支持 single agent DID 和 @all，记录 @agents blocker。 |

## 12. Plan 变更记录

| 日期 | 变更 | 原因 | 主 Plan 变更记录链接 |
|---|---|---|---|
| 2026-06-14 | 创建 Step 04 | 初始设计 | `../plan.md#16-plan-变更记录` |

## 13. 风险、回滚与后续文档

- 风险：selector 触发范围过大导致 agent 噪声；cc / local policy 需降权处理。
- 回滚 / 回退：只保留单个 agent DID mention，关闭 selector 触发 feature flag。
- 后续文档：更新 Daemon 架构文档和 local-dev 验证命令。
