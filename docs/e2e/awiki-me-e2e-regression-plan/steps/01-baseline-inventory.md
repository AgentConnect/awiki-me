# Step 01：E2E 基线盘点与覆盖地图

主 Plan：[../plan.md](../plan.md)  
Step index：01  
状态：done

## 1. 执行状态

| 字段 | 值 |
|---|---|
| Status | done |
| Branch | `feature/test-awiki-me` |
| Started | 2026-06-14 12:52 CST |
| Completed | 2026-06-14 13:02 CST |
| Commit | 本步骤提交，短 hash 以 `git log -1` 为准 |
| Review evidence | 覆盖地图已按当前代码和文档核对；Agent 和 E2EE 明确保留为 skipped；未把 dry-run/skipped smoke 误记为真实 E2E。 |
| Verification evidence | `find docs/e2e/awiki-me-e2e-regression-plan -type f -name '*.md' -print` 通过；`git diff --check -- docs/e2e/awiki-me-e2e-regression-plan` 通过；敏感信息/绝对路径扫描通过。 |
| Next action | 启动 Step 02：场景矩阵与标签/gate 契约 |

状态取值：`pending`、`in_progress`、`review`、`blocked`、`committed`、`done`。

## 2. 目标

- 结果：形成当前 AWiki Me E2E 基线盘点，明确哪些功能已经有测试入口，哪些只是 dry-run 或 smoke，哪些仍缺真实 E2E。
- 用户 / 系统可见行为：后续新增测试时可以按覆盖地图放置 case，不再把 unit、integration、E2E 混在一起。
- 非目标：不新增测试实现，不修改 runner，不运行真实后端 E2E。
- 完成标准：覆盖地图至少包含 App shell、native SDK、onboarding/session、direct message、群组、附件、profile/settings、mobile 两设备；Agent 作为 IM App 处理者和端到端加密本轮标记为 `Skipped`。

## 3. 设计方法

- 设计边界：只读调研和文档更新，先冻结当前事实。
- 核心决策：把现有测试按 `unit`、`integration smoke`、`desktop real E2E`、`group/attachment E2E`、`mobile E2E` 分类。
- 契约 / API / 数据流：确认 App 侧 E2E 应通过 `OnboardingService`、`MessagingService`、UI semantics 或 Flutter integration entry，不用静态 `ModMessage` 伪造真实消息互通。
- 兼容性：保留根级 `integration_test/*.dart` shim，真实实现继续位于 `tests/integration_test/`。
- 迁移策略：本步骤只产出覆盖地图，后续步骤再修改代码。
- 风险控制：如果发现文档与代码不一致，先记录差异，不直接改实现。

## 4. 实现方法

1. 读取 `test-awiki-me/docs/testing.md`、`test-awiki-me/tests/e2e_test/README.md`、`test-awiki-me/tests/integration_test/README.md`。
2. 盘点 `test-awiki-me/tests/unit_test/`、`test-awiki-me/tests/integration_test/`、`test-awiki-me/tests/e2e_test/`、`test-awiki-me/integration_test/`、`test-awiki-me/tool/` 的入口。
3. 标注每个入口的性质：确定性、依赖后端、依赖设备、只 dry-run、真实双端、是否默认 skip。
4. 输出覆盖地图，作为 Step 02 场景矩阵的输入。

### 4.1 覆盖地图输出

| 能力域 | 当前入口 | 当前覆盖 | 性质 | 缺口 / 下一步 |
|---|---|---|---|---|
| App shell / onboarding shell | `test-awiki-me/tests/integration_test/app/app_smoke_test.dart`；`test-awiki-me/integration_test/app_smoke_test.dart` | fake bootstrap 下覆盖 AppShell、OnboardingPage、authenticated shell。 | 确定性 integration smoke。 | Step 04 固化 macOS/Linux smoke gate。 |
| Native SDK open | `test-awiki-me/tests/integration_test/native/im_core_open_smoke_test.dart`；`test-awiki-me/integration_test/im_core_open_smoke_test.dart` | 临时路径中打开 `AwikiImCore.open` 并校验路径。 | 确定性 desktop native smoke。 | Step 04 继续保留 Linux headless 条件和 native SDK 前提。 |
| 账号注册 / 恢复 | `test-awiki-me/integration_test/desktop_cli_peer_smoke_test.dart`；`test-awiki-me/tool/desktop_cli_peer_e2e_runner.dart` | App recover/register；CLI peer recover/register；真实服务配置通过 env 注入。 | 真实后端 E2E 前置；默认 skip。 | Step 03/05 细化账号池、状态隔离和报告。 |
| Direct App -> CLI | `desktop_cli_peer_smoke_test.dart` | App 发送 runId 文本，CLI history 轮询确认。 | 真实 Desktop App + CLI peer E2E。 | Step 05 增加报告、去重和失败诊断。 |
| Direct CLI -> App | `desktop_cli_peer_smoke_test.dart` | CLI 发送 runId 文本，App `MessagingService.loadHistory` 轮询确认。 | 真实 Desktop App + CLI peer E2E。 | Step 05 增加会话刷新、history/inbox 回归。 |
| 会话 history / inbox / 去重 | `desktop_cli_peer_smoke_test.dart`；`tests/unit_test/conversation_workspace_test.dart` | history 基础轮询；fake UI 下覆盖会话工作区相邻行为。 | 部分覆盖。 | Step 05 补真实去重、刷新和既有会话不破坏断言。 |
| 群组创建 / 加入 / 成员 | `tests/unit_test/group_flow_test.dart`；`tests/unit_test/conversation_workspace_test.dart` | fake gateway 下覆盖创建群、Group DID 加入、群详情、成员列表和添加成员失败。 | Unit/widget fake 覆盖。 | Step 06 补真实两人群和群内双向文本。 |
| 群组消息互通 | 当前无独立真实 E2E。 | 尚未覆盖 App/peer 群内双向消息。 | 缺口。 | Step 06 设计 `GROUP-E2E-002`，必要时记录 CLI/SDK blocker。 |
| 附件发送 / 接收 | `lib/src/application/models/attachment_models.dart` 有模型；`tests/e2e_test/scenarios/agent_im_delegated_message/app_bootstrap_scenario.dart` 有相邻引用。 | 尚无基础附件真实 E2E。 | 缺口。 | Step 06 补小型 fixture、metadata/hash/download 状态方案。 |
| Profile / Settings | `tests/unit_test/profile_page_test.dart`；`tests/unit_test/settings_page_test.dart`；`tests/unit_test/profile_provider_test.dart` | fake-backed 覆盖 profile 编辑/展示、settings 语言/凭证/更新入口等。 | Unit/widget fake 覆盖。 | Step 04 判断是否补 no-backend integration smoke。 |
| Mobile 两设备消息 | `tests/e2e_test/harness/mobile_e2e_runner.dart`；`tests/e2e_test/mobile/maestro/*.yaml`；`tests/e2e_test/configs/mobile.example.yaml` | Runner 支持 dry-run、两设备登录和 A->B / B->A 消息 flow。 | dry-run 已有；real run 依赖设备池和后端。 | Step 07 补 real run 策略、报告和 blocker 处理。 |
| Agent 作为 IM App 处理者 | `tests/e2e_test/scenarios/agent_im_delegated_message/`；`integration_test/agent_im_delegated_message_e2e_test.dart` | 已有独立 Agent IM 框架和历史证据。 | 本轮 skipped。 | 保留 `AGENT-SKIP-001`，不实现、不运行、不进 gate。 |
| 端到端加密 | 相关验证应在 `awiki-system-test` 或 SDK/服务测试中另行规划。 | 本轮不盘点细节。 | 本轮 skipped。 | 保留 `E2EE-SKIP-001`，后续单独方案处理。 |

## 5. 路径

| 仓库 / 模块 / 文件 | 计划变更 | 备注 |
|---|---|---|
| `test-awiki-me/docs/e2e/awiki-me-e2e-regression-plan/plan.md` | 回填基线盘点结论 | 文档变更 |
| `test-awiki-me/docs/testing.md` | 如发现入口说明漂移，后续步骤再更新 | 本步骤只记录 |
| `test-awiki-me/tests/e2e_test/` | 只读盘点 | 不修改实现 |
| `test-awiki-me/tests/integration_test/` | 只读盘点 | 不修改实现 |
| `test-awiki-me/integration_test/` | 只读 shim 入口 | 不移动实现 |

## 6. 依赖

- 前置步骤：无。
- 外部文档或决策：主 Plan 第 3 节当前基线。
- 环境前提：只需要本地仓库可读。

## 7. 验收标准

- [x] 覆盖地图列出当前已有测试入口和缺口。
- [x] 明确哪些测试能进入 PR required，哪些只能进入 nightly/manual/release。
- [x] 没有把 dry-run 或 skipped smoke 误记为真实 E2E 已通过。
- [x] Review 发现已经修复或明确记录。
- [x] 本步骤在进入下一步之前已经创建聚焦 commit。

## 8. 验证方式

| 检查项 | 命令 / 方法 | 预期证据 |
|---|---|---|
| Docs | `cd test-awiki-me && find docs/e2e/awiki-me-e2e-regression-plan -type f -name '*.md' -print` | 文档存在，路径可读。 |
| Diff | `cd test-awiki-me && git diff --check` | 无 Markdown 空白错误。 |
| Secret | 人工检查本步骤文档 | 未写入 OTP 值、JWT、私钥、本机绝对路径。 |

如果某个命令不能运行，必须记录原因、影响和替代证据。

## 9. Review 环节

- Review 时机：覆盖地图完成后、commit 前。
- Review 重点：当前事实是否准确，是否把测试入口分类清楚，是否夸大真实 E2E 覆盖，是否遗漏 Linux/macOS/mobile/group/attachment 基础场景。
- Review 结论必须在 commit 前记录；必须修复必要问题，或明确记录剩余风险。

| Review 项 | 结果 | 备注 |
|---|---|---|
| 发现问题 | 无阻塞问题 | 发现当前基础群组/附件真实 E2E 仍是缺口，已记录给 Step 06；Agent 与 E2EE 已标 skipped。 |
| 已修复问题 | 已修正文档范围 | 覆盖地图明确区分 unit/widget、integration smoke、dry-run、真实 E2E 和 skipped。 |
| 剩余风险 | 群组/附件 CLI/SDK 能力待确认 | Step 06 需要验证 CLI/SDK 是否已有高层 group/attachment 命令。 |
| 新增或缺失测试 | 本步骤不新增测试 | 缺失项已作为后续步骤输入。 |
| 已更新或缺失文档 | 已更新主 Plan 和 Step 01 | 后续 Step 02 继续细化标签/gate。 |

## 10. Commit 要求

- Commit 时机：本步骤文档更新、验证、Review 都完成后。
- Commit 范围：只包含本步骤覆盖地图和直接相关文档。
- Commit 前状态：记录 `git status --short --branch`。
- 纳入文件：`test-awiki-me/docs/e2e/awiki-me-e2e-regression-plan/plan.md`、`test-awiki-me/docs/e2e/awiki-me-e2e-regression-plan/steps/*.md`。
- Commit 后证据：本步骤提交后用 `git log -1` 确认，工作区仅允许保留用户/既有未跟踪目录。
- 建议消息：`docs: inventory awiki me e2e baseline`

## 11. Blocked 处理

| Blocker | 证据 | 已尝试方案 | 影响范围 | 下一步决策 |
|---|---|---|---|---|
| 找不到某个权威入口 | 待记录 | 使用 `rg --files` 和现有 docs 交叉确认 | 当前步骤 | 记录未知项，不阻塞后续矩阵设计 |

## 12. Plan 变更记录

| 日期 | 变更 | 原因 | 主 Plan 变更记录链接 |
|---|---|---|---|
| 待记录 | 待记录 | 待记录 | [../plan.md#17-plan-变更记录](../plan.md#17-plan-变更记录) |

## 13. 风险、回滚与后续文档

- 风险：当前文档和实际代码可能有漂移。
- 回滚 / 回退：回滚本步骤文档 commit，不影响代码。
- 后续文档：Step 02 使用本步骤覆盖地图制定场景矩阵和标签。
