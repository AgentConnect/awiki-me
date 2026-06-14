# Step 02：场景矩阵与标签/gate 契约

主 Plan：[../plan.md](../plan.md)  
Step index：02  
状态：done

## 1. 执行状态

| 字段 | 值 |
|---|---|
| Status | done |
| Branch | `feature/test-awiki-me` |
| Started | 2026-06-14 12:58 CST |
| Completed | 2026-06-14 13:02 CST |
| Commit | `cacfde6` |
| Review evidence | Review 完成：标签、gate、case 字段、晋级/降级规则覆盖基础 E2E 和回归保护；真实后端和 App/CLI peer 未进入 PR required；`AGENT-SKIP-001` 与 `E2EE-SKIP-001` 保持 skipped。 |
| Verification evidence | `awk ... uniq -d` 检查矩阵 Case ID 无重复；`find docs/e2e/awiki-me-e2e-regression-plan -type f -name '*.md' -print | sort` 通过；`git diff --check -- docs/e2e/awiki-me-e2e-regression-plan` 通过；敏感信息/绝对路径扫描仅命中 Step 05 的 env 变量名示例，无真实 secret。 |
| Next action | 启动 Step 03：测试环境、账号和数据隔离契约 |

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
   - `pr-optional`：Linux/macOS runner 或 native SDK smoke，允许需要桌面 runner，但不能依赖真实后端。
   - `nightly`：真实后端/账号/设备可用时运行。
   - `release`：发布前必须通过或明确豁免。
   - `manual`：人工准备环境或排障运行，不作为自动 gate 通过条件。
   - `skipped`：本轮明确保留记录但不实现、不运行、不进入 gate。
4. 定义 case 晋级规则：feature case 连续稳定后提升为 regression case。
5. 将矩阵回填到主 Plan 或独立文档。

### 4.1 标签定义

| 标签 | 运行目的 | 环境边界 | 维护规则 |
|---|---|---|---|
| `smoke` | 快速确认 App、runner、SDK 或 harness 可启动。 | 不依赖真实后端、OTP、账号池或移动设备池。 | 失败时优先阻断更高层 E2E；可进入 PR optional。 |
| `feature` | 新功能首版验证。 | 可依 manual config、临时账号池或 nightly 环境。 | 默认不进 PR required；稳定后按规则晋级。 |
| `regression` | 保护已经稳定的核心能力。 | 依 gate 决定是否允许真实后端。 | 必须有可复查证据和失败诊断路径。 |
| `pr-required` | 普通 PR 必跑。 | 只能使用确定性本地检查、unit/widget、parser、dry-run。 | 不允许接真实后端、OTP、设备池或 SSH。 |
| `pr-optional` | 可选或 self-hosted 的桌面确定性检查。 | 允许 macOS/Linux desktop runner、native SDK 和 `xvfb-run`。 | 失败不应由账号或远端服务波动触发。 |
| `nightly` | 定时真实闭环。 | 可使用非生产后端、账号池、OTP、App/CLI peer、设备池。 | 必须输出脱敏 report、runId 和环境证据。 |
| `release` | 发布前 P0/P1 gate。 | 可使用 release 测试环境和设备池。 | 失败或跳过必须有显式豁免记录。 |
| `manual` | 人工验证、排障或临时环境运行。 | 可依人工准备的服务、账号和设备。 | 结果不能被表述为自动 gate 通过。 |
| `skipped` | 明确延期。 | 不要求环境。 | 本轮不实现、不运行、不加入任何 gate。 |

### 4.2 Gate 分层

| Gate | 目标 | 接收范围 | 排除范围 |
|---|---|---|---|
| PR required | 给每个 PR 提供快速、确定性的回归保护。 | `dart analyze`、unit/widget、harness parser、dry-run、docs/secret scan。 | 真实后端、OTP、账号池、App/CLI 真消息、移动设备池。 |
| PR optional desktop | 验证桌面 runner 和 native SDK 可用。 | `app_smoke_test.dart`、`im_core_open_smoke_test.dart`、Linux `xvfb-run`。 | 注册/恢复、真实消息、群组、附件、移动设备。 |
| Nightly desktop | 验证 macOS/Linux App + CLI peer 真正闭环。 | 账号准备、双向 direct message、history/inbox、群组、附件基础路径。 | `skipped` 场景、未脱敏报告、绕过 SDK/CLI 的测试。 |
| Nightly mobile | 验证 iOS/Android 两设备基础消息互通。 | Maestro flows、mobile runner、账号池和设备日志。 | 桌面专属 smoke、没有设备证据的伪通过。 |
| Release | 发布前保护核心用户路径。 | 已稳定的 P0/P1 `regression` 和必要 `smoke`。 | 未稳定 `feature`、`manual`、`skipped`。 |
| Manual | 支持本地排障和人工 release 辅助。 | 临时账号、局部服务、排障用真实 E2E。 | 不能替代自动 gate，除非 release 记录明确豁免。 |

### 4.3 Case 字段

后续新增或维护 E2E case 时，每个 case 必须至少记录：

| 字段 | 说明 |
|---|---|
| Case ID | 全局唯一，按领域前缀命名，例如 `MSG-E2E-001`。 |
| Owner domain | App shell、Auth、Direct Message、Group、Attachment、Profile/Settings、Mobile 或 Deferred。 |
| Platform | macOS、Linux、iOS、Android 或组合；桌面 case 默认共享 scenario。 |
| Peer topology | no-peer、App + CLI peer、two mobile devices、App + mobile peer、system-only 或 deferred。 |
| Backend dependency | no-backend、dry-run、real non-production backend 或 local system-test backend。 |
| Data / secret requirement | 只记录 env 名、账号池角色和 fixture 名，不记录敏感值。 |
| Gate | PR required、PR optional desktop、nightly desktop、nightly mobile、release、manual 或 skipped。 |
| Pass evidence | 命令、runId、history/inbox evidence、UI/service assertion、report、redaction scan。 |
| Skip / blocker rule | 缺账号、缺设备、缺 Linux runner、缺 CLI/SDK 高层能力时如何处理。 |

### 4.4 晋级和降级规则

- `feature` case 只有在目标 nightly 环境连续稳定通过至少三次，并完成 Review 后，才能晋级为 `regression`。
- `regression` case 如果被证明不稳定，应先降级为 quarantine/manual，并在主 Plan 变更记录中说明原因、影响和恢复条件。
- `pr-required` 不允许新增真实后端、OTP、设备池或 App/CLI 真实互通依赖。
- `skipped` case 只有在用户显式扩大本轮范围后才能转为 `feature`；本轮 `AGENT-SKIP-001` 和 `E2EE-SKIP-001` 固定为 skipped。
- 群组和附件如果缺少 CLI/SDK 高层命令，只能记录 blocker 或补最小高层能力，不能直接拼 message-service payload、WebSocket frame、SQLite 或内部存储对象。

### 4.5 本步骤矩阵落点

- 主 Plan 第 7 节新增标签契约、gate 契约、case 字段契约和晋级/降级规则。
- 主 Plan 第 8 节将场景矩阵扩展为可执行字段：Case ID、Owner domain、Tags、Platform、Peer topology、Backend/data dependency、Gate、当前基础和验收/blocker 规则。
- `AGENT-SKIP-001` 与 `E2EE-SKIP-001` 保留在矩阵中，`Tags` 和 `Gate` 均标记为 skipped，不进入任何自动 gate。

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

- [x] 每个核心 E2E 场景有唯一 case id。
- [x] 每个 case 明确平台、依赖、gate 和是否真实后端。
- [x] PR required、PR optional、nightly、release 的边界清楚。
- [x] 新功能如何进入 E2E 矩阵有明确规则。
- [x] Agent 作为 IM App 处理者和端到端加密被列为 skipped，而不是从矩阵中删除。
- [x] Review 发现已经修复或明确记录。
- [x] 本步骤在进入下一步之前已经创建聚焦 commit。

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
| 发现问题 | 无阻断问题 | Review 确认 PR required 不包含真实后端、OTP、设备池或真实 App/CLI peer E2E。 |
| 已修复问题 | 已修正文档契约 | 补齐 `pr-optional`、`manual`、case 字段、gate 分层和晋级/降级规则；主 Plan 的执行协议改为当前 Goal 已进入执行阶段。 |
| 剩余风险 | 后续实现需继续验证 CLI/SDK 高层能力 | 群组和附件是否具备高层命令留到 Step 06 处理，不能通过内部 payload 绕过。 |
| 新增或缺失测试 | 未新增测试 | 本步骤只定义文档契约，不修改测试实现。 |
| 已更新或缺失文档 | 已更新主 Plan 和当前 Step | `docs/e2e/awiki-me-e2e-regression-plan/plan.md`、本文件。 |

## 10. Commit 要求

- Commit 时机：矩阵、标签、gate 契约完成并通过 Review 后。
- Commit 范围：只包含矩阵/标签相关文档。
- Commit 前状态：记录 `git status --short --branch`。
- 纳入文件：记录本步骤 commit 包含的文件。
- Commit 后证据：记录 commit hash 和 commit 后 `git status`。
- 建议消息：`docs: define e2e scenario gates`
- Commit 前状态：`git status --short --branch` 显示仅本步骤两个已修改文档和一个无关未跟踪旧草稿目录；未跟踪目录不纳入提交。
- 纳入文件：`docs/e2e/awiki-me-e2e-regression-plan/plan.md`、`docs/e2e/awiki-me-e2e-regression-plan/steps/02-scenario-matrix-tags.md`。
- Commit 后状态：本步骤提交后用 `git status --short --branch` 复核；预期仅保留无关未跟踪旧草稿目录。

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
