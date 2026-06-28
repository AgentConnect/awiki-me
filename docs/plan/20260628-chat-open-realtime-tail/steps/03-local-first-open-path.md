# Step 03：点击路径 local-first，网络补同步后台化

主 Plan：[../plan.md](../plan.md)  
Step index：03  
状态：done

## 1. 执行状态

| 字段 | 值 |
|---|---|
| Status | done |
| Branch | `awiki-me: feature/perf/message-sync-opt-0627` |
| Started | 2026-06-28 21:26:45 CST |
| Completed | 2026-06-28 21:35:18 CST |
| Commit | `awiki-me@b6d8c1f` |
| Review evidence | Review 确认 `openConversation` 仍只调度 `_openConversationLocalFirst`，不会 await 首屏后台 work；memory tail 命中时记录 `chat.open.first_paint` 并后台 `syncThreadAfter`；空内存才读 local history；local history 命中后不再因 unreadCount 或 lastMessageAt 调用 remote history；本地空或本地失败时 remote fallback 保留，且允许 loading / failure；`syncThreadAfter` 仍走 `messageSyncServiceProvider`，未推进 global checkpoint。 |
| Verification evidence | `dart format lib/src/presentation/chat/chat_provider.dart tests/unit/chat_provider_open_test.dart` 通过；`git diff --check` 通过；`flutter test tests/unit/chat_provider_open_test.dart` 通过 50 个测试；`flutter test tests/unit/app_runtime_notification_test.dart` 通过 19 个测试；`dart run tests/unit/runner.dart` 通过，最终 `+678: All tests passed!`；`dart analyze` 仅失败于既有无关 warning：`tests/e2e/flutter/desktop_cli_peer/support/cli_peer_process.dart:192:5 unused_element _groupCountFromCliOutput`。 |
| Next action | 返回主 Plan，开始 Step 04。 |

状态取值：`pending`、`in_progress`、`review`、`blocked`、`committed`、`done`。

## 2. 目标

- 结果：用户点击含新消息 / 未读消息的会话时，ChatView 首屏优先显示 memory tail 或本地 SQLite tail；网络补同步全部后台化。
- 用户 / 系统可见行为：类似微信的体验，收到远端新消息后点开能马上看到最近消息；远端 reconcile 变慢或失败也不阻塞已显示内容。
- 非目标：
  - 不删除 remote history fallback。
  - 不改变 `syncThreadAfter` 的 thread-local 语义。
  - 不把 unread count 本身作为 remote history 阻塞条件。
- 完成标准：
  - memory tail 已有消息时，`openConversation` 不设置 blocking loading，也不立即 remote `loadHistory`。
  - local history 能返回消息时，remote history 不因 unreadCount 单独触发。
  - `syncThreadAfter` 总是 `unawaited` 或等效后台执行，错误只记录日志。
  - 本地为空或本地读取失败时，remote history 作为兜底后台启动，并可显示 loading / failure。

## 3. 设计方法

- 设计边界：点击路径只负责 first paint；freshness 由后台 `syncThreadAfter`、global `MessageSyncCoordinator` 和 remote fallback 补齐。
- 核心决策：
  - 将 `_shouldLoadHistory` 拆分为本地读取需要和 remote fallback 需要，避免 `conversation.unreadCount > 0` 强制 remote history。
  - `_openConversationLocalFirst` 先检查当前 `thread(displayThreadId).messages` 是否已有可渲染消息；有则立即返回首屏，并后台触发 `_syncThreadAfterLocalMax`。
  - local history 只作为本地 tail 补充；返回非空后也只后台 thread-after。
  - remote history 条件收窄为：本地当前为空且 `localResult.loadedAny == false`，或 localResult.failed，或显式 force refresh。
- 契约 / API / 数据流：
  - Conversation click → ensure thread patch subscription → memory tail first → optional localHistory → background thread-after → remote history only if local missing。
  - mark-read 仍 best effort，不阻塞 first paint。
- 兼容性：保留现有 `syncHistoryForConversation(force:)` public behavior，但内部 showLoading/reportFailure 更严格。
- 迁移策略：无数据迁移。
- 风险控制：fake service tests 断言 remote history 调用次数；performance logs 区分 first paint source。

## 4. 实现方法

1. 在 `awiki-me` 执行 `git status --short --branch`，确认 Step 02 已提交且没有无关完成工作。
2. 阅读：
   - `awiki-me/lib/src/presentation/chat/chat_provider.dart`
   - `awiki-me/lib/src/presentation/conversation_list/conversation_list_page.dart`
   - `awiki-me/lib/src/presentation/conversation_list/conversation_workspace_page.dart`
   - `awiki-me/tests/unit/chat_provider_open_test.dart`
3. 调整 `_openConversationLocalFirst`：
   - 当前 thread 已有可渲染消息时，记录 `chat.open.first_paint_source=memory_tail` 或类似 perf log，后台 `_syncThreadAfterLocalMax`，不 remote history。
   - 当前 thread 为空时，调用 `_loadLocalHistory`；如果返回非空，记录 `local_history` source，后台 thread-after，不 remote history。
   - local 失败或返回空时，才后台 `syncHistoryForConversation(... showLoading: true, reportFailure: true/failed)`。
4. 调整判定函数：
   - 保留 `_shouldLoadHistory` 供 remote/manual refresh 时使用，或拆成 `_shouldLoadLocalHistory` 和 `_shouldLoadRemoteHistory`。
   - `conversation.unreadCount > 0` 应触发 background freshness，而不是 remote first paint。
   - `conversation.lastMessageAt > latestLocalAt` 且本地已有消息时，优先 thread-after，不 remote history；只有 thread-after 后仍缺数据或本地空时 fallback。
5. 确保 `_syncThreadAfterLocalMax`：
   - 读取当前 displayThreadId 的 max server seq。
   - 使用 `_localHistoryThreadRefFor(conversation)`。
   - 不 await 于首屏路径；错误只打 `chat.thread_after.failed`。
6. 更新 tests：
   - 本地 memory tail 已有 realtime 消息，open unread conversation 不调用 remote `loadHistory`。
   - local history 返回消息，remote `loadHistory` 不调用；`syncThreadAfter` 被后台请求。
   - local history 返回空或失败，remote fallback 被调用且 showLoading/reportFailure 符合预期。
   - manual `refreshConversation(force)` 仍可 remote refresh。
7. 添加或更新性能日志 docs 的 TODO 可留到 Step 05；如果本步骤新增事件名，应同步 `awiki-me/docs/performance-tracing.md` 或在 Step 05 明确待同步。
8. 运行验证，Review，commit。

## 5. 路径

| 仓库 / 模块 / 文件 | 计划变更 | 备注 |
|---|---|---|
| `awiki-me/lib/src/presentation/chat/chat_provider.dart` | 调整 `_openConversationLocalFirst`、history 判定、remote fallback 条件、perf log。 | P2 主变更。 |
| `awiki-me/lib/src/presentation/conversation_list/conversation_list_page.dart` | 原则上只读确认导航不 await；如需最小修正则记录。 | UI 点击路径。 |
| `awiki-me/lib/src/presentation/conversation_list/conversation_workspace_page.dart` | 只读确认 ChatView key。 | 与 alias key 配合。 |
| `awiki-me/tests/unit/chat_provider_open_test.dart` | 增加 local-first / remote fallback tests。 | 核心验收。 |
| `awiki-me/tests/unit/test_support.dart` | 必要时增加 fake call counters。 | 断言 remote history / syncThreadAfter。 |
| `awiki-me/docs/performance-tracing.md` | 若本步骤新增事件名，更新或在 Step 05 更新。 | 文档同步。 |

## 6. 依赖

- 前置步骤：Step 02 完成；否则 memory tail 可能仍写入错误 key，P2 测试无法证明真实点击路径。
- 外部文档或决策：`awiki-me/README.md` Message Sync 边界、`awiki-harness/features/message-sync-reliability.md`。
- 环境前提：AWiki Me unit test harness 可运行；不得误改平台 runner。

## 7. 验收标准

- [x] memory tail 命中时首屏不等待 local history / remote history。
- [x] local history 命中时首屏不等待 remote history。
- [x] unreadCount 不再单独导致 remote history 阻塞。
- [x] `syncThreadAfter` 只后台补新，不影响 first paint。
- [x] 本地空 / 本地失败时 remote history fallback 保留。
- [x] fake service tests 覆盖 remote call / syncThreadAfter call 的期望。
- [x] Review 发现已经修复或明确记录。
- [x] 本步骤在进入下一步之前已经创建聚焦 commit。

## 8. 验证方式

| 检查项 | 命令 / 方法 | 预期证据 |
|---|---|---|
| Focused chat open tests | `cd awiki-me && dart run tests/unit/runner.dart --name openConversation` | local-first tests 通过。 |
| Chat provider suite | `cd awiki-me && dart run tests/unit/runner.dart --name chat_provider` | ChatThreadController 相关回归通过。 |
| Full unit | `cd awiki-me && dart run tests/unit/runner.dart` | 单元回归通过。 |
| Analyze | `cd awiki-me && dart analyze` | 无新增 analyzer 错误。 |
| Manual log review | 运行或检查 tests 中 perf events | first paint source 不包含敏感内容。 |
| Git hygiene | `cd awiki-me && git status --short --branch` | commit 前后状态记录完整。 |

如果某个命令不能运行，记录原因、影响和替代证据。

## 9. Review 环节

- Review 时机：本步骤代码实现完成后、commit 前。
- Review 重点：
  - `openConversation` 是否仍不 await 首屏后台 work。
  - remote fallback 条件是否不会因 unreadCount 误触发。
  - local empty / failed 情况是否仍有兜底和错误提示。
  - mark-read best effort 是否不阻塞 UI。
  - `syncThreadAfter` 是否不推进 global checkpoint、未被用于同步阻塞。
  - 新 perf log 是否脱敏。

| Review 项 | 结果 | 备注 |
|---|---|---|
| 发现问题 | 发现 1 个测试语义冲突 | 旧 pending 回补测试依赖 open path 触发 remote history；Step 03 后 open path 本地有消息时应只后台 thread-after。 |
| 已修复问题 | 已修复 | 将 pending 回补测试改为 `thread-after` 回补服务端已发送消息，同时断言 remote history 不被调用。 |
| 剩余风险 | 可接受 | memory/local 命中后 remote history 不再立即兜底；freshness 依赖 thread-after 和 patch stream。已有 local 空、local 失败、manual refresh 测试覆盖兜底路径。 |
| 新增或缺失测试 | 已更新 | `tests/unit/chat_provider_open_test.dart` 覆盖 local history 命中不 remote、local 空 remote fallback、memory tail 命中走 thread-after 不 remote、pending 回补由 thread-after 完成、已加载再次打开不重读本地。 |
| 已更新或缺失文档 | 本步骤无需业务文档 | 新增 perf event `chat.open.first_paint`，按计划在 Step 05 更新 `docs/performance-tracing.md`。 |

## 10. Commit 要求

- Commit 时机：本步骤实现、验证、Review 都完成后。
- Commit 范围：只包含 AWiki Me P2 click local-first 代码、测试和必要文档。
- Commit 前状态：`awiki-me` 位于 `feature/perf/message-sync-opt-0627`，领先远端 3 个提交；未提交文件包括 `android/app/src/main/java/io/flutter/plugins/GeneratedPluginRegistrant.java`、主 Plan、本 Step 文档、`lib/src/presentation/chat/chat_provider.dart`、`tests/unit/chat_provider_open_test.dart`。
- 纳入文件：`lib/src/presentation/chat/chat_provider.dart`、`tests/unit/chat_provider_open_test.dart`。
- Commit 后证据：实现提交 `awiki-me@b6d8c1f fix(app): keep chat open first paint local-first`；提交后仍有 `android/app/src/main/java/io/flutter/plugins/GeneratedPluginRegistrant.java` 和 Plan 文档未提交，Android 生成文件不是本步骤范围，计划文档作为单独台账提交。
- 遗留未提交变更：`android/app/src/main/java/io/flutter/plugins/GeneratedPluginRegistrant.java` 为执行前已有/工具生成 Android registrant 差异，非本步骤范围，未纳入实现提交。
- 建议消息：`fix(app): keep chat open first paint local-first`

## 11. Blocked 处理

| Blocker | 证据 | 已尝试方案 | 影响范围 | 下一步决策 |
|---|---|---|---|---|
| 待填 | 待填 | 待填 | 当前步骤 / 整体计划 | 待填 |

## 12. Plan 变更记录

| 日期 | 变更 | 原因 | 主 Plan 变更记录链接 |
|---|---|---|---|
| 2026-06-28 | 初始 Step 03 计划 | P2 保证点击路径 first paint local-first。 | [../plan.md#15-plan-变更记录](../plan.md#15-plan-变更记录) |

## 13. 风险、回滚与后续文档

- 风险：remote fallback 收窄过度，导致本地空时用户等待；后台 sync 错误被吞导致新消息延迟。
- 回滚 / 回退：回滚本步骤 commit 后恢复原 open path；或只回退 remote fallback 判定，保留 perf log。
- 后续文档：Step 05 将性能追踪文档补齐，说明 remote history 仅本地缺失时出现。
