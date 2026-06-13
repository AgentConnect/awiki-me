# Step 07：最终全局 Review 与整体验证收口

主 Plan：[../plan.md](../plan.md)  
Step index：07  
状态：draft

## 1. 执行状态

| 字段 | 值 |
|---|---|
| Status | pending |
| Branch | `feature/release-0526/agent-im-hutong` |
| Started | 待执行 |
| Completed | 待执行 |
| Commit | 待填写 |
| Review evidence | 待填写 |
| Verification evidence | 待填写 |
| Next action | 等待 Step 01-06 全部 done 后执行 |

## 2. 目标

- 结果：对 Agent IM 委托消息处理 E2E 测试体系进行最终全局 Review、整体验证、文档与台账收口。
- 用户 / 系统可见行为：用户可以从 Plan 和 evidence 中判断测试框架是否已能验证核心功能，并看到剩余风险与后续场景。
- 非目标：不在最终阶段塞入大规模新功能；发现重大缺口时回到对应 Step 或更新 Plan。
- 完成标准：所有步骤状态、commit、Review 证据、验证证据完整；最终 `git status` 清晰；P0 E2E 结果和安全检查结论已记录。

## 3. 设计方法

- 设计边界：最终阶段只做整合、Review、验证、文档同步和小修；大功能缺口回到前置 Step。
- 核心决策：以主 Plan 执行台账为事实来源，逐仓库核对 changed files、commit 和未提交变更。
- 契约 / API / 数据流：重新核对 App -> Daemon bootstrap -> Message Service delegated fanout -> Hermes -> App sync/action 的完整证据。
- 兼容性：确认无 scenario 参数的旧 smoke、Mac dry-run、Linux dry-run 仍可用或跳过原因明确。
- 迁移策略：如果最终 Review 发现文档漂移，先更新 docs，再执行文档验证和最终 commit。
- 风险控制：最终报告必须列出未运行命令、失败或跳过原因、剩余风险。

## 4. 实现方法

1. 读取主 Plan 执行台账，确认 Step 01-06 状态均为 `done` 或有明确跳过/blocked 处理。
2. 对所有受影响仓库运行 `git status --short --branch` 并记录。
3. 做全局 Review：
   - `awiki-me` harness/scenario/config/report；
   - `awiki-cli-rs2` CLI/Daemon/im-core；
   - `message-service` delegated proof/fanout；
   - `user-service` DID Document public method；
   - `awiki-system-test` focused coverage；
   - docs/evidence/security。
4. 运行第 8 节整体验证命令；无法运行项记录原因。
5. 扫描 report/log 文档中是否包含敏感值；删除或 gitignore 本地 report。
6. 回填主 Plan 第 7、15、17 节和各 Step 执行状态。
7. 如本阶段修改文件，Review 后创建最终聚焦 commit。

## 5. 路径

| 仓库 / 模块 / 文件 | 计划变更 | 备注 |
|---|---|---|
| `awiki-me/docs/agent-im-delegated-message-e2e-test-plan/plan.md` | 回填最终 Review、验证、风险和台账 | 必改 |
| `awiki-me/docs/agent-im-delegated-message-e2e-test-plan/steps/*.md` | 回填各 step 最终状态 | 必要时 |
| `awiki-me/docs/agent-im-delegated-message-e2e-test-plan/evidence-template.md` | 如证据字段变化则更新 | docs sync |
| `awiki-me/docs/testing.md` | 如 runner 命令已变化则更新 | docs sync |
| 所有受影响仓库 | 最终 `git status` 和必要 docs/test 收口 | 不做大功能 |

## 6. 依赖

- 前置步骤：Step 01-06 已完成、验证、Review、commit；如某步骤 blocked，必须有用户决策或替代证据。
- 外部文档或决策：主 Plan、第 11 节验证策略、各仓库验证命令。
- 环境前提：本地工具链和 `awiki.info` 可用；若不可用则记录未运行原因。

## 7. 验收标准

- [ ] Step 01-06 执行台账完整，commit hash 和验证证据已记录。
- [ ] 全局 Review 无未处理 P0/P1 问题。
- [ ] P0 E2E 场景结果明确：通过、失败或 blocked/skipped 原因。
- [ ] 敏感信息扫描通过。
- [ ] 文档与实际命令/路径一致。
- [ ] 所有受影响仓库最终 `git status` 已记录。
- [ ] 如果本步骤修改文件，已经创建聚焦最终 commit。

## 8. 验证方式

| 检查项 | 命令 / 方法 | 预期证据 |
|---|---|---|
| awiki-me analyze | `cd awiki-me && dart analyze` | 无新增错误。 |
| awiki-me unit | `cd awiki-me && flutter test tests/unit_test` | 单元测试通过。 |
| awiki-me integration | `cd awiki-me && flutter test integration_test/im_core_open_smoke_test.dart -d macos`；如新增 Agent IM shim，也运行对应 shim | integration smoke 通过或跳过原因明确。 |
| awiki-me E2E dry-run | `cd awiki-me && dart run tests/e2e_test/harness/desktop_e2e_runner.dart --platform=macos --scenario=agent-im-delegated-message --config tests/e2e_test/configs/agent_im_delegated.example.yaml --dry-run` | dry-run 通过。 |
| awiki-me E2E real | `cd awiki-me && dart run tests/e2e_test/harness/desktop_e2e_runner.dart --platform=macos --scenario=agent-im-delegated-message --config tests/e2e_test/configs/agent_im_delegated.local.yaml` | P0 场景结果记录。 |
| awiki-cli-rs2 | `cd awiki-cli-rs2 && cargo test -p awiki-deamon --locked && cargo test -p im-core --locked` | 如有相关改动，测试通过。 |
| message-service | `cd message-service && cargo test --workspace` | 如有相关改动，测试通过。 |
| user-service | `cd user-service && uv run pytest tests/app/did -v` | 如有相关改动，测试通过。 |
| awiki-system-test | `cd awiki-system-test && AWIKI_SYSTEM_TEST_MODE=remote E2E_DID_DOMAIN=awiki.info E2E_USER_SERVICE_URL=https://awiki.info E2E_MESSAGE_SERVICE_URL=https://awiki.info E2E_MESSAGE_SERVICE_WS_URL=wss://awiki.info/im/ws AWIKI_CLI_RUST_REPO=../awiki-cli-rs2 uv run awiki-system-test --show-command` | 如服务侧契约受影响，记录通过/失败/跳过。 |
| security scan | 对 `.e2e` report、CLI workspace、远端 evidence summary 做 redaction scan | 无敏感信息。 |
| git status | 对所有受影响仓库运行 `git status --short --branch` | 最终状态清晰，无遗漏未提交完成工作。 |

## 9. Review 环节

- Review 时机：所有验证完成后、最终 commit 前；如果最终验证失败，先判断是修复、记录风险还是回到前置 Step。
- Review 重点：跨仓一致性、P0 行为真实性、安全隐私、E2EE 边界、文档漂移、报告是否可复现、未提交变更。

| Review 项 | 结果 | 备注 |
|---|---|---|
| 发现问题 | 待填写 |  |
| 已修复问题 | 待填写 |  |
| 剩余风险 | 待填写 |  |
| 新增或缺失测试 | 待填写 |  |
| 已更新或缺失文档 | 待填写 |  |

## 10. Commit 要求

- Commit 时机：最终 Review、验证、文档回填完成后。
- Commit 范围：只包含最终文档/台账/小修；如果发现大功能缺口，回到对应 Step，不在本 commit 混入。
- Commit 前状态：记录各仓 `git status`。
- 纳入文件：记录本步骤 commit 包含的文件。
- Commit 后证据：记录 commit hash 和 commit 后 `git status`。
- 遗留未提交变更：必须记录原因以及为什么安全。
- 建议消息：`docs: finalize agent im e2e verification`

## 11. Blocked 处理

| Blocker | 证据 | 已尝试方案 | 影响范围 | 下一步决策 |
|---|---|---|---|---|
| P0 real E2E 无法运行 | 待填写 | dry-run、unit、integration、remote health | release confidence | 标记 blocked 或请求用户恢复环境 |
| security scan 失败 | 待填写 | 删除 report、修 redactor、轮换测试凭证 | 安全 gate | 阻塞，必须修复 |
| 跨仓状态无法提交 | 待填写 | 分仓记录 status，拆 commit | 当前步骤 | 请求用户处理无关变更 |

## 12. Plan 变更记录

| 日期 | 变更 | 原因 | 主 Plan 变更记录链接 |
|---|---|---|---|
| 2026-06-13 | 创建 Step 07 小 Plan | 初始计划拆分 | [../plan.md#15-plan-变更记录](../plan.md#15-plan-变更记录) |

## 13. 风险、回滚与后续文档

- 风险：最终阶段发现的大缺口被小修掩盖。
- 回滚 / 回退：回到对应 Step 更新 Plan 并重新执行，不做隐藏式最终修复。
- 后续文档：完成后可把稳定命令摘要回写 `awiki-me/docs/testing.md`，必要时再更新 Harness feature map。
