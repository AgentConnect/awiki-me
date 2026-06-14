# Step 02：场景矩阵与标签/gate 契约

主 Plan：[../plan.md](../plan.md)  
Step index：02  
状态：draft

## 1. 执行状态

| 字段 | 值 |
|---|---|
| Status | pending |
| Branch | 待执行时记录 |
| Started | 待记录 |
| Completed | 待记录 |
| Commit | 待记录 |
| Review evidence | 待记录 |
| Verification evidence | 待记录 |
| Next action | 基于 Step 01 基线定义场景矩阵、标签和 gate 分层 |

状态取值：`pending`、`in_progress`、`review`、`blocked`、`committed`、`done`。

## 2. 目标

- 结果：建立可维护的 E2E 场景矩阵和标签契约，支持“新功能验证”和“既有功能回归”两类目标。
- 用户 / 系统可见行为：后续新增功能时，开发者能明确应新增什么 E2E case、放在哪个 gate、需要什么环境。
- 非目标：不在本步骤实现具体测试 case。
- 完成标准：每个核心场景都有 case id、平台、环境依赖、gate、当前基础、验收方式和晋级规则。

## 3. 设计方法

- 设计边界：矩阵只描述测试目标和 gate，不写业务实现细节。
- 核心决策：使用 `feature`、`regression`、`smoke`、`nightly`、`release`、`manual` 等标签区分用途和运行时机。
- 契约 / API / 数据流：真实 E2E 必须跨越真实 App/SDK/CLI/backend 或 mobile peer；只用 fixture 的测试不能标记为 real E2E。
- 兼容性：macOS/Linux 桌面共享同一 case id；移动端在同一矩阵中单独标注 iOS/Android。
- 迁移策略：先把现有 smoke/dry-run/real E2E 纳入矩阵，再逐步补缺口。
- 风险控制：PR required gate 不包含真实后端、OTP、设备池或远端 SSH 依赖。

## 4. 实现方法

1. 从 Step 01 覆盖地图提取现有入口。
2. 为每个现有和计划中的 E2E 场景分配 case id。
3. 定义标签含义：
   - `smoke`：快速验证启动或关键依赖。
   - `feature`：新功能验证，可能只在 feature branch 或 manual run。
   - `regression`：稳定后加入 nightly/release，防止既有功能退化。
   - `pr-required`：确定性、无后端、可快速运行。
   - `nightly`：真实后端/账号/设备可用时运行。
   - `release`：发布前必须通过或明确豁免。
   - `skipped`：本轮明确保留记录但不实现、不运行、不进入 gate。
4. 定义 case 晋级规则：feature case 连续稳定后提升为 regression case。
5. 将矩阵回填到主 Plan 或独立文档。

## 5. 路径

| 仓库 / 模块 / 文件 | 计划变更 | 备注 |
|---|---|---|
| `test-awiki-me/docs/e2e/awiki-me-e2e-regression-plan/plan.md` | 更新场景矩阵和 gate 标签 | 主入口 |
| `test-awiki-me/docs/testing.md` | 后续实现时同步 gate 说明 | 本步骤可只规划 |
| `test-awiki-me/tests/e2e_test/scenarios/` | 后续实现时按 case id 放置 scenario | 本步骤不修改 |
| `test-awiki-me/tests/e2e_test/configs/` | 后续实现时补 example config | 本步骤不提交 local config |

## 6. 依赖

- 前置步骤：Step 01。
- 外部文档或决策：是否有稳定测试账号池和 nightly runner。
- 环境前提：无运行环境要求。

## 7. 验收标准

- [ ] 每个核心 E2E 场景有唯一 case id。
- [ ] 每个 case 明确平台、依赖、gate 和是否真实后端。
- [ ] PR required、PR optional、nightly、release 的边界清楚。
- [ ] 新功能如何进入 E2E 矩阵有明确规则。
- [ ] Agent 作为 IM App 处理者和端到端加密被列为 skipped，而不是从矩阵中删除。
- [ ] Review 发现已经修复或明确记录。
- [ ] 本步骤在进入下一步之前已经创建聚焦 commit。

## 8. 验证方式

| 检查项 | 命令 / 方法 | 预期证据 |
|---|---|---|
| Docs | 人工检查 case id、标签、gate 表格 | 没有重复 case id，gate 边界清楚。 |
| Diff | `cd test-awiki-me && git diff --check` | 无 Markdown 空白错误。 |
| Secret | 人工检查矩阵和示例 env | 只记录 env 名，不记录真实值。 |

## 9. Review 环节

- Review 时机：矩阵和标签契约完成后、commit 前。
- Review 重点：是否把真实 E2E 错放进 PR gate，是否遗漏回归保护，是否对 Linux/macOS/mobile 有不同标准，是否把协议验证过度塞进 UI E2E。
- Review 结论必须在 commit 前记录。

| Review 项 | 结果 | 备注 |
|---|---|---|
| 发现问题 | 待记录 |  |
| 已修复问题 | 待记录 |  |
| 剩余风险 | 待记录 |  |
| 新增或缺失测试 | 待记录 | 本步骤不新增测试 |
| 已更新或缺失文档 | 待记录 |  |

## 10. Commit 要求

- Commit 时机：矩阵、标签、gate 契约完成并通过 Review 后。
- Commit 范围：只包含矩阵/标签相关文档。
- Commit 前状态：记录 `git status --short --branch`。
- 纳入文件：记录本步骤 commit 包含的文件。
- Commit 后证据：记录 commit hash 和 commit 后 `git status`。
- 建议消息：`docs: define e2e scenario gates`

## 11. Blocked 处理

| Blocker | 证据 | 已尝试方案 | 影响范围 | 下一步决策 |
|---|---|---|---|---|
| 无法确认某场景是否应进 release gate | 待记录 | 先标 nightly/manual，记录决策点 | 当前步骤 | 等用户或 release owner 确认 |

## 12. Plan 变更记录

| 日期 | 变更 | 原因 | 主 Plan 变更记录链接 |
|---|---|---|---|
| 待记录 | 待记录 | 待记录 | [../plan.md#17-plan-变更记录](../plan.md#17-plan-变更记录) |

## 13. 风险、回滚与后续文档

- 风险：矩阵过大导致后续实现不可控。
- 回滚 / 回退：保留 P0 场景，P1/P2 场景移入 follow-up。
- 后续文档：Step 03 使用矩阵定义环境和数据契约。
