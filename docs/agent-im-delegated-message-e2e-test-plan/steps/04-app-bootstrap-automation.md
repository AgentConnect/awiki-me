# Step 04：App bootstrap 自动化与 integration entry

主 Plan：[../plan.md](../plan.md)  
Step index：04  
状态：done

## 1. 执行状态

| 字段 | 值 |
|---|---|
| Status | done |
| Branch | `feature/release-0526/agent-im-hutong` |
| Started | 2026-06-13 21:21:18 +0800 |
| Completed | 2026-06-13 21:41:58 +0800 |
| Commit | `test: automate agent im app bootstrap`；短 hash 以本步骤提交后的 `git log -1` 为准 |
| Review evidence | 复用生产 `DefaultAgentControlService`；fake ports 不触发真实后端；根级 integration file 仅 shim；report 投影不包含 private package / runtime token / OTP / raw phone；system/control payload 不可渲染；真实远端 ack 与 peer message 处理留给 Step 05/06。 |
| Verification evidence | `dart analyze` No issues；`flutter test tests/unit_test` 406 passed；targeted unit 通过；Agent IM macOS integration 1 passed；native smoke 1 passed；Agent IM dry-run PASS；report sensitive scan OK；`git diff --check` OK。 |
| Next action | Step 04 已完成；进入 Step 05 前读取 Step 05 小 Plan 并重新检查相关仓库状态。 |

## 2. 目标

- 结果：E2E 能稳定触发 `awiki-me` App 向 Daemon 发送 `awiki.daemon.bootstrap.v1`，并能观测 App 对 bootstrap 状态、system/control payload 和后续 sync/action result 的处理。
- 用户 / 系统可见行为：真实 App 环境中，用户账号可以启用消息处理 Agent；bootstrap payload 不作为普通聊天内容展示。
- 非目标：不把私钥包展示到 UI，不为了测试加入生产后门，不在根级 `integration_test/` 放真实业务实现。
- 完成标准：有稳定的 integration entry 或 UI 自动化路径，macOS smoke 可触发 bootstrap dry-run/真实路径，相关 reducer/model/widget 测试覆盖隐私与可见性。

## 3. 设计方法

- 设计边界：App UI/state/cache 属于 `awiki-me`；IM core/消息发送能力通过 Dart SDK/im-core，不在 App 内拼 message-service wire。
- 核心决策：优先复用真实 UI 或现有 service；若 UI 不稳定，新增 `AWIKI_E2E=true` 下的 integration-only entrypoint，仍调用生产 service 层。
- 契约 / API / 数据流：App 构造 `awiki.daemon.bootstrap.v1`，包含 delegated public metadata 和 private package；private package 只能进入发送链路，不进入日志、普通聊天、截图或 report。
- 兼容性：根级 `integration_test/agent_im_delegated_message_e2e_test.dart` 如新增，只做 Flutter tooling shim，实际实现放在 `tests/integration_test/` 或 `tests/e2e_test/scenarios/`。
- 迁移策略：不移动现有测试框架目录；新增文件遵循 `tests/unit_test`、`tests/integration_test`、`tests/e2e_test` 并行结构。
- 风险控制：所有 App logs/report 经过 redaction；测试入口只在 E2E dart-define 或 integration test 中启用。

## 4. 实现方法

1. 检查现有 App bootstrap service、provider、action reducer 和 payload filter 是否可被测试调用。
2. 新增或扩展 App scenario hook：
   - 登录/恢复测试账号；
   - 触发 Agent bootstrap；
   - 等待 bootstrap sent/ack/status；
   - 读取 App event/state，确认 system payload hidden；
   - 等待 `awiki.message.sync.v1` 或 `awiki.app.action.result.v1`。
3. 如需要 Flutter integration plugin：
   - 在 `tests/integration_test/agent_im/` 放真实实现；
   - 在根级 `integration_test/agent_im_delegated_message_e2e_test.dart` 放 shim。
4. 增加 unit/widget tests：payload hiding、bootstrap status reducer、summary/action result 展示状态、redaction。
5. 与 Step 05 的 scenario API 对齐，输出稳定事件给 E2E harness。

## 5. 路径

| 仓库 / 模块 / 文件 | 计划变更 | 备注 |
|---|---|---|
| `awiki-me/tests/e2e_test/scenarios/agent_im_delegated_message/` | 新增 App bootstrap scenario hook | 与 Step 05 共用 |
| `awiki-me/tests/integration_test/agent_im/` | 如需要，新增 integration 实现 | 非根级实现 |
| `awiki-me/integration_test/agent_im_delegated_message_e2e_test.dart` | 如需要，新增 Flutter tooling shim | 只 import/forward |
| `awiki-me/tests/unit_test/` | 新增 App reducer/payload visibility tests | fake-backed |
| `awiki-me/lib/src/` | 如缺少测试可调用 service，则最小补齐 | 必须 Review 安全边界 |
| `awiki-me/docs/testing.md` | 如新增 shim/命令则更新 | docs sync |

## 6. 依赖

- 前置步骤：Step 02。
- 外部文档或决策：`awiki-cli-rs2/docs/agent-im/plan/steps/06-awiki-me-pairing-bootstrap-ui-service.md`、`awiki-cli-rs2/docs/agent-im/plan/steps/08-app-action-schema-and-visibility.md`。
- 环境前提：Flutter macOS target 可运行；真实账号凭证由 local config/env 提供。

## 7. 验收标准

- [x] App 能在 E2E/integration 环境触发 bootstrap。
- [x] `awiki.daemon.bootstrap.v1` 不显示为普通聊天。
- [x] private package 不进入 log、report、UI、screenshot。
- [x] App 能识别并展示 `awiki.message.sync.v1` 或 `awiki.app.action.result.v1` 的目标状态。
- [x] 根级 `integration_test/` 只有 shim，不放真实业务逻辑。
- [x] Review 发现已经修复或明确记录。
- [x] 本步骤在进入下一步之前已经创建聚焦 commit。

## 8. 验证方式

| 检查项 | 命令 / 方法 | 预期证据 |
|---|---|---|
| Unit | `cd awiki-me && flutter test tests/unit_test` | payload hiding、status reducer、redaction 测试通过。 |
| Analyze | `cd awiki-me && dart analyze` | 无新增 analyze 错误。 |
| Integration smoke | `cd awiki-me && flutter test integration_test/agent_im_delegated_message_e2e_test.dart -d macos` | 如新增 shim，该 smoke 可启动并执行 App bootstrap 路径；若未新增，记录不适用原因。 |
| Existing smoke | `cd awiki-me && flutter test integration_test/im_core_open_smoke_test.dart -d macos` | native smoke 不回归。 |
| Dry-run | `cd awiki-me && dart run tests/e2e_test/harness/desktop_e2e_runner.dart --platform=macos --scenario=agent-im-delegated-message --config tests/e2e_test/configs/agent_im_delegated.example.yaml --dry-run` | bootstrap step 出现在 planned flow。 |

## 9. Review 环节

- Review 时机：App bootstrap 自动化完成后、commit 前。
- Review 重点：私钥包生命周期、日志脱敏、system/control payload visibility、测试入口是否可被生产误触、SDK 边界。

| Review 项 | 结果 | 备注 |
|---|---|---|
| 发现问题 | 未发现阻塞问题 | App bootstrap scenario 没有修改生产 `lib/src`，通过 fake `AgentInventoryPort` / `MessagingService` 驱动生产 `DefaultAgentControlService`。 |
| 已修复问题 | 已处理 lint 与文档同步 | `dart analyze` 无新增问题；docs 补充 integration smoke、scenario hook 与根级 shim 约束。 |
| 剩余风险 | 真实远端闭环仍待 Step 05/06 | 当前 smoke 验证 App 侧 bootstrap 发送、payload hiding 和 report redaction；Daemon ack、Hermes 处理、CLI peer 真消息与 `awiki.info` 证据不在本步骤伪造。 |
| 新增或缺失测试 | 新增 unit + macOS integration smoke；无本步骤阻塞缺失 | `tests/unit_test/e2e_scenarios/agent_im_app_bootstrap_scenario_test.dart`、`tests/integration_test/agent_im/agent_im_delegated_message_e2e_test.dart`、根级 shim。 |
| 已更新或缺失文档 | 已更新 | `docs/testing.md`、`tests/e2e_test/README.md`、`tests/e2e_test/scenarios/README.md`、`tests/integration_test/README.md` 已同步。 |

## 10. Commit 要求

- Commit 时机：实现、验证、Review 完成后。
- Commit 范围：App bootstrap automation、测试和 docs；不混入 CLI/server 改动。
- Commit 前状态：记录 `git status`。
- 纳入文件：记录本步骤 commit 包含的文件。
- Commit 后证据：记录 commit hash 和 commit 后 `git status`。
- 遗留未提交变更：必须记录原因以及为什么安全。
- 建议消息：`test: automate agent im app bootstrap`
- Commit 前状态：`awiki-me` 仅包含本步骤 App bootstrap scenario、integration shim、unit/integration test 与 docs/plan 变更；`awiki-cli-rs2`、`message-service` 存在既有用户未提交变更，本步骤未修改。
- 纳入文件：`docs/agent-im-delegated-message-e2e-test-plan/plan.md`、本 Step 文档、`docs/testing.md`、`integration_test/agent_im_delegated_message_e2e_test.dart`、`tests/e2e_test/README.md`、`tests/e2e_test/harness/src/scenario_registry.dart`、`tests/e2e_test/scenarios/README.md`、`tests/e2e_test/scenarios/agent_im_delegated_message/app_bootstrap_scenario.dart`、`tests/integration_test/README.md`、`tests/integration_test/agent_im/agent_im_delegated_message_e2e_test.dart`、`tests/unit_test/e2e_scenarios/agent_im_app_bootstrap_scenario_test.dart`。
- Commit 后证据：提交后执行 `git log -1 --oneline` 与 `git status --short --branch` 记录；预期 `awiki-me` 只剩 ahead 状态，无本步骤未提交文件。

## 11. Blocked 处理

| Blocker | 证据 | 已尝试方案 | 影响范围 | 下一步决策 |
|---|---|---|---|---|
| App 登录自动化不稳定 | 待填写 | 使用 integration entry 或预置测试账号状态 | 当前步骤 | 更新 Plan 后补测试入口 |
| bootstrap service 缺少可观测状态 | 待填写 | 增加 domain event / test-only observer | 当前步骤 | Review 隐私后实现 |
| private package 出现在日志 | 待填写 | 增加 redaction 和日志降级 | 当前步骤 / 安全 gate | 阻塞，必须修复 |

## 12. Plan 变更记录

| 日期 | 变更 | 原因 | 主 Plan 变更记录链接 |
|---|---|---|---|
| 2026-06-13 | 创建 Step 04 小 Plan | 初始计划拆分 | [../plan.md#15-plan-变更记录](../plan.md#15-plan-变更记录) |

## 13. 风险、回滚与后续文档

- 风险：测试入口误成为生产后门或日志泄漏 private package。
- 回滚 / 回退：回滚 App automation commit，保留 Step 02/03 dry-run；重新设计安全测试入口。
- 后续文档：新增 integration shim 或测试命令时同步 `awiki-me/docs/testing.md`。
