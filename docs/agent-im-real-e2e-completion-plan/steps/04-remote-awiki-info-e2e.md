# Step 04：远端 awiki.info 部署联调与真实 E2E 执行

主 Plan：[../plan.md](../plan.md)
Step index：04
状态：done

## 1. 执行状态

| 字段 | 值 |
|---|---|
| Status | done |
| Branch | `feature/release-0526/agent-im-hutong` |
| Started | 2026-06-14 |
| Completed | 2026-06-14 |
| Commit | 纯远端部署和本地 report；功能代码见 `awiki-cli-rs2` `a5cd420`、`awiki-me` `236acbb` |
| Review evidence | 远端 SSH 已恢复并完成部署；真实 run `20260614T024413341Z` 已取得 App↔Daemon/Hermes “完整处理摘要回传”证据。runner 的 remote evidence gate 输出六个 `E2E_STAGE ... pass`：`daemon_bootstrap_received`、`delegated_key_imported`、`hermes_agent_ready`、`cli_message_received`、`hermes_runtime_finished`、`summary_return_sent`。 |
| Verification evidence | `ssh ali` 可访问，远端 `awiki-deamon.service` active；真实 E2E runner result PASS，runId `20260614T024413341Z`，messageId `msg_agent_im_20260614T024413341Z`；`agent-im-scenario-result.json` 中 `AIM-E2E-001/002/006` pass；`remote-evidence-result.json` passed，missingStages 为空。 |
| Next action | 进入最终 Review、文档同步、commit/push；P1/P2 skipped 场景另行计划。 |

状态取值：`pending`、`in_progress`、`review`、`blocked`、`committed`、`done`。

## 2. 目标

- 结果：将必要修复部署到 `ssh ali` 上的 Daemon/Hermes/Message Service/User Service，执行真实 `awiki-me` macOS E2E 并取得 P0 pass 证据。
- 用户 / 系统可见行为：App 与远端 Agent 的真实委托处理能力可被自动化测试证明。
- 非目标：不做生产发布流程外的长期运维改造；不在报告输出秘密。
- 完成标准：`agent-im-scenario-result.json` 中 `AIM-E2E-001`、`AIM-E2E-002` 为 pass；`remote-evidence-result.json` 与 App probe report 可关联同一 runId/message ID；服务端运行版本明确。

## 3. 设计方法

- 设计边界：远端操作只部署本目标相关仓库；服务端代码可直接修改/编译/部署，但要同步本地仓库或记录远端-only 差异。
- 核心决策：E2E pass 需要 App 本地 report + remote state/log 双证据；单独 CLI send success 不足以 pass。
- 契约 / API / 数据流：按 App bootstrap、CLI ordinary send、Daemon/Hermes process、App return 逐段验证。
- 兼容性：远端改动应与本地 branch commit 对齐；不得依赖未记录手工 hotfix。
- 迁移策略：如 daemon state schema 需要自动迁移，先备份/确认迁移可重复。
- 风险控制：服务重启前记录状态；失败保留日志；敏感输出脱敏。

## 4. 实现方法

1. `ssh ali` 检查远端 repo 分支、commit、service unit、构建脚本。
2. 将 Step 03 修复部署到远端：git pull 或 patch、build、restart 对应 service。
3. 运行远端 health：user-service、message-service、daemon、Hermes gateway。
4. 本地运行真实 E2E：
   - `cd awiki-me && dart run tests/e2e_test/harness/desktop_e2e_runner.dart --platform=macos --scenario=agent-im-delegated-message --config tests/e2e_test/configs/agent_im_delegated.local.yaml --skip-flutter-smoke`
5. 按 report runId/message ID 查询远端：
   - daemon bootstrap/audit/message_agent binding；
   - delegated identity；
   - processed_message/message_event/message_sync_outbox；
   - Hermes runtime run/audit；
   - Message Service fanout；
   - App history 中的回传 payload。
6. 若失败，回到 Step 02/03 修复并重跑；不得把失败改成 skipped。

## 5. 路径

| 仓库 / 模块 / 文件 | 计划变更 | 备注 |
|---|---|---|
| 远端 `awiki-space/awiki-cli-rs2` | 部署 daemon 修复 | 路径以远端实际为准，文档中保持 workspace-relative 描述。 |
| 远端 `message-service` / `user-service` | 仅在有改动时部署 | 需要 health 和版本记录。 |
| `awiki-me/.e2e/<platform>/reports/<runId>/` | 本地 E2E report | 不提交。 |
| `awiki-me/docs/agent-im-real-e2e-completion-plan/` | 回填证据 | 脱敏。 |

## 6. 依赖

- 前置步骤：Step 02、Step 03。
- 外部文档或决策：`awiki-me/codex.md` 允许 `awiki.info` 通过 `ssh ali` 联调。
- 环境前提：远端 SSH 可用；本地配置和测试账号 env 可用。

## 7. 验收标准

- [x] 远端部署版本/commit 已记录。
- [x] 服务 health 通过。
- [x] 真实 E2E report 中 `AIM-E2E-001/002/006` pass。
- [x] 远端证据按 runId/message ID 覆盖 bootstrap、identity、message agent、Hermes processing、message sync delivery。
- [x] App 侧证据证明收到回传且不显示为普通聊天。
- [x] Review 发现已经修复或明确记录。
- [x] 本步骤在进入下一步之前已经创建聚焦 commit，或记录纯远端部署无需 commit 的原因。

## 8. 验证方式

| 检查项 | 命令 / 方法 | 预期证据 |
|---|---|---|
| Remote health | `ssh ali` service health and journal tail | 相关服务 active，近期无 fatal。 |
| Real E2E | `cd awiki-me && dart run tests/e2e_test/harness/desktop_e2e_runner.dart --platform=macos --scenario=agent-im-delegated-message --config tests/e2e_test/configs/agent_im_delegated.local.yaml --skip-flutter-smoke` | Runner PASS；P0 cases pass。 |
| Remote evidence | `remote-evidence-result.json` + targeted ssh queries | 与 runId/message ID 对齐，脱敏。 |
| Redaction | E2E redaction scan | 私钥/JWT/token/OTP 不出现在 report/log。 |

## 9. Review 环节

- Review 时机：真实 E2E 通过后、提交/标记 done 前。
- Review 重点：远端是否运行了本地修复版本；证据是否覆盖完整链路；是否有 skipped 被误当 pass；是否有秘密泄漏。
- Review 结论必须在 commit 前记录；必须修复必要问题，或明确记录剩余风险。

| Review 项 | 结果 | 备注 |
|---|---|---|
| 发现问题 | 已修复 | 上一轮 run `20260614T022608576Z` 缺 `hermes_runtime_finished`/`summary_return_sent`，根因是新 App instance 触发 Hermes cold init timeout。 |
| 已修复问题 | 已修复 | 稳定 App instance、run-scoped bootstrap attempt、Hermes timeout 调整并重启远端 daemon。 |
| 剩余风险 | 已记录 | 本轮只声明 P0 核心闭环通过；P1/P2 follow-up 继续 skipped。 |
| 新增或缺失测试 | 已覆盖 P0 | 真实 E2E + remote evidence gate 覆盖核心链路；daemon restart/E2EE/revoke/negative payload 后续补。 |
| 已更新或缺失文档 | 已更新 | 本 Step、主 Plan、测试文档和 Agent IM 设计文档同步 runId 证据。 |

## 10. Commit 要求

- Commit 时机：远端 E2E 证据回填和 Review 完成后。
- Commit 范围：部署/runbook/证据文档变更；代码变更应已在 Step 02/03 commit。
- Commit 前状态：记录 `git status`。
- 纳入文件：记录本步骤 commit 包含的文件。
- Commit 后证据：记录 commit hash 和 commit 后 `git status`。
- 遗留未提交变更：必须记录原因以及为什么安全。
- 建议消息：`test: validate agent im e2e on awiki info`

## 11. Blocked 处理

| Blocker | 证据 | 已尝试方案 | 影响范围 | 下一步决策 |
|---|---|---|---|---|
| 远端服务无法部署或重启 | SSH/service/build log | 修复构建、回滚、重启单服务 | 核心目标 | 连续三轮相同 blocker 才标 goal blocked。 |
| 真实 E2E 失败但本地无法复现 | report + remote evidence | 按链路二分，补远端日志/state query | 当前步骤 | 回到 Step 02/03 修复。 |
| 新 SSH 连接 banner timeout | `ssh -o BatchMode=yes -o ConnectTimeout=8 ali ...` 多次返回 `Connection timed out during banner exchange`，最近一次 2026-06-13T17:29:49Z；TCP 可 connect 但无 SSH banner；本机仍有 3 个既有 `ssh ali` TCP established 会话 | 已重试短命令、检查 SSH config、TCP connect 和 ping；本地已完成并推送 gate/daemon 修复；未擅自结束用户会话 | 远端部署和真实 E2E | 需要恢复 SSH 或经用户确认释放既有会话后重试。 |
| 本地 E2E secret env 未导出 | 若 `.e2e/macos.env` 不存在或缺少账号 env，probe 会 fail | 不在日志回显秘密；使用本机私有 env 文件加载 | 真实非 dry-run | 运行前从本机私有 env 加载，不提交。 |

## 12. Plan 变更记录

| 日期 | 变更 | 原因 | 主 Plan 变更记录链接 |
|---|---|---|---|
| 2026-06-14 | 创建 Step 04 | 真实远端验证必须单独执行和记录 | [../plan.md#15-plan-变更记录](../plan.md#15-plan-变更记录) |
| 2026-06-14 | Step 04 从 SSH blocked 转为 in_progress，并记录最新真实失败 run | SSH 已恢复；当前 blocker 已变为 Hermes runtime 冷启动 / App message agent 复用策略问题 | [../plan.md#15-plan-变更记录](../plan.md#15-plan-变更记录) |
| 2026-06-14 | Step 04 done：真实远端 E2E PASS | run `20260614T024413341Z` 覆盖 App bootstrap、CLI peer send、Daemon/Hermes processing、message sync return 和 App hidden payload | [../plan.md#15-plan-变更记录](../plan.md#15-plan-变更记录) |

## 13. 风险、回滚与后续文档

- 风险：远端环境有真实用户/服务负载；测试使用固定短消息和测试账号，避免污染。
- 回滚 / 回退：回滚远端服务到部署前 commit 并重启；本地测试不能标完成。
- 后续文档：将最终可复用命令写入 `awiki-me/docs/testing.md` 或 runbook。
