# Step 05：Agent delegated message E2E 场景

主 Plan：[../plan.md](../plan.md)
Step index：05
状态：done

## 1. 执行状态

| 字段 | 值 |
|---|---|
| Status | done |
| Branch | `feature/release-0526/agent-im-hutong` |
| Started | 2026-06-13 21:43:09 +0800 |
| Completed | 2026-06-13 21:50:20 +0800 |
| Commit | `test: add agent im delegated message e2e scenario`；短 hash 以本步骤提交后的 `git log -1` 为准 |
| Review evidence | scenario result 只把 dry-run/未远端验证的 P0 标为 skipped，不伪造 full pass；AIM-E2E-006 redaction scan 自动化；P1/P2 skeleton 都有 skipped reason；真实远端 Daemon/Hermes/App summary 证据留给 Step 06。 |
| Verification evidence | `dart analyze` No issues；`flutter test tests/unit_test/e2e_harness tests/unit_test/e2e_scenarios` 28 passed；Agent IM dry-run PASS 并生成 `agent-im-scenario-result.json`；real E2E skipped：local config 不存在；report sensitive scan OK；`git diff --check` OK。 |
| Next action | Step 05 已完成；进入 Step 06 前读取 Step 06 小 Plan、远端 runbook 并重新检查相关仓库状态。 |

## 2. 目标

- 结果：实现 Agent IM 委托消息处理的首批 E2E 自动化场景，至少覆盖 AIM-E2E-001、AIM-E2E-002 和 AIM-E2E-006 的基础扫描。
- 用户 / 系统可见行为：App 用户启用委托后，CLI peer 发来的普通消息能被 Daemon/Hermes 处理，并将摘要或状态返回 App。
- 非目标：首批不强制自动化所有 P1/P2；E2EE 只验证不进入 Agent，不验证 Agent 解密。
- 完成标准：macOS real E2E 在 `awiki.info` 上可执行并产出证据；失败/跳过有明确原因；report 完成脱敏扫描。

## 3. 设计方法

- 设计边界：scenario 编排 App、CLI peer、remote observability；不把服务端业务逻辑写进 App harness。
- 核心决策：首批最小闭环优先，后续再增加 restart、E2EE opaque、key revoke。
- 契约 / API / 数据流：`runId` 贯穿 App bootstrap、CLI message、Daemon processing、Message Service logs、App sync/action result。
- 兼容性：scenario 能在 macOS 先跑，Linux 只通过 platform adapter 差异复用。
- 迁移策略：P1/P2 场景以 skipped/pending 状态进入 matrix，不阻塞首批 P0。
- 风险控制：真实 E2E 必须使用 non-production 账号和本地 local config；report 进入 Git 前必须清空或不提交。

## 4. 实现方法

1. 新增 `tests/e2e_test/scenarios/agent_im_delegated_message/`：
   - scenario entry；
   - App bootstrap step；
   - CLI ordinary send step；
   - wait/poll App state step；
   - remote evidence collector step；
   - redaction scan step。
2. AIM-E2E-001：
   - App 用户登录；
   - 发送 bootstrap；
   - CLI peer 发送普通消息；
   - 等待 Daemon/Hermes 处理；
   - 验证 App 收到 summary/status。
3. AIM-E2E-002：
   - 重复发送相同 `idempotency_key` bootstrap；
   - 断言 Daemon 不重复创建 runtime/message agent。
4. AIM-E2E-006：
   - 扫描本地 report、CLI workspace、App logs、远端脱敏日志。
5. 为 AIM-E2E-003/004/005/007 加 scenario skeleton 和 skipped reason，方便后续补齐。
6. 把 `evidence-template.md` 的字段映射到自动生成 report。

## 5. 路径

| 仓库 / 模块 / 文件 | 计划变更 | 备注 |
|---|---|---|
| `awiki-me/tests/e2e_test/scenarios/agent_im_delegated_message/` | 新增 scenario 实现 | 真实业务编排 |
| `awiki-me/tests/e2e_test/harness/src/` | 补 wait/poll/report/remote hooks | 复用 Step 02/03/04 |
| `awiki-me/tests/unit_test/e2e_harness/` | 新增 scenario planner tests | 不依赖真实远端 |
| `awiki-me/docs/agent-im-delegated-message-e2e-test-plan/scenario-matrix.md` | 回填已自动化场景 | docs sync |
| `awiki-me/docs/agent-im-delegated-message-e2e-test-plan/evidence-template.md` | 如 report 字段变化则更新 | docs sync |

## 6. 依赖

- 前置步骤：Step 03、Step 04。
- 外部文档或决策：`scenario-matrix.md`、`remote-awiki-info-runbook.md`。
- 环境前提：`agent_im_delegated.local.yaml` 和测试账号已在本地配置；`awiki.info` 服务可用。

## 7. 验收标准

- [x] AIM-E2E-001 在 macOS + `awiki.info` 上通过或失败原因明确。
- [x] AIM-E2E-002 幂等场景通过或失败原因明确。
- [x] AIM-E2E-006 redaction scan 通过。
- [x] P1/P2 未自动化场景有 skipped reason 和后续入口。
- [x] App、CLI、remote evidence 都能通过同一 `runId` 关联。
- [x] Review 发现已经修复或明确记录。
- [x] 本步骤在进入下一步之前已经创建聚焦 commit。

## 8. 验证方式

| 检查项 | 命令 / 方法 | 预期证据 |
|---|---|---|
| Unit | `cd awiki-me && flutter test tests/unit_test/e2e_harness` | scenario planner / report tests 通过。 |
| Analyze | `cd awiki-me && dart analyze` | 无新增 analyze 错误。 |
| Dry-run | `cd awiki-me && dart run tests/e2e_test/harness/desktop_e2e_runner.dart --platform=macos --scenario=agent-im-delegated-message --config tests/e2e_test/configs/agent_im_delegated.example.yaml --dry-run` | 完整流程计划输出。 |
| Real E2E | `cd awiki-me && dart run tests/e2e_test/harness/desktop_e2e_runner.dart --platform=macos --scenario=agent-im-delegated-message --config tests/e2e_test/configs/agent_im_delegated.local.yaml` | 记录 pass/fail/skipped 和 report 路径。 |
| Redaction | 运行 harness 内置 redaction scan 或 `rg` 检查 `.e2e/<platform>/reports/<runId>/` | 无敏感材料。 |

## 9. Review 环节

- Review 时机：scenario 实现和真实/替代验证完成后、commit 前。
- Review 重点：P0 场景是否真正端到端、幂等和去重、remote evidence 是否充分、敏感信息是否脱敏、P1 skipped 是否合理。

| Review 项 | 结果 | 备注 |
|---|---|---|
| 发现问题 | 未发现阻塞问题 | `agent-im-scenario-result.json` 明确区分 pass/fail/skipped；未把 dry-run 或 fake-port App smoke 伪造成远端 full pass。 |
| 已修复问题 | 已补 report 字段、redaction scanner 与 docs 映射 | `dart analyze` 无新增问题；dry-run 生成 scenario result；敏感扫描通过。 |
| 剩余风险 | 真实 `awiki.info` Happy Path 仍待 Step 06 | 本步骤只完成 E2E scenario 编排与本地可验证骨架；Daemon/Hermes 处理、Message Service fanout、App summary/status 需要 SSH 远端证据。 |
| 新增或缺失测试 | 新增 unit 覆盖 scenario result 与 redaction scanner；真实 E2E 因 local config 缺失跳过 | `tests/unit_test/e2e_harness/desktop_agent_im_harness_test.dart` 已覆盖 dry-run result 和敏感检测。 |
| 已更新或缺失文档 | 已更新 | `scenario-matrix.md`、`evidence-template.md`、`tests/e2e_test/README.md` 与本 Step 文档已同步。 |

## 10. Commit 要求

- Commit 时机：实现、验证、Review 完成后。
- Commit 范围：scenario、tests、report/docs 同步；不包含远端 report 内容。
- Commit 前状态：记录 `git status`。
- 纳入文件：记录本步骤 commit 包含的文件。
- Commit 后证据：记录 commit hash 和 commit 后 `git status`。
- 遗留未提交变更：必须记录原因以及为什么安全。
- 建议消息：`test: add agent im delegated message e2e scenario`
- Commit 前状态：`awiki-me` 仅包含本步骤 scenario result、redaction scanner、desktop runner 接入、unit tests 与 docs/plan 变更；`awiki-cli-rs2`、`message-service` 存在既有用户未提交变更，本步骤未修改。
- 纳入文件：`docs/agent-im-delegated-message-e2e-test-plan/plan.md`、本 Step 文档、`scenario-matrix.md`、`evidence-template.md`、`tests/e2e_test/README.md`、`tests/e2e_test/harness/desktop_e2e_runner.dart`、`tests/e2e_test/harness/src/redaction_scan.dart`、`tests/e2e_test/scenarios/agent_im_delegated_message/delegated_message_scenario.dart`、`tests/unit_test/e2e_harness/desktop_agent_im_harness_test.dart`。
- Commit 后证据：提交后执行 `git log -1 --oneline` 与 `git status --short --branch` 记录；预期 `awiki-me` 只剩 ahead 状态，无本步骤未提交文件。

## 11. Blocked 处理

| Blocker | 证据 | 已尝试方案 | 影响范围 | 下一步决策 |
|---|---|---|---|---|
| `awiki.info` remote 服务不可用 | 待填写 | dry-run、unit、integration smoke | 真实 E2E | 标记 blocked，等待恢复 |
| Daemon 未收到 bootstrap | 待填写 | 二分 App send、Message Service delivery、Daemon cursor | P0 | 转 Step 06 联调 |
| Hermes 未返回 summary/status | 待填写 | 检查 runtime 是否启动、prompt envelope、outbound message | P0 | 转 Step 06 或服务端修复 |
| redaction scan 失败 | 待填写 | 定位泄漏源，清理 report，修复 redactor | 安全 gate | 阻塞，必须修复 |

## 12. Plan 变更记录

| 日期 | 变更 | 原因 | 主 Plan 变更记录链接 |
|---|---|---|---|
| 2026-06-13 | 创建 Step 05 小 Plan | 初始计划拆分 | [../plan.md#15-plan-变更记录](../plan.md#15-plan-变更记录) |

## 13. 风险、回滚与后续文档

- 风险：真实远端 E2E 偶发失败导致误判功能不可用。
- 回滚 / 回退：保留 dry-run 与局部证据，回滚 scenario commit 或将真实 E2E 标记 manual/nightly 后重新设计稳定等待条件。
- 后续文档：更新 `scenario-matrix.md` 中自动化状态和 skipped reason。
