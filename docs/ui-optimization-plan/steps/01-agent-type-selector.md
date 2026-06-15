# Step 01：Agent 类型选择（Hermes only）

主 Plan：[../plan.md](../plan.md)
Step index：01
状态：done

## 1. 执行状态

| 字段 | 值 |
|---|---|
| Status | done |
| Branch | `awiki-me-ui:feature/release-0526/ui-optimization` |
| Started | 2026-06-14 |
| Completed | 2026-06-15 |
| Commit | 用户已要求统一提交、推送并合并到 `release/0526`；不再按 Step 拆分提交 |
| Review evidence | Review 确认只新增 Hermes 类型选择与提示，不引入第二种 runtime，不改变 `createHermesRuntime` 调用语义 |
| Verification evidence | `flutter analyze ...`；`flutter test tests/unit_test/agents/agents_page_layout_test.dart` 已通过 |
| Next action | 无 |

## 2. 目标

- 结果：创建 Runtime Agent / 安装宿主代理流程明确展示 Agent 类型。
- 用户 / 系统可见行为：创建对话框中出现“Agent 类型”，当前只可选 Hermes；宿主安装命令对话框提示“支持的 Agent 类型：Hermes”。
- 非目标：不新增 Hermes 以外的 runtime，不改 Daemon / SDK 协议。
- 完成标准：用户能看到 Hermes 类型选择，提交仍走原 Hermes 创建链路，测试覆盖文案和创建参数。

## 3. 设计方法

- 设计边界：只改 `awiki-me-ui` 的 Agent 管理 UI 与测试。
- 核心决策：使用只读/单选式 Hermes 卡片，避免暗示已有多类型 runtime。
- 契约 / API / 数据流：`_RuntimeAgentCreationDraft.agentType` 只允许 Hermes；提交前校验非 Hermes 时拒绝。
- 兼容性：保持既有 `createHermesRuntime` payload 和 provider 行为。
- 风险控制：文案明确“当前仅支持 Hermes Runtime Agent”。

## 4. 实现方法

1. 在 `agents_page.dart` 的创建 Hermes 对话框加入类型卡片。
2. 在安装命令对话框增加 Hermes 支持提示。
3. 更新 Agent 页面 widget test，覆盖类型文案和提交参数不变。

## 5. 路径

| 仓库 / 模块 / 文件 | 计划变更 | 备注 |
|---|---|---|
| `awiki-me-ui/lib/src/presentation/agents/agents_page.dart` | 新增类型选择 UI 与 Hermes-only 校验 | UI 层 |
| `awiki-me-ui/tests/unit_test/agents/agents_page_layout_test.dart` | 覆盖文案 / 提交流程 | Widget test |

## 6. 依赖

- 前置步骤：无。
- 外部文档或决策：用户明确“当前只支持 Hermes”。
- 环境前提：Flutter 测试环境。

## 7. 验收标准

- [x] 创建 Runtime Agent 对话框展示“Agent 类型”。
- [x] 仅 Hermes 可用。
- [x] 安装命令对话框提示 Hermes 支持范围。
- [x] Review 发现已经修复或明确记录。
- [x] 本步骤纳入统一集成提交；用户已要求推送并合并到 `release/0526`。

## 8. 验证方式

| 检查项 | 命令 / 方法 | 预期证据 |
|---|---|---|
| Unit / Widget | `cd awiki-me-ui && flutter test tests/unit_test/agents/agents_page_layout_test.dart` | 相关 Agent 页面测试通过 |
| Analyze | `cd awiki-me-ui && flutter analyze ... agents_page.dart ... agents_page_layout_test.dart` | No issues found |
| Docs | 检查 `docs/ui-optimization-plan/plan.md` | 台账记录完成 |

## 9. Review 环节

- Review 时机：实现完成后、验证前后各一次。
- Review 重点：Hermes-only 约束、误导性多类型入口、创建参数回归。

| Review 项 | 结果 | 备注 |
|---|---|---|
| 发现问题 | 无阻断 | 仅需保持 Hermes-only 文案清晰 |
| 已修复问题 | 非 Hermes 分支补错误提示 | 避免未来扩展时静默提交 |
| 剩余风险 | 无 | 后续新增类型时再扩展 UI |
| 新增或缺失测试 | 已更新 `agents_page_layout_test.dart` | 覆盖文案 |
| 已更新或缺失文档 | 已更新主 Plan / `docs/testing.md` | 无缺失 |

## 10. Commit 要求

- Commit 时机：用户已确认，纳入统一集成提交。
- Commit 范围：Agent 类型 UI、测试与相关文档。
- 建议消息：`feat(app): add Hermes agent type selector`

## 11. Blocked 处理

| Blocker | 证据 | 已尝试方案 | 影响范围 | 下一步决策 |
|---|---|---|---|---|
| 无 | - | - | - | - |

## 12. Plan 变更记录

| 日期 | 变更 | 原因 | 主 Plan 变更记录链接 |
|---|---|---|---|
| 2026-06-15 | 回填 Step 文档与证据 | 恢复执行时补齐 awiki-plan 小 Plan | `../plan.md#15-plan-变更记录` |

## 13. 风险、回滚与后续文档

- 风险：未来新增 Agent 类型时需要避免硬编码散落。
- 回滚 / 回退：移除类型卡片和文案，保留原创建 Hermes 流程。
- 后续文档：新增 runtime 类型时更新本 Plan 与用户文档。
