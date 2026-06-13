# Step 06：`awiki.info` 远端联调与服务侧补强

主 Plan：[../plan.md](../plan.md)  
Step index：06  
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
| Next action | 等待 Step 05 后进行 remote evidence 和服务侧缺口处理 |

## 2. 目标

- 结果：把 `awiki-me` E2E run 与 `awiki.info` 远端 User Service、Message Service、Daemon、Hermes 的日志和部署状态打通，并在发现服务侧缺口时按仓库补测试或修复。
- 用户 / 系统可见行为：失败时能通过 runId 快速定位是 App、CLI、Message Service、User Service、Daemon 还是 Hermes 问题。
- 非目标：不在文档中记录远端真实路径或密钥；不做无 commit 的远端临时 hotfix。
- 完成标准：remote runbook 被实际验证；必要服务端改动有本地 commit、验证证据、部署版本和回滚方案。

## 3. 设计方法

- 设计边界：远端联调先观测，后修改；服务端行为属于各服务仓库，不写进 `awiki-me` harness。
- 核心决策：`ssh ali` 是 remote access；本地 report 只保存脱敏后的 runId 证据摘要。
- 契约 / API / 数据流：按链路二分：App send -> Message Service delivery/fanout -> Daemon inbox/cursor -> Hermes prompt/result -> Daemon outbound -> App sync/action。
- 兼容性：远端部署版本必须记录；本地代码与远端版本不一致时不能把失败直接归因于代码。
- 迁移策略：服务端需要变更时，按对应仓库执行测试和 commit；部署后记录回滚方式。
- 风险控制：所有远端日志先脱敏再写入 evidence；生产状态不允许重启时，不强行执行 restart 场景。

## 4. 实现方法

1. 用 `ssh ali` 验证连接和服务健康；记录服务版本或部署 commit。
2. 执行 Step 05 的真实 E2E，取得 runId。
3. 按 runId 收集远端脱敏证据：
   - User Service DID Document public method / authentication；
   - Message Service delegated proof/fanout；
   - Daemon bootstrap、delegated identity、cursor、processed message；
   - Hermes untrusted content envelope 与 result；
   - Daemon outbound sync/action。
4. 如果发现服务侧缺口：
   - 在对应仓库增加 focused test；
   - 修复代码；
   - 运行仓库验证；
   - Review；
   - commit；
   - 按现有部署流程部署并记录版本与回滚。
5. 如 App-side E2E 无法覆盖某服务契约，补 `awiki-system-test` focused remote/local case。
6. 更新 `remote-awiki-info-runbook.md` 和 evidence template 的实际字段，不写入远端绝对路径或密钥。

## 5. 路径

| 仓库 / 模块 / 文件 | 计划变更 | 备注 |
|---|---|---|
| `awiki-me/docs/agent-im-delegated-message-e2e-test-plan/remote-awiki-info-runbook.md` | 回填实际可复用联调检查项 | 不写秘密和绝对路径 |
| `awiki-me/tests/e2e_test/harness/src/` | 必要时补 remote evidence collector/redactor | 只保存脱敏摘要 |
| `awiki-cli-rs2/crates/awiki-deamon/` | 如 Daemon 缺口，补测试/修复 | 可能受影响 |
| `message-service/` | 如 delegated proof/fanout 缺口，补测试/修复 | 可能受影响 |
| `user-service/` | 如 DID public method/authentication 缺口，补测试/修复 | 可能受影响 |
| `awiki-system-test/` | 如需要跨服务契约测试，新增 focused case | 可能受影响 |

## 6. 依赖

- 前置步骤：Step 05。
- 外部文档或决策：`remote-awiki-info-runbook.md`、各服务仓库 README/SPEC/API docs。
- 环境前提：`ssh ali` 可连接；有权限查看服务日志和部署状态；部署操作需用户允许或已有项目约定。

## 7. 验收标准

- [ ] `ssh ali` 联调路径验证过，或不可用原因已记录。
- [ ] 每个真实 E2E run 的本地/远端证据能用 runId 关联。
- [ ] 远端日志证据已脱敏。
- [ ] 服务端缺口如存在，已在对应仓库补测试/修复/commit。
- [ ] 部署版本和回滚方式已记录，未把远端路径/密钥写入仓库。
- [ ] Review 发现已经修复或明确记录。
- [ ] 本步骤在进入下一步之前已经创建聚焦 commit。

## 8. 验证方式

| 检查项 | 命令 / 方法 | 预期证据 |
|---|---|---|
| Remote access | `ssh ali` | 能连接；若失败记录错误，不输出敏感信息。 |
| Daemon tests | `cd awiki-cli-rs2 && cargo test -p awiki-deamon --locked` | 如改 Daemon，测试通过。 |
| Message Service tests | `cd message-service && cargo test --workspace` | 如改消息服务，测试通过。 |
| User Service tests | `cd user-service && uv run pytest tests/app/did -v` | 如改 DID/auth，测试通过。 |
| System test | `cd awiki-system-test && AWIKI_SYSTEM_TEST_MODE=remote E2E_DID_DOMAIN=awiki.info E2E_USER_SERVICE_URL=https://awiki.info E2E_MESSAGE_SERVICE_URL=https://awiki.info E2E_MESSAGE_SERVICE_WS_URL=wss://awiki.info/im/ws AWIKI_CLI_RUST_REPO=../awiki-cli-rs2 uv run awiki-system-test --show-command` | 如补服务侧契约测试，记录通过/失败/跳过数量。 |
| E2E rerun | `cd awiki-me && dart run tests/e2e_test/harness/desktop_e2e_runner.dart --platform=macos --scenario=agent-im-delegated-message --config tests/e2e_test/configs/agent_im_delegated.local.yaml` | 修复后 P0 场景通过或失败原因变化清楚。 |

## 9. Review 环节

- Review 时机：远端证据收集和服务侧修复完成后、commit 前；部署前也要 Review。
- Review 重点：日志脱敏、部署版本一致性、服务端契约、回滚方案、是否引入生产降级或 mock。

| Review 项 | 结果 | 备注 |
|---|---|---|
| 发现问题 | 待填写 |  |
| 已修复问题 | 待填写 |  |
| 剩余风险 | 待填写 |  |
| 新增或缺失测试 | 待填写 |  |
| 已更新或缺失文档 | 待填写 |  |

## 10. Commit 要求

- Commit 时机：每个受影响仓库实现、验证、Review 完成后。
- Commit 范围：按仓库拆分；`awiki-me` remote docs/harness、`awiki-cli-rs2` Daemon、`message-service`、`user-service`、`awiki-system-test` 分别聚焦。
- Commit 前状态：记录各仓 `git status`。
- 纳入文件：记录本步骤 commit 包含的文件。
- Commit 后证据：记录 commit hash 和 commit 后 `git status`。
- 遗留未提交变更：必须记录原因以及为什么安全。
- 建议消息：`test: integrate agent im remote evidence` 或按具体仓库功能命名。

## 11. Blocked 处理

| Blocker | 证据 | 已尝试方案 | 影响范围 | 下一步决策 |
|---|---|---|---|---|
| `ssh ali` 无权限或不可达 | 待填写 | 本地 dry-run、请求用户确认 SSH | remote gate | 标记 blocked |
| 不能重启远端 Daemon | 待填写 | 跳过 restart 场景，改本地/独立环境测 | AIM-E2E-003 | 记录 skipped reason |
| 远端版本不是当前分支 | 待填写 | 记录版本差异，请求部署确认 | 真实 E2E | 等待部署或标记不一致 |
| 服务端缺口跨仓较大 | 待填写 | 更新 Plan，拆更多步骤 | 整体计划 | 先停在当前 step |

## 12. Plan 变更记录

| 日期 | 变更 | 原因 | 主 Plan 变更记录链接 |
|---|---|---|---|
| 2026-06-13 | 创建 Step 06 小 Plan | 初始计划拆分 | [../plan.md#15-plan-变更记录](../plan.md#15-plan-变更记录) |

## 13. 风险、回滚与后续文档

- 风险：远端联调无意暴露生产数据或造成服务扰动。
- 回滚 / 回退：停止真实 E2E，删除本地敏感 report，回滚服务端部署到上一个记录版本。
- 后续文档：把稳定联调步骤保留在 runbook；服务端 API/契约变化更新各自 docs。
