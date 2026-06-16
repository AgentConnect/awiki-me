# Step 03：Agent 收件箱增强

主 Plan：[../plan.md](../plan.md)
Step index：03
状态：done

## 1. 执行状态

| 字段 | 值 |
|---|---|
| Status | done |
| Branch | `awiki-me-ui:feature/release-0526/ui-optimization` |
| Started | 2026-06-14 |
| Completed | 2026-06-15 |
| Commit | 用户已要求统一提交、推送并合并到 `release/0526`；不再按 Step 拆分提交 |
| Review evidence | Review 确认 list/thread 默认 limit=20，cursor load more 保留，列表最新优先，线程消息按时间顺序 |
| Verification evidence | `flutter test tests/unit/agents/agent_inbox_provider_test.dart` 已通过；整体 focused unit 151 passed |
| Next action | 无 |

## 2. 目标

- 结果：Agent 收件箱可读性和分页能力增强。
- 用户 / 系统可见行为：列表展示时间和“最新：”预览；线程消息展示发送时间；默认只拉 20 条，可继续加载旧会话 / 旧消息。
- 非目标：不改 Daemon control payload schema。
- 完成标准：limit、cursor、排序、去重、时间展示、SelectionArea 均有测试或静态证据。

## 3. 设计方法

- 设计边界：只改 App provider / panel / service 默认值。
- 核心决策：统一 `agentInboxPageSize = 20`，所有 list/thread query 与 load more 共用。
- 契约 / API / 数据流：沿用 `runtime_inbox` 与 `runtime_inbox_thread` status payload，使用 `next_cursor` 翻页。
- 兼容性：若旧 daemon 不返回时间则隐藏时间标签，预览 fallback 为“最新：无预览 / 附件”。
- 风险控制：合并重复 item 后重新按 `lastMessageAtMs` 排序，线程 prepend 后按 `sentAtMs` 排序。

## 4. 实现方法

1. 在 `agent_inbox_provider.dart` 增加 page size 常量并修改 query/loadMore 默认 limit。
2. 实现列表和线程消息排序、去重与分页合并。
3. 在 `agent_inbox_panel.dart` 展示时间、最新预览和 load more 按钮。
4. 用 `SelectionArea` 包裹收件箱 shell，支持文字选择复制。
5. 更新 fake service 与 provider tests。

## 5. 路径

| 仓库 / 模块 / 文件 | 计划变更 | 备注 |
|---|---|---|
| `awiki-me-ui/lib/src/presentation/agents/agent_inbox_provider.dart` | limit=20、排序、分页合并 | Provider |
| `awiki-me-ui/lib/src/presentation/agents/agent_inbox_panel.dart` | 时间、预览、SelectionArea | UI |
| `awiki-me-ui/lib/src/domain/entities/agent/agent_command.dart` | 默认 limit=20 | Domain command |
| `awiki-me-ui/lib/src/application/agent/agent_control_service.dart` | service 默认 limit=20 | Application service |
| `awiki-me-ui/tests/unit/agents/agent_inbox_provider_test.dart` | limit / 排序 / 分页测试 | Unit |
| `awiki-me-ui/tests/unit/test_support.dart` | fake 记录 limit / cursor | Test support |

## 6. 依赖

- 前置步骤：Step 02 弹窗嵌入入口。
- 外部文档或决策：用户要求默认 20 条与分页。
- 环境前提：Fake control payload 测试环境。

## 7. 验收标准

- [x] 默认 list/thread limit 为 20。
- [x] load more 使用 cursor 继续请求旧数据。
- [x] 列表按最新消息时间降序。
- [x] 线程消息按发送时间升序，旧消息 prepend 后不乱序。
- [x] 列表和线程展示时间。
- [x] Agent 收件箱文字可选择复制。
- [x] Review 发现已经修复或明确记录。
- [x] 本步骤纳入统一集成提交；用户已要求推送并合并到 `release/0526`。

## 8. 验证方式

| 检查项 | 命令 / 方法 | 预期证据 |
|---|---|---|
| Provider | `cd awiki-me-ui && flutter test tests/unit/agents/agent_inbox_provider_test.dart` | limit、排序、分页测试通过 |
| Widget / UI | `cd awiki-me-ui && flutter test tests/unit/conversation_workspace_test.dart` | Agent 收件箱入口回归通过 |
| Analyze | `cd awiki-me-ui && flutter analyze ... agent_inbox_provider.dart agent_inbox_panel.dart ...` | No issues found |

## 9. Review 环节

| Review 项 | 结果 | 备注 |
|---|---|---|
| 发现问题 | `_sortItemsByLatest` 初版固定长度列表导致合并失败 | 已改为 growable list |
| 已修复问题 | list/thread limit 和 cursor fake 记录补齐 | 已补测试 |
| 剩余风险 | 真实 Daemon 返回缺失时间时只显示无时间标签 | 兼容策略可接受 |
| 新增或缺失测试 | 已新增分页 / 排序测试 | 无缺失 |
| 已更新或缺失文档 | 已更新 `docs/testing.md` | 无缺失 |

## 10. Commit 要求

- Commit 时机：用户已确认，纳入统一集成提交。
- Commit 范围：Agent 收件箱 provider / panel / tests。
- 建议消息：`feat(app): improve agent inbox pagination`

## 11. Blocked 处理

| Blocker | 证据 | 已尝试方案 | 影响范围 | 下一步决策 |
|---|---|---|---|---|
| 无 | - | - | - | - |

## 12. Plan 变更记录

| 日期 | 变更 | 原因 | 主 Plan 变更记录链接 |
|---|---|---|---|
| 2026-06-15 | 回填实现证据 | 恢复执行后完成审计 | `../plan.md#15-plan-变更记录` |

## 13. 风险、回滚与后续文档

- 风险：Daemon page size 若另有上限，App 的 20 只作为请求值。
- 回滚 / 回退：恢复旧 limit 与旧 UI，不影响消息发送。
- 后续文档：Daemon inbox schema 若演进需同步 API 文档。
