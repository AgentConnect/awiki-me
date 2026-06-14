# Step 03：App 发送、接收和高亮展示

主 Plan：[../plan.md](../plan.md)
Step index：03
状态：draft

## 1. 执行状态

| 字段 | 值 |
|---|---|
| Status | pending |
| Branch | 待定 |
| Started | 待执行 |
| Completed | 待执行 |
| Commit | 待记录 |
| Review evidence | 待记录 |
| Verification evidence | 待记录 |
| Next action | 实现 P9 mention payload 的 App 发送、接收投影和高亮展示 |

状态取值：`pending`、`in_progress`、`review`、`blocked`、`committed`、`done`。

## 2. 目标

- 结果：带 mention 的群消息以 P9 JSON payload 发送；接收后正常显示文本并高亮被 mention 部分。
- 用户 / 系统可见行为：用户看到消息中的 `@xxx` 使用明显不同颜色；普通文本 / Markdown 消息不回归。
- 非目标：不实现富文本编辑器；不支持 attachment caption mention；不把 invalid mention 触发通知或 agent。
- 完成标准：
  - `ChatMessage` 能携带 typed `mentions`。
  - mapper 能从 `payloadJson` 投影 `content` 和 `mentions`。
  - `_MessageTextContent` 支持 mention span。
  - 无 mentions 时继续走旧 `sendText`。

## 3. 设计方法

- 设计边界：App 发送分支构造 P9 payload，但不拼外层 wire；SDK 负责最终 ANP send。
- 核心决策：mention payload 按纯文本渲染，不走 MarkdownBody，避免 P9 range 与 Markdown AST 冲突。
- 契约 / API / 数据流：
  - `ChatComposerDraft` → `MessagingService.sendMentionText` → SDK payload send。
  - SDK `MessageBodyView.payloadJson` → App P9 parser → `ChatMessage.content + mentions` → RichText spans。
- 兼容性：原有 `payloadJson` 保留；control payload 继续被 `isAgentControlPayload` 过滤。
- 迁移策略：新增 optional fields，避免破坏现有测试。
- 风险控制：invalid mentions 忽略高亮；文本仍可显示。

## 4. 实现方法

1. 扩展 `ChatMessage`：新增 `mentions`、`isMentionPayload` / `hasValidMentions` 等只读 helper。
2. 扩展 `MessagingService` / `MessageCorePort`：新增 `sendMentionText` 或 `sendPayload` wrapper，群聊 mention 发送走 payload。
3. 修改 `ChatThreadsController.sendMessage`：当 draft mentions 非空时调用 mention 发送；pending message 先本地带 mentions 显示高亮。
4. 修改 `AwikiImCoreMappers.chatMessageFromCore`：
   - 对 `message.body.payloadJson` 解析 P9 payload；
   - 合法时 `content = payload.text`，`mentions = parsedMentions`；
   - control payload 继续隐藏。
5. 修改 `_MessageTextContent`：增加 mentions 参数，合法 mentions 时用 `TextSpan` 切片并高亮。
6. 预览与无障碍：conversation preview 使用 `payload.text`；semantics label 使用纯文本。

## 5. 路径

| 仓库 / 模块 / 文件 | 计划变更 | 备注 |
|---|---|---|
| `awiki-me/lib/src/domain/entities/chat_message.dart` | 新增 mentions 字段与 helper | 保持构造兼容。 |
| `awiki-me/lib/src/application/messaging_service.dart` | 新增 mention 发送方法 | 或复用 sendPayload wrapper。 |
| `awiki-me/lib/src/application/ports/message_core_port.dart` | 暴露 mention 发送接口 | 与 SDK adapter 对齐。 |
| `awiki-me/lib/src/data/im_core/awiki_im_core_message_adapter.dart` | 调用 SDK mention / payload API | 不直接拼外层 ANP wire。 |
| `awiki-me/lib/src/data/im_core/awiki_im_core_mappers.dart` | payloadJson → ChatMessage projection | 控制 payload 仍隐藏。 |
| `awiki-me/lib/src/presentation/chat/chat_provider.dart` | 发送分支、pending message、retry 策略 | retry 需保留 original payload。 |
| `awiki-me/lib/src/presentation/chat/chat_page.dart` | mention span 高亮 | 普通 Markdown 保持。 |
| `awiki-me/tests/unit_test/` | mapper / widget / provider tests | 覆盖合法和非法 P9。 |

## 6. 依赖

- 前置步骤：Step 01 SDK payload 兼容；Step 02 draft mentions。
- 外部文档或决策：P9 终端侧校验规则。
- 环境前提：Flutter test 环境可用。

## 7. 验收标准

- [ ] 群聊 mention 消息发送 payload 包含 `text` 和 `mentions`，无 mention sender/proof。
- [ ] 收到合法 P9 payload 时 App 显示 `payload.text`，并按 range 高亮 mention surface。
- [ ] 无效 range / target 的 mention 不高亮、不触发，但文本仍显示。
- [ ] 普通 Markdown、普通文本、附件展示不回归。
- [ ] Conversation preview 使用人类可读文本。
- [ ] Review 发现已经修复或明确记录。
- [ ] 本步骤在进入下一步之前已经创建聚焦 commit。

## 8. 验证方式

| 检查项 | 命令 / 方法 | 预期证据 |
|---|---|---|
| Mapper unit | `cd awiki-me && flutter test tests/unit_test --name "mention payload"` | payload projection 测试通过。 |
| Widget | `cd awiki-me && flutter test tests/unit_test --name "mention highlight"` | mention span 高亮测试通过。 |
| Provider | `cd awiki-me && flutter test tests/unit_test --name "send mention"` | 有 mentions 时走 payload，无 mentions 走 sendText。 |
| Analyze | `cd awiki-me && dart analyze` | 无静态分析问题。 |
| Manual | 群聊发送 `@所有 Agents` 与 `@单个成员` | UI 显示、高亮、preview 正常。 |

如果某个命令不能运行，必须记录原因、影响和替代证据。

## 9. Review 环节

- Review 时机：本步骤代码实现完成后、commit 前。
- Review 重点：P9 payload shape、range 高亮、Markdown 兼容、retry 是否丢失 mention、control payload 是否仍隐藏、安全字段禁止。
- Review 结论必须在 commit 前记录；必须修复必要问题，或明确记录剩余风险。

| Review 项 | 结果 | 备注 |
|---|---|---|
| 发现问题 | 待执行 |  |
| 已修复问题 | 待执行 |  |
| 剩余风险 | 待执行 |  |
| 新增或缺失测试 | 待执行 |  |
| 已更新或缺失文档 | 待执行 |  |

## 10. Commit 要求

- Commit 时机：本步骤实现、验证、Review 都完成后。
- Commit 范围：App sending / mapper / render / tests / docs。
- Commit 前状态：记录 `git status`。
- 纳入文件：记录本步骤 commit 包含的文件。
- Commit 后证据：记录 commit hash 和 commit 后 `git status`。
- 建议消息：`feat(app): send and render group mentions`

## 11. Blocked 处理

| Blocker | 证据 | 已尝试方案 | 影响范围 | 下一步决策 |
|---|---|---|---|---|
| SDK payload API 未完成 | App adapter 编译失败 | 先用 fake port 测 UI / mapper | 真实发送 | 等 Step 01。 |
| Selectable RichText 难以兼容 | Widget test 失败 | 先用 RichText，保留 SelectionArea 外层 | 高亮体验 | 记录选择复制限制或改用 SelectableText.rich。 |

## 12. Plan 变更记录

| 日期 | 变更 | 原因 | 主 Plan 变更记录链接 |
|---|---|---|---|
| 2026-06-14 | 创建 Step 03 | 初始设计 | `../plan.md#16-plan-变更记录` |

## 13. 风险、回滚与后续文档

- 风险：payload message 被 `hasRenderableContent` 过滤导致聊天中不可见；mapper tests 必须覆盖。
- 回滚 / 回退：关闭 mention 发送，只把收到的 P9 payload 当普通文本显示。
- 后续文档：更新 `awiki-me/docs/testing.md` 的聊天 UI 测试 gate。
