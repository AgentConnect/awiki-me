# Step 01：上下文与契约基线核对

主 Plan：[../plan.md](../plan.md)  
Step index：01  
状态：done

## 1. 执行状态

| 字段 | 值 |
|---|---|
| Status | done |
| Branch | `feature/release-0526/agent-im-hutong` |
| Started | 2026-06-13 20:44:29 +0800 |
| Completed | 2026-06-13 20:47:00 +0800 |
| Commit | `docs: baseline agent im e2e contracts`；短 hash 以本步骤提交后的 `git log -1` 为准 |
| Review evidence | Review 完成：确认基线覆盖 App bootstrap、CLI peer、Daemon delegated inbox、Message Service delegated local view、User Service delegated public key、system-test 相邻覆盖、ANP SDK 依赖边界和 P0 缺口；未发现需要修改生产代码的问题。 |
| Verification evidence | 文档路径、相对链接、敏感信息扫描、`git diff --check` 通过；未运行功能测试，原因是本步骤为 docs-only/read-only 基线。 |
| Next action | 启动 Step 02：E2E harness 基础扩展 |

状态取值：`pending`、`in_progress`、`review`、`blocked`、`committed`、`done`。

## 2. 目标

- 结果：确认 Agent IM 委托消息处理 E2E 的当前契约、代码入口、测试入口和缺口，避免后续实现阶段一边写 harness 一边反复改需求。
- 用户 / 系统可见行为：执行完成后，Plan 和方案文档中能清楚说明哪些能力已经存在、哪些需要在后续 Step 补齐。
- 非目标：本步骤不实现 E2E runner，不修改服务端行为，不登录远端部署。
- 完成标准：形成 contract/gap 清单，更新主 Plan 或方案文档中必要的假设与开放问题；Review 确认没有遗漏 P0 链路和安全边界；创建 docs-only commit。

## 3. 设计方法

- 设计边界：只做只读调研和文档校准，除必要的计划文档更新外不改生产代码。
- 核心决策：以子仓库权威 docs 和现有代码为准，Harness 只作为路由控制面。
- 契约 / API / 数据流：重点核对 `awiki.daemon.bootstrap.v1`、`awiki.message.sync.v1`、`awiki.app.action.result.v1`、`user_did#daemon-key-1`、Message Service delegated proof/fanout、E2EE opaque ignore。
- 兼容性：确认当前 `awiki-me` E2E 框架仍是 `tests/e2e_test/`，根级 `integration_test/` 只允许 Flutter tooling shim。
- 迁移策略：本步骤不迁移文件。
- 风险控制：记录每个相关仓库 `git status --short --branch`，避免混入用户既有变更。

## 4. 实现方法

1. 记录相关仓库状态：`awiki-me`、`awiki-cli-rs2`、`awiki-system-test`、`message-service`、`user-service`。
2. 阅读并摘录当前契约：
   - `awiki-cli-rs2/docs/agent-im/agent_im_core_design.md`
   - `awiki-cli-rs2/docs/agent-im/agent_delegated_identity_message_proof_plan.md`
   - `awiki-cli-rs2/docs/agent-im/plan/steps/05-awiki-deamon-user-delegated-inbox-sync.md`
   - `awiki-cli-rs2/docs/agent-im/plan/steps/06-awiki-me-pairing-bootstrap-ui-service.md`
   - `awiki-cli-rs2/docs/agent-im/plan/steps/07-message-service-delegated-key-policy-and-fanout.md`
   - `awiki-cli-rs2/docs/agent-im/plan/steps/08-app-action-schema-and-visibility.md`
3. 检查 `awiki-me/tests/e2e_test/` 当前 runner、README、config、scenarios 目录，确认可扩展点。
4. 检查 `awiki-cli-rs2` 是否已有 CLI peer 所需命令或测试 helper：账号登录/恢复、发送普通消息、可选发送 E2EE 消息、状态查询。
5. 检查 `awiki-me` 是否已有 App bootstrap service/UI/reducer/test entry 可自动触发和观测。
6. 输出 gap 清单，必要时更新 `README.md`、`scenario-matrix.md` 或主 Plan 的开放问题。

## 5. 路径

| 仓库 / 模块 / 文件 | 计划变更 | 备注 |
|---|---|---|
| `awiki-me/docs/agent-im-delegated-message-e2e-test-plan/plan.md` | 回填基线结论和 gap | docs-only |
| `awiki-me/docs/agent-im-delegated-message-e2e-test-plan/README.md` | 必要时校准方案 | docs-only |
| `awiki-me/docs/agent-im-delegated-message-e2e-test-plan/scenario-matrix.md` | 必要时调整场景优先级 | docs-only |
| `awiki-me/tests/e2e_test/` | 只读调研 | 后续 Step 才修改 |
| `awiki-cli-rs2/docs/agent-im/` | 只读调研 | 后续如发现文档漂移再计划修改 |
| `awiki-cli-rs2/crates/awiki-deamon/` | 只读调研 | 检查 daemon 能力入口 |
| `message-service/` | 只读调研 | 检查 delegated proof/fanout 测试 |
| `user-service/` | 只读调研 | 检查 DID Document public method 测试 |

## 6. 依赖

- 前置步骤：无。
- 外部文档或决策：主 Plan、方案文档、Harness baseline。
- 环境前提：本地仓库可读；无需远端环境。

## 7. 验收标准

- [x] 已记录相关仓库 `git status --short --branch`。
- [x] 已确认 `awiki-me` E2E 扩展点和 Flutter integration shim 约束。
- [x] 已确认 CLI peer、App bootstrap、Daemon/service 观测的 P0 缺口。
- [x] 已更新主 Plan 或方案文档中的假设、开放问题、风险。
- [x] Review 发现已经修复或明确记录。
- [x] 本步骤在进入下一步之前已经创建聚焦 commit。

## 8. 验证方式

| 检查项 | 命令 / 方法 | 预期证据 |
|---|---|---|
| Git 状态 | `git -C awiki-me status --short --branch` 等相关仓库状态命令 | 记录既有变更，避免混入本步骤 commit。 |
| 文档路径 | `cd awiki-me && find docs/agent-im-delegated-message-e2e-test-plan -type f -name '*.md' -print` | 本目录文档存在。 |
| 链接 Review | 人工打开 `plan.md` 到各 Step 的相对链接 | 链接正确。 |
| 敏感信息 | 使用临时 Python 扫描器拼接 private-key、bearer-style、JWT-like、refresh/access token、OTP-value matcher，并扫描 `awiki-me/docs/agent-im-delegated-message-e2e-test-plan` | 不出现真实私钥、token、OTP 值；环境变量名如需出现必须不带值。 |

如果某个命令不能运行，必须记录原因、影响和替代证据。

### Step 01 验证记录

| 命令 / 检查 | 结果 | 说明 |
|---|---|---|
| `cd awiki-me && find docs/agent-im-delegated-message-e2e-test-plan -type f -name '*.md' -print` | 通过 | 输出本目录 13 个 Markdown 文档。 |
| 临时 Python Markdown link checker | 通过 | 本目录 Markdown 相对链接均可解析。 |
| 临时 Python machine-specific path scan | 通过 | 未发现本机绝对路径或工作区目录名。 |
| 临时 Python sensitive scan | 通过 | 未发现 private-key、bearer-style、JWT-like、token-value、OTP-value matcher 命中。 |
| `git -C awiki-me diff --check` | 通过 | 无 whitespace/error marker。 |
| 功能测试 | 未运行 | Step 01 为 docs-only/read-only 基线，不修改生产代码或测试代码。 |

## 9. Review 环节

- Review 时机：gap 清单和文档更新完成后、commit 前。
- Review 重点：契约完整性、P0 场景覆盖、路径归属、E2EE 边界、安全隐私、是否误用旧 `awiki-cli`。
- Review 结论必须在 commit 前记录；必须修复必要问题，或明确记录剩余风险。

| Review 项 | 结果 | 备注 |
|---|---|---|
| 发现问题 | 有发现 | `awiki-me` harness 缺少 scenario/config/report/redaction；CLI peer 未封装账号与发送；App bootstrap 缺少 E2E entry；Daemon `message_sync_outbox` delivery path 需要 Step 05/06 证明或补齐；ANP 本地源码可能领先发布版。 |
| 已修复问题 | 已修复文档 | 新增 [../context-contract-baseline.md](../context-contract-baseline.md)，并在主 Plan 与 README 中链接和回填 Step 01 基线结论。 |
| 剩余风险 | 已记录 | 远端服务管理方式仍需 Step 06 通过 `ssh ali` 发现；sync outbox 到 App 的真实 delivery 尚无本步骤证据；本步骤未运行功能测试。 |
| 新增或缺失测试 | 无新增测试 | 本步骤 docs-only；后续 Step 02-05 增加 harness/scenario 单测与 E2E。 |
| 已更新或缺失文档 | 已更新 | 更新 `plan.md`、`README.md`、本 Step 文档，并新增 `context-contract-baseline.md`。 |

## 10. Commit 要求

- Commit 时机：文档校准、验证、Review 完成后。
- Commit 范围：只包含 Step 01 的 docs/gap 清单。
- Commit 前状态：记录 `git status`。
- 纳入文件：记录本步骤 commit 包含的文件。
- Commit 后证据：记录 commit hash 和 commit 后 `git status`。
- 遗留未提交变更：必须记录原因以及为什么安全。
- 建议消息：`docs: baseline agent im e2e contracts`

执行记录：

| 项 | 记录 |
|---|---|
| Commit 前状态 | `awiki-me`：`docs/agent-im-delegated-message-e2e-test-plan/` 为本步骤新增/修改；`awiki-cli-rs2` 和 `message-service` 有既有未提交变更但本步骤不触碰；`awiki-system-test`、`user-service` 干净。 |
| 纳入文件 | `docs/agent-im-delegated-message-e2e-test-plan/README.md`、`context-contract-baseline.md`、`plan.md`、`steps/01-context-contract-baseline.md`，以及该计划目录内初始文档。 |
| Commit 后证据 | 待提交后由 `git log -1 --oneline` 确认；短 hash 不写入同一提交正文，避免自引用 hash 无法稳定。 |
| 遗留未提交变更 | 仅保留其他仓库既有用户变更；Step 01 不修改这些仓库。 |

## 11. Blocked 处理

| Blocker | 证据 | 已尝试方案 | 影响范围 | 下一步决策 |
|---|---|---|---|---|
| 关键契约文档缺失或互相冲突 | 待填写 | 搜索代码和测试；询问用户决策 | 整体计划 | 更新开放问题并阻塞后续实现 |
| 相关仓库存在大量未提交变更 | 待填写 | 记录状态，避免修改该仓库 | 当前步骤 / 后续 commit | 请求用户确认或只改 `awiki-me` docs |

## 12. Plan 变更记录

| 日期 | 变更 | 原因 | 主 Plan 变更记录链接 |
|---|---|---|---|
| 2026-06-13 | 创建 Step 01 小 Plan | 初始计划拆分 | [../plan.md#15-plan-变更记录](../plan.md#15-plan-变更记录) |

## 13. 风险、回滚与后续文档

- 风险：基线调研遗漏真实代码状态，导致后续 Step 反复返工。
- 回滚 / 回退：回滚本步骤 docs commit，重新读取权威 docs 后更新 Plan。
- 后续文档：若发现 `awiki-cli-rs2/docs/agent-im/` 与代码不一致，后续 Step 需同步更新对应仓库 docs。
