# Step 02：E2E harness 基础扩展

主 Plan：[../plan.md](../plan.md)  
Step index：02  
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
| Next action | 等待 Step 01 完成后扩展 desktop E2E runner |

## 2. 目标

- 结果：让 `awiki-me` 的桌面 E2E runner 具备 Agent IM scenario、config、report、redaction 和 remote adapter 的基础能力。
- 用户 / 系统可见行为：执行者可以通过 dry-run 看到完整 Agent IM E2E 编排计划，但不会在 dry-run 中写远端状态或泄漏敏感信息。
- 非目标：本步骤不实现完整业务场景，不要求真实 App/CLI/Daemon 消息闭环通过。
- 完成标准：新增 config example、scenario registry、redaction/report 基础单元测试；macOS dry-run 可运行并生成脱敏 report。

## 3. 设计方法

- 设计边界：复用 `awiki-me/tests/e2e_test/harness/desktop_e2e_runner.dart`；共用逻辑抽入 `harness/src/`，不要复制一套 Linux runner。
- 核心决策：新增 `--scenario=agent-im-delegated-message` 和 `--config=...`，默认 smoke 行为保持兼容。
- 契约 / API / 数据流：harness 只编排，不解析私钥包，不直接实现 message-service wire；具体 IM 操作交给 App 或 CLI peer。
- 兼容性：旧 `tool/macos_e2e_runner.dart` wrapper 和无 scenario 的 smoke 行为不应失效。
- 迁移策略：本步骤可逐步拆出 `DesktopE2eConfig`、`DesktopCommandRunner` 等公共类，但避免大重写。
- 风险控制：local config、report、workspace 继续位于 `.e2e/`，不纳入 Git；redactor 对日志和 JSON report 都生效。

## 4. 实现方法

1. 设计并新增 `tests/e2e_test/configs/agent_im_delegated.example.yaml`，只包含占位和环境变量名。
2. 在 desktop runner 增加 `--scenario`、`--config` 解析；无参数时保持原 smoke 流程。
3. 新增或拆分 `harness/src/`：
   - scenario registry / scenario interface；
   - config loader；
   - report writer；
   - secret redactor；
   - remote adapter dry-run command planner。
4. 为 config parser、scenario planner、redactor 写 `tests/unit_test/e2e_harness/` 单元测试。
5. 更新 `awiki-me/docs/testing.md` 或 `tests/e2e_test/README.md`，记录 Agent IM scenario 的 dry-run 命令。

## 5. 路径

| 仓库 / 模块 / 文件 | 计划变更 | 备注 |
|---|---|---|
| `awiki-me/tests/e2e_test/harness/desktop_e2e_runner.dart` | 增加 scenario/config 参数并保持兼容 | 尽量薄化入口 |
| `awiki-me/tests/e2e_test/harness/src/` | 新增共享 harness 模块 | 当前目录只有 README，可新增 Dart 文件 |
| `awiki-me/tests/e2e_test/configs/agent_im_delegated.example.yaml` | 新增 example config | 不提交 local config |
| `awiki-me/tests/unit_test/e2e_harness/` | 新增 parser/planner/redactor 单元测试 | 不依赖真实后端 |
| `awiki-me/tests/e2e_test/README.md` | 更新 runner 用法 | docs sync |
| `awiki-me/docs/testing.md` | 必要时更新测试说明 | 保持已有结构 |

## 6. 依赖

- 前置步骤：Step 01 完成并确认扩展点。
- 外部文档或决策：`awiki-me/docs/awiki-me-test-framework-plan.md`。
- 环境前提：Dart/Flutter 工具可用；dry-run 不要求远端。

## 7. 验收标准

- [ ] `desktop_e2e_runner.dart --help` 包含 Agent IM scenario/config 说明。
- [ ] 无 scenario 参数时原有 smoke/dry-run 行为保持兼容。
- [ ] `agent_im_delegated.example.yaml` 不含真实手机号、OTP、token、私钥。
- [ ] redactor 单元测试覆盖 token/JWT/private package/OTP/手机号。
- [ ] macOS dry-run 能生成 report/timings，且 report 中无敏感值。
- [ ] Review 发现已经修复或明确记录。
- [ ] 本步骤在进入下一步之前已经创建聚焦 commit。

## 8. 验证方式

| 检查项 | 命令 / 方法 | 预期证据 |
|---|---|---|
| Analyze | `cd awiki-me && dart analyze` | 无新增 analyze 错误。 |
| Unit | `cd awiki-me && flutter test tests/unit_test/e2e_harness` | parser/planner/redactor 测试通过。 |
| Full unit gate | `cd awiki-me && flutter test tests/unit_test` | 既有单元测试不回归。 |
| Dry-run | `cd awiki-me && dart run tests/e2e_test/harness/desktop_e2e_runner.dart --platform=macos --scenario=agent-im-delegated-message --config tests/e2e_test/configs/agent_im_delegated.example.yaml --dry-run` | 输出 planned commands，生成 `.e2e/macos/reports/<runId>/timings.json`。 |
| 兼容 dry-run | `cd awiki-me && dart run tests/e2e_test/harness/desktop_e2e_runner.dart --platform=macos --dry-run` | 原 smoke dry-run 不失效。 |

## 9. Review 环节

- Review 时机：代码和测试完成后、commit 前。
- Review 重点：runner 兼容性、跨平台抽象边界、secret redaction、local config 不入库、是否把业务逻辑塞入 harness。

| Review 项 | 结果 | 备注 |
|---|---|---|
| 发现问题 | 待填写 |  |
| 已修复问题 | 待填写 |  |
| 剩余风险 | 待填写 |  |
| 新增或缺失测试 | 待填写 |  |
| 已更新或缺失文档 | 待填写 |  |

## 10. Commit 要求

- Commit 时机：实现、验证、Review 完成后。
- Commit 范围：只包含 harness foundation、example config、单元测试和相关 docs。
- Commit 前状态：记录 `git status`。
- 纳入文件：记录本步骤 commit 包含的文件。
- Commit 后证据：记录 commit hash 和 commit 后 `git status`。
- 遗留未提交变更：必须记录原因以及为什么安全。
- 建议消息：`test: add agent im e2e harness foundation`

## 11. Blocked 处理

| Blocker | 证据 | 已尝试方案 | 影响范围 | 下一步决策 |
|---|---|---|---|---|
| 现有 runner 结构不适合小改 | 待填写 | 先抽最小 config/redactor，不做大重构 | 当前步骤 | 更新 Plan，拆分 runner refactor step |
| dry-run 仍需真实二进制 | 待填写 | mock command planner 只打印，不检查文件 | 当前步骤 | 修复 dry-run 语义 |

## 12. Plan 变更记录

| 日期 | 变更 | 原因 | 主 Plan 变更记录链接 |
|---|---|---|---|
| 2026-06-13 | 创建 Step 02 小 Plan | 初始计划拆分 | [../plan.md#15-plan-变更记录](../plan.md#15-plan-变更记录) |

## 13. 风险、回滚与后续文档

- 风险：harness 抽象过早扩大导致难 Review。
- 回滚 / 回退：回滚本步骤 commit，恢复原 desktop runner；后续重新以更小 patch 实现。
- 后续文档：如果新增 runner 参数，必须同步 `awiki-me/docs/testing.md` 和 `tests/e2e_test/README.md`。
