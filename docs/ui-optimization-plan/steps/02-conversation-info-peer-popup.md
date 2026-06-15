# Step 02：会话信息默认关闭与用户 / 智能体信息弹窗

主 Plan：[../plan.md](../plan.md)
Step index：02
状态：done

## 1. 执行状态

| 字段 | 值 |
|---|---|
| Status | done |
| Branch | `awiki-me-ui:feature/release-0526/ui-optimization` |
| Started | 2026-06-14 |
| Completed | 2026-06-15 |
| Commit | 用户已要求统一提交、推送并合并到 `release/0526`；不再按 Step 拆分提交 |
| Review evidence | Review 确认直聊默认不打开右侧信息栏，用户 / Agent 资料进入弹窗；群聊信息仍走原群详情侧栏 |
| Verification evidence | `flutter test tests/unit_test/conversation_workspace_test.dart tests/unit_test/chat_page_test.dart`；`flutter test integration_test/app_smoke_test.dart -d macos` 已通过 |
| Next action | 无 |

## 2. 目标

- 结果：消息页面会话信息默认关闭，点击用户 / 智能体头像或身份卡入口打开资料弹窗。
- 用户 / 系统可见行为：直聊头部的身份卡、关注、Agent 收件箱能力迁移到“用户信息 / 智能体信息”弹窗；群聊“群聊信息”仍打开群详情。
- 非目标：不改变消息收发、群详情管理权限和 profile 数据协议。
- 完成标准：默认关闭、主动打开会话信息、资料弹窗、关注和 Agent 收件箱入口均有测试覆盖。

## 3. 设计方法

- 设计边界：`ConversationWorkspacePage` 管理侧栏开关；`ChatView` 管理资料弹窗。
- 核心决策：直聊身份入口打开 `_PeerInfoDialog`；群聊身份入口继续调用群信息侧栏。
- 契约 / API / 数据流：复用 `peerProfileProvider`、`friendsProvider`、`agentsProvider` 和 `AgentInboxPanel`。
- 兼容性：保留移动端 Agent 收件箱全屏入口；macOS 直聊不再默认占用右栏。
- 风险控制：右侧栏空间不足时仍使用现有 inline panel 逻辑；资料弹窗高度受限并内部滚动。

## 4. 实现方法

1. 将 `conversation_workspace_page.dart` 中 `_isSidePanelOpen` 初始值和切换会话逻辑改为关闭。
2. 在 `chat_page.dart` 新增 `_PeerInfoDialog`，包含 DID、handle、Homepage、身份卡、关注按钮与 Runtime Agent 收件箱入口。
3. 将头像 / 身份卡按钮连接到弹窗；群聊保持群信息侧栏。
4. 更新 conversation / chat widget tests 与 integration smoke。

## 5. 路径

| 仓库 / 模块 / 文件 | 计划变更 | 备注 |
|---|---|---|
| `awiki-me-ui/lib/src/presentation/conversation_list/conversation_workspace_page.dart` | 默认关闭会话信息，主动切换侧栏 | macOS 工作区 |
| `awiki-me-ui/lib/src/presentation/chat/chat_page.dart` | 用户 / 智能体信息弹窗，入口迁移 | Chat UI |
| `awiki-me-ui/tests/unit_test/conversation_workspace_test.dart` | 默认关闭、弹窗、群信息回归 | Widget test |
| `awiki-me-ui/tests/unit_test/chat_page_test.dart` | 关注 / 头部入口回归 | Widget test |
| `awiki-me-ui/tests/integration_test/app/app_smoke_test.dart` | fake-bootstrap E2E smoke | Integration |

## 6. 依赖

- 前置步骤：无。
- 外部文档或决策：用户要求“会话信息默认关闭”和“资料弹窗迁移”。
- 环境前提：Flutter macOS / widget test。

## 7. 验收标准

- [x] 打开消息页后会话信息不默认展示。
- [x] 点击会话信息按钮后才出现会话信息。
- [x] 点击头像 / 身份卡打开用户或智能体信息弹窗。
- [x] 弹窗内包含身份卡、关注、Agent 收件箱入口。
- [x] 群聊信息入口仍打开群详情侧栏。
- [x] Review 发现已经修复或明确记录。
- [x] 本步骤纳入统一集成提交；用户已要求推送并合并到 `release/0526`。

## 8. 验证方式

| 检查项 | 命令 / 方法 | 预期证据 |
|---|---|---|
| Widget | `cd awiki-me-ui && flutter test tests/unit_test/conversation_workspace_test.dart tests/unit_test/chat_page_test.dart` | 默认关闭、弹窗、群信息回归通过 |
| Integration | `cd awiki-me-ui && LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 flutter test integration_test/app_smoke_test.dart -d macos` | fake app smoke 4 passed |
| Analyze | `cd awiki-me-ui && flutter analyze ... chat_page.dart conversation_workspace_page.dart ...` | No issues found |

## 9. Review 环节

| Review 项 | 结果 | 备注 |
|---|---|---|
| 发现问题 | 需要保留群详情侧栏行为 | 已恢复群聊 `onMacIdentityPanelTap` 路径 |
| 已修复问题 | 切换会话后会话信息仍关闭；群信息不误跳弹窗 | 已补测试 |
| 剩余风险 | 弹窗内 Markdown 与链接选择交互需后续真机观察 | 当前 widget / smoke 通过 |
| 新增或缺失测试 | 已新增 integration UI smoke | 覆盖 AppShell → 消息 → 弹窗 |
| 已更新或缺失文档 | 已更新 `docs/testing.md` | 无缺失 |

## 10. Commit 要求

- Commit 时机：用户已确认，纳入统一集成提交。
- Commit 范围：会话默认关闭、资料弹窗、相关测试与文档。
- 建议消息：`feat(app): move peer details into info dialog`

## 11. Blocked 处理

| Blocker | 证据 | 已尝试方案 | 影响范围 | 下一步决策 |
|---|---|---|---|---|
| 无 | - | - | - | - |

## 12. Plan 变更记录

| 日期 | 变更 | 原因 | 主 Plan 变更记录链接 |
|---|---|---|---|
| 2026-06-15 | 增加 integration smoke | 需要端到端入口验证 | `../plan.md#15-plan-变更记录` |

## 13. 风险、回滚与后续文档

- 风险：弹窗内容继续增长可能需要拆分 tab。
- 回滚 / 回退：恢复直聊右侧身份卡面板，保留默认关闭侧栏。
- 后续文档：若设计稿明确弹窗尺寸，再更新 UI 文档。
