# Step 01：基线审计与远端可观测点确认

主 Plan：[../plan.md](../plan.md)
Step index：01
状态：review

## 1. 执行状态

| 字段 | 值 |
|---|---|
| Status | review |
| Branch | `feature/release-0526/agent-im-hutong` |
| Started | 2026-06-14 |
| Completed | - |
| Commit | - |
| Review evidence | 已确认当前 `awiki-me` scenario 在非 dry-run 下仍把核心 P0 标为 skipped；`app_bootstrap_scenario.dart` 使用 fake messaging/inventory；`awiki-cli-rs2/docs/agent-im` 要求的 App↔Daemon/Hermes 回传证据当时并未形成。 |
| Verification evidence | `git status` 已复核；本地 dry-run 可生成计划；远端 `ssh ali` 初探曾显示 Daemon/Hermes/message-service/user-service units active，但后续新 SSH 连接出现 banner timeout。 |
| Next action | 等远端 SSH 恢复后补齐 state/log/部署路径证据；本地实现已进入 Step 02/03 Review。 |

状态取值：`pending`、`in_progress`、`review`、`blocked`、`committed`、`done`。

## 2. 目标

- 结果：明确当前 E2E skeleton 与 `awiki-cli-rs2/docs/agent-im` 完整目标之间的缺口，确认可用于真实验收的本地/远端证据来源。
- 用户 / 系统可见行为：后续测试失败时可以定位是 App bootstrap、CLI peer send、Message Service fanout、Daemon bootstrap、Hermes runtime、message sync 回传还是 App reducer/历史读取问题。
- 非目标：本步骤不修复功能代码，不把远端健康检查当作功能通过。
- 完成标准：形成可执行证据清单；确认远端 `ssh ali` 服务、状态库、日志或 API 查询方式；记录当前 blockers 和风险。

## 3. 设计方法

- 设计边界：只读审计优先；避免修改远端和本地业务代码，直到真实缺口被定位。
- 核心决策：P0 pass 必须同时有 App 侧、CLI 侧、Daemon/Hermes 侧和回传侧证据。
- 契约 / API / 数据流：
  - App -> Daemon：`awiki.daemon.bootstrap.v1` payload，`controller_did == sender_did`。
  - Daemon -> Hermes：`awiki.runtime.user_message_task.v1`，`content_role=user_message_untrusted`。
  - Daemon -> App：`awiki.message.sync.v1` / `awiki.app.action.result.v1` 或等价 status payload。
- 兼容性：现有 dry-run 保留；非 dry-run P0 不再 skipped。
- 迁移策略：无。
- 风险控制：远端命令只输出脱敏状态、hash、ID 和短摘要。

## 4. 实现方法

1. 读取 `awiki-cli-rs2/docs/agent-im/` 设计、Step 03-09、registry hardening docs，抽取验收点。
2. 读取 `awiki-me/tests/e2e_test/` 当前 runner/scenario/config/remote adapter，确认 fake 与 skipped 路径。
3. 读取 `awiki-cli-rs2/crates/awiki-deamon/src/app_bridge/`、`inbox/user_delegated.rs`、`foreground.rs`、`state/mod.rs`，确认 bootstrap、message-agent binding、delegated inbox、outbox delivery 是否完整。
4. 通过 `ssh ali` 确认远端服务单元、repo 路径、daemon state sqlite、Hermes gateway 日志、message-service/user-service health。
5. 记录真实 E2E 必须采集的证据字段：runId、bootstrap id、idempotency key、app DID、daemon DID、runtime agent DID、peer message ID、processed message status、message sync outbox status、App history payload schema。

## 5. 路径

| 仓库 / 模块 / 文件 | 计划变更 | 备注 |
|---|---|---|
| `awiki-me/tests/e2e_test/scenarios/agent_im_delegated_message/` | 审计现状 | 当前 P0 skipped 逻辑在这里。 |
| `awiki-me/tests/e2e_test/harness/src/remote_adapter.dart` | 审计远端证据命令 | 后续可能增强为 state query。 |
| `awiki-cli-rs2/docs/agent-im/` | 审计功能要求 | 本任务权威功能设计。 |
| `awiki-cli-rs2/crates/awiki-deamon/src/` | 审计服务侧闭环 | 重点是 `message_sync_outbox` 是否有 flusher。 |
| `ssh ali` 远端 | 只读检查服务/日志/state | 不输出秘密。 |

## 6. 依赖

- 前置步骤：无。
- 外部文档或决策：主 Plan 第 2 节 Harness 上下文。
- 环境前提：本地仓库可读；`ssh ali` 可连接或可重试。

## 7. 验收标准

- [ ] 当前 fake/skipped 点已明确记录。
- [ ] 远端服务、repo、state/log 查询路径已确认。
- [ ] P0 证据清单覆盖 App、CLI、Message Service、Daemon、Hermes、回传到 App。
- [ ] Review 发现已经修复或明确记录。
- [ ] 本步骤在进入下一步之前已经创建聚焦 commit，或在主 Plan 中记录为何与 Step 02 合并提交。

## 8. 验证方式

| 检查项 | 命令 / 方法 | 预期证据 |
|---|---|---|
| Git status | `for repo in awiki-me awiki-cli-rs2 awiki-system-test message-service user-service; do git -C "$repo" status --short --branch; done` | 知道哪些变更属于本任务，避免覆盖他人工作。 |
| Code audit | `rg`/`sed` 读取相关路径 | 明确 skipped/fake 和 missing flusher 等缺口。 |
| Remote health | `ssh ali` 只读 `systemctl` / `journalctl` / `find` | Daemon/Hermes/message-service/user-service 可观测。 |
| Docs audit | 读取 `awiki-cli-rs2/docs/agent-im` | 验收点和当前测试缺口对应。 |

如果某个命令不能运行，必须记录原因、影响和替代证据。

## 9. Review 环节

- Review 时机：审计完成、进入 Step 02 前。
- Review 重点：不要把健康检查当通过；证据清单是否足够证明完整闭环；是否有秘密泄漏风险。
- Review 结论必须在 commit 前记录；必须修复必要问题，或明确记录剩余风险。

| Review 项 | 结果 | 备注 |
|---|---|---|
| 发现问题 | 待回填 | - |
| 已修复问题 | 待回填 | - |
| 剩余风险 | 待回填 | - |
| 新增或缺失测试 | 待回填 | - |
| 已更新或缺失文档 | 待回填 | - |

## 10. Commit 要求

- Commit 时机：本步骤审计、Review 和文档回填完成后。
- Commit 范围：本计划/审计文档；如无功能变更，可与 Step 02 的文档更新同一 commit，但需在台账记录。
- Commit 前状态：记录 `git status`。
- 纳入文件：本计划和 Step 01 文档。
- Commit 后证据：记录 commit hash 和 commit 后 `git status`。
- 遗留未提交变更：必须记录原因以及为什么安全。
- 建议消息：`docs: plan real agent im e2e completion`

## 11. Blocked 处理

| Blocker | 证据 | 已尝试方案 | 影响范围 | 下一步决策 |
|---|---|---|---|---|
| SSH 临时超时 | 记录 ssh stderr | 减少并发、稍后重试、本地继续审计 | 远端路径确认 | 不阻塞本地 Step 02 设计，但不能完成 Step 04。 |

## 12. Plan 变更记录

| 日期 | 变更 | 原因 | 主 Plan 变更记录链接 |
|---|---|---|---|
| 2026-06-14 | 创建 Step 01 | 建立真实 E2E 前必须先确认证据和缺口 | [../plan.md#15-plan-变更记录](../plan.md#15-plan-变更记录) |

## 13. 风险、回滚与后续文档

- 风险：远端查询命令可能意外输出消息正文或 token；必须限制字段并脱敏。
- 回滚 / 回退：本步骤只写文档，无运行时代码回滚。
- 后续文档：Step 04 需要把确认后的远端查询方式同步到 runbook。
