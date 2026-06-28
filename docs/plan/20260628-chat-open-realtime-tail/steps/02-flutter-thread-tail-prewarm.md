# Step 02：Flutter realtime thread-tail alias 预热

主 Plan：[../plan.md](../plan.md)  
Step index：02  
状态：done

## 1. 执行状态

| 字段 | 值 |
|---|---|
| Status | done |
| Branch | `awiki-me: feature/perf/message-sync-opt-0627` |
| Started | 2026-06-28 21:03:43 CST |
| Completed | 2026-06-28 21:22:50 CST |
| Commit | `awiki-me@e34f996` |
| Review evidence | Review 确认 realtime update 只做内存 tail 预热，不新增持久缓存、checkpoint 或 raw sync；alias fan-out 有序去重，覆盖 opened state key、conversation/message thread id、conversation visibility keys、direct DID/handle/direct-did/direct aliases、handle 打开路径 `dm:pending:*`、group raw id 与 `group:` canonical key；每个 alias 仍通过 `_mergeMessages` 去重。Review 发现并修复 handle alias 不应生成当前打开路径不会使用的 `dm:<owner>:<handle>`，应补齐 `dm:pending:<handle>`。 |
| Verification evidence | `dart format lib/src/presentation/chat/chat_provider.dart tests/unit/app_runtime_notification_test.dart tests/unit/chat_provider_open_test.dart` 通过；`git diff --check` 通过；`flutter test tests/unit/app_runtime_notification_test.dart` 通过 19 个测试；`flutter test tests/unit/chat_provider_open_test.dart` 通过 50 个测试；`dart run tests/unit/runner.dart` 通过，最终 `+678: All tests passed!`；`dart analyze` 仅失败于既有无关 warning：`tests/e2e/flutter/desktop_cli_peer/support/cli_peer_process.dart:192:5 unused_element _groupCountFromCliOutput`。 |
| Next action | 返回主 Plan，开始 Step 03。 |

状态取值：`pending`、`in_progress`、`review`、`blocked`、`committed`、`done`。

## 2. 目标

- 结果：AWiki Me 收到 realtime message 后，不只更新会话列表，也会把对应消息合并到所有等价 ChatThreadState key。
- 用户 / 系统可见行为：如果远端新消息到达时 App 已在前台或后台恢复，用户点击会话后 ChatView 监听任意 canonical / legacy key 都能立即看到该消息。
- 非目标：
  - 不新增 Flutter 持久消息缓存。
  - 不改变 `ConversationSummary` 或 SDK core DTO 的 owner。
  - 不依赖远端 history 来修正 key 错配。
- 完成标准：
  - alias 集合至少覆盖 `conversation.threadId`、`message.threadId`、direct peer DID、direct handle canonical id、group id、group DID / `group:` canonical id。
  - alias 去重、忽略空 key。
  - 每个 alias 下的消息通过现有 `_mergeMessages` 去重，不重复显示。
  - unit tests 覆盖 direct DID/handle 错配和 group id/DID 错配。

## 3. 设计方法

- 设计边界：App 只做内存 tail 预热；SQLite projection 和 patch stream 仍由 `im-core` 拥有。
- 核心决策：
  - 在 `ChatThreadController.applyRealtimeUpdate` 内部改为 alias fan-out，保持 `AppRuntimeProvider._applyRealtimeUpdate` 调用面最小化。
  - 抽取 `_threadIdsForRealtimeMessage(message, conversation)` 或等效 helper，返回有序去重 aliases。
  - 首选已有 state 中 `sameConversationTarget` 命中的 key，之后补齐 conversation / message / canonical keys。
  - 对每个 alias 调用 `_mergeMessages(alias, [_withThreadId(message, alias)], trustIncomingAgentReply: true)`。
- 契约 / API / 数据流：
  - `RealtimeUpdate` → `ChatThreadController.applyRealtimeUpdate` → alias fan-out → ChatThreadState memory tail。
  - conversation list 仍由 `ConversationListController.restoreConversationBestEffort` / `upsertConversation` 维护。
- 兼容性：方法签名尽量不变；如需新增 public provider 方法，也只在 `awiki-me` 内部使用。
- 迁移策略：无数据迁移。
- 风险控制：通过 key 去重和消息去重避免重复；通过 focused tests 覆盖 ChatView 监听 B key 的场景。

## 4. 实现方法

1. 在 `awiki-me` 执行 `git status --short --branch`，确认 `codex.md` 等已有本地修改归属；不要覆盖非本步骤修改。
2. 阅读相关代码：
   - `awiki-me/lib/src/presentation/app_shell/providers/app_runtime_provider.dart`
   - `awiki-me/lib/src/presentation/chat/chat_provider.dart`
   - `awiki-me/lib/src/application/thread_id_utils.dart`
   - `awiki-me/lib/src/domain/entities/conversation_identity.dart`
   - `awiki-me/lib/src/domain/entities/chat_message.dart`
   - `awiki-me/lib/src/domain/entities/conversation_summary.dart`
3. 在 `ChatThreadController` 中实现 alias 计算：
   - 固定加入非空 `conversation.threadId`。
   - 固定加入非空 `message.threadId`。
   - 对 direct：加入 `conversation.targetDid`、`conversation.targetPeer`、`message.senderDid` / `message.receiverDid` 中与 owner 相对的 peer DID、`canonicalDirectThreadId(ownerDid, peerDid)`，以及已有 state 中 `sameConversationTarget` 命中的 key。
   - 对 group：加入 `conversation.groupId`、`message.groupId`、`canonicalGroupThreadId(group)`、已有 state 命中 key。
   - owner DID 可从 `sessionProvider.session.did` 读取；缺失时跳过 owner 依赖 canonical direct key，但仍保留 conversation/message key。
4. 保持 `AppRuntimeProvider._applyRealtimeUpdate` 的会话列表更新顺序：先 chat tail prewarm，再 restore/upsert conversation；如测试证明反向更稳定，可记录理由。
5. 更新 unit tests：
   - 在 `awiki-me/tests/unit/chat_provider_open_test.dart` 或更聚焦 test file 中添加：conversation.threadId 为 `direct-handle:*`，message.threadId 为 `dm:*`，打开 ChatView 监听任一 key 都能看到消息。
   - 添加 group test：`groupId` 与 `group:<id>` key 都预热。
   - 添加 duplicate test：同一 message 通过两个 aliases 合并后单 key 内不重复。
6. 如 docs 需要，Step 05 再统一更新 performance tracing；本步骤仅更新直接相关注释或测试说明。
7. 运行 focused unit tests，Review，commit。

## 5. 路径

| 仓库 / 模块 / 文件 | 计划变更 | 备注 |
|---|---|---|
| `awiki-me/lib/src/presentation/chat/chat_provider.dart` | 修改 `applyRealtimeUpdate`，新增 alias helper 和预热逻辑。 | P1 主变更。 |
| `awiki-me/lib/src/presentation/app_shell/providers/app_runtime_provider.dart` | 原则上保持调用；必要时传递更多上下文。 | 避免 provider 层复制 alias 规则。 |
| `awiki-me/lib/src/application/thread_id_utils.dart` | 复用 canonical direct/group helper；必要时补小工具。 | 不新增持久事实。 |
| `awiki-me/lib/src/domain/entities/conversation_identity.dart` | 只读参考 visibility alias 规则。 | 避免列表和聊天身份规则冲突。 |
| `awiki-me/tests/unit/chat_provider_open_test.dart` | 增加 alias prewarm tests。 | 可使用现有 fake providers。 |
| `awiki-me/tests/unit/app_runtime_notification_test.dart` | 必要时增加 `_applyRealtimeUpdate` 端到端 provider test。 | 确认 runtime provider 调用 chat prewarm。 |
| `awiki-me/tests/unit/test_support.dart` | 如 fake service 需要增加断言支持。 | 避免真实服务依赖。 |

## 6. 依赖

- 前置步骤：建议 Step 01 已完成，以保证底层 patch 行为也正确；本步骤 unit tests 可独立运行。
- 外部文档或决策：主 Plan P1 设计；`awiki-me/docs/conversation-presentation-ownership.md` 不允许新增 Flutter 主数据缓存。
- 环境前提：Dart / Flutter tooling 可运行；执行前保留 `awiki-me/codex.md` 当前状态。

## 7. 验收标准

- [x] realtime message 被合并到 `conversation.threadId` key。
- [x] realtime message 被合并到 `message.threadId` key。
- [x] direct peer DID / handle 相关 canonical key 被预热。
- [x] group id / group DID / `group:` canonical key 被预热。
- [x] 同一 key 内没有重复消息。
- [x] `AppRuntimeProvider._applyRealtimeUpdate` 的现有通知、group upsert、conversation upsert 行为不回归。
- [x] Review 发现已经修复或明确记录。
- [x] 本步骤在进入下一步之前已经创建聚焦 commit。

## 8. 验证方式

| 检查项 | 命令 / 方法 | 预期证据 |
|---|---|---|
| Focused unit | `cd awiki-me && dart run tests/unit/runner.dart --name realtime` | 新增 realtime alias tests 通过；如 runner 不支持 `--name`，记录实际 focused 命令。 |
| Chat provider unit | `cd awiki-me && dart run tests/unit/runner.dart --name chat_provider` | 相关 ChatThreadController tests 通过。 |
| App runtime unit | `cd awiki-me && dart run tests/unit/runner.dart --name app_runtime` | `_applyRealtimeUpdate` 相关 tests 通过。 |
| Broader unit | `cd awiki-me && dart run tests/unit/runner.dart` | 单元回归通过。 |
| Analyze | `cd awiki-me && dart analyze` | 无新增 analyzer 错误。 |
| Git hygiene | `cd awiki-me && git status --short --branch` | commit 前后状态记录完整，`codex.md` 归属明确。 |

如果某个命令不能运行，记录原因、影响和替代证据。

## 9. Review 环节

- Review 时机：本步骤代码实现完成后、commit 前。
- Review 重点：
  - alias 计算是否覆盖用户要求的所有 key，且不加入空 key。
  - direct peer DID 与 handle 归一是否不会把不同会话合并。
  - group id / DID 是否不会混入 direct key。
  - `_mergeMessages` 去重是否足以防止重复渲染。
  - 是否保持 App overlay / SDK DTO 边界。
  - 测试是否验证“缓存到 A key，ChatView 监听 B key”的真实问题。

| Review 项 | 结果 | 备注 |
|---|---|---|
| 发现问题 | 发现 1 个边界问题 | direct handle alias 初版会生成 `dm:<owner>:<handle>`，该 key 不是当前 `openDirectConversationForDid` 的 handle 打开路径；同时缺少 `dm:pending:<handle>`。 |
| 已修复问题 | 已修复 | 去掉 handle 生成的 `dm:<owner>:<handle>`，补齐 `dm:pending:<handle>`，并在 realtime direct alias 单测中断言该 key 被预热。 |
| 剩余风险 | 可接受 | fan-out 会增加少量内存 state，但仅写非空去重 key，且单 key 内仍用 `_mergeMessages` 通过 remoteId/localId/pending 匹配去重。 |
| 新增或缺失测试 | 已新增 | `tests/unit/app_runtime_notification_test.dart` 新增 direct DID/handle/message thread/`dm:pending:*` alias、重复消息去重、group raw/canonical alias 覆盖；`tests/unit/chat_provider_open_test.dart` 更新 canonical realtime thread 预热断言。 |
| 已更新或缺失文档 | 本步骤无需业务文档 | 主 Plan 和本 Step 文档已回填执行证据；面向性能 tracing 的说明按计划留到 Step 05 统一更新。 |

## 10. Commit 要求

- Commit 时机：本步骤实现、验证、Review 都完成后。
- Commit 范围：只包含 AWiki Me P1 alias prewarm 代码、测试和必要文档。
- Commit 前状态：`awiki-me` 位于 `feature/perf/message-sync-opt-0627`，领先远端 1 个提交；未提交文件包括 `android/app/src/main/java/io/flutter/plugins/GeneratedPluginRegistrant.java`、主 Plan、本 Step 文档、`lib/src/presentation/chat/chat_provider.dart`、`tests/unit/app_runtime_notification_test.dart`、`tests/unit/chat_provider_open_test.dart`。
- 纳入文件：`lib/src/presentation/chat/chat_provider.dart`、`tests/unit/app_runtime_notification_test.dart`、`tests/unit/chat_provider_open_test.dart`。
- Commit 后证据：实现提交 `awiki-me@e34f996 fix(app): prewarm realtime thread aliases`；提交后仍有 `android/app/src/main/java/io/flutter/plugins/GeneratedPluginRegistrant.java` 和 Plan 文档未提交，Android 生成文件不是本步骤范围，计划文档作为单独台账提交。
- 遗留未提交变更：`android/app/src/main/java/io/flutter/plugins/GeneratedPluginRegistrant.java` 为执行前已有/工具生成的 Android registrant 差异，非本步骤范围，未纳入实现提交。
- 建议消息：`fix(app): prewarm realtime thread aliases`

## 11. Blocked 处理

| Blocker | 证据 | 已尝试方案 | 影响范围 | 下一步决策 |
|---|---|---|---|---|
| 待填 | 待填 | 待填 | 当前步骤 / 整体计划 | 待填 |

## 12. Plan 变更记录

| 日期 | 变更 | 原因 | 主 Plan 变更记录链接 |
|---|---|---|---|
| 2026-06-28 | 初始 Step 02 计划 | P1 修复 realtime tail key 错配。 | [../plan.md#15-plan-变更记录](../plan.md#15-plan-变更记录) |

## 13. 风险、回滚与后续文档

- 风险：alias fan-out 过宽导致状态重复、错误会话串消息、内存增长。
- 回滚 / 回退：回滚本步骤 commit 后，realtime update 退回单 key merge。
- 后续文档：Step 05 更新 `awiki-me/docs/performance-tracing.md`，解释 memory tail prewarm 与点击首屏指标。
