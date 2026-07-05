# AWiki Me 性能追踪日志

AWiki Me 支持一个默认关闭的性能诊断开关，用来定位启动后会话列表慢、进入会话后消息列表加载慢、CPU 短时间升高等问题。

## 开启方式

```bash
cd awiki-me
flutter run -d macos --dart-define=AWIKI_PERF_LOG=true
```

默认只输出 `summary` 级别事件。`summary` 覆盖启动、会话列表、history、mark-read、慢帧等主链路结果；高频 UI build、merge 子步骤、重复请求类日志属于 `verbose`，默认不会输出，避免长时间运行时日志过大。

需要完整细粒度日志时使用：

```bash
flutter run -d macos \
  --dart-define=AWIKI_PERF_LOG_LEVEL=verbose
```

可选：调整慢帧阈值，默认 24ms；调整单个事件的日志上限，默认每个事件最多打印 120 条，超过后只打印一次 suppress 提示。

```bash
flutter run -d macos \
  --dart-define=AWIKI_PERF_LOG=true \
  --dart-define=AWIKI_PERF_SLOW_FRAME_MS=16 \
  --dart-define=AWIKI_PERF_MAX_EVENT_LOGS=200
```

日志前缀统一为：

```text
[awiki_me][perf]
```

## 日志级别与容量控制

| 级别 | 开启方式 | 内容 | 日志量风险 |
|---|---|---|---|
| `off` | 默认 | 不输出性能日志 | 无 |
| `summary` | `AWIKI_PERF_LOG=true` 或 `AWIKI_PERF_LOG_LEVEL=summary` | 主链路汇总、慢帧、关键 native/SQLite/RPC 边界 | 低；适合日常联调 |
| `verbose` | `AWIKI_PERF_LOG_LEVEL=verbose` | 包含 UI build、merge loop、重复请求、细粒度子步骤 | 中；只建议短时间复现问题时开启 |

每个事件默认最多输出 120 条，由 `AWIKI_PERF_MAX_EVENT_LOGS` 控制。设置为 `0` 表示不限制，通常不建议在线上或长时间运行时使用。

## 重点事件

| 事件前缀 | 含义 | 用途 |
|---|---|---|
| `main.*` / `bootstrap.*` | App 启动、路径解析、bootstrap 创建 | 判断打开软件初始等待是否卡在 App 初始化 |
| `app_refresh.*` | 登录态后台刷新本地会话、profile、agents、friends、groups 以及 product store warm-up | 判断启动后列表慢是否被后台刷新抢资源；`app_refresh.conversation_fast_local` 应先完成，其他数据并发补齐 |
| `conversation_list.refresh_fast_local*` / `conversation_list.refresh_enrich*` | 会话列表 provider 的本地 summary 首屏刷新与后台 enrichment merge/badge | 判断首屏 state 更新是否只等本地 summary，Agent/overlay 是否在后台补齐 |
| `conversation_service.fast_local*` / `conversation_service.enrich*` | im-core summary list、Agent 投影、overlay、过滤排序 | 判断会话列表业务层慢点；`fast_local` 不应等待远端 Agent inventory |
| `product_store.*` | product overlay SQLite warm-up、路径解析、legacy migration、open database、query/decode | 判断 overlay DB 首次 open/migration 是否仍挤进首屏路径 |
| `im_core_conversations.*` | Dart -> im-core native 会话查询边界 | 判断是否卡在 native/SQLite/SDK 查询 |
| `agents.load*` | Agent 清单与 daemon status 本地投影 | 判断 Agent 投影是否拖慢会话列表 |
| `chat.open_conversation` | 点击进入会话 | 进入会话起点 |
| `chat.conversation_timeline.*` / `im_core_messages.conversation_timeline*` | 进入会话时按 canonical `conversationId` 读取本地 projection、Dart 映射、merge/sort | 判断本地已有消息是否能先于远端 history 快速渲染 |
| `chat.local_history.*` / `im_core_messages.local_history*` | legacy local history 日志名或低层兼容入口 | 新链路优先看 canonical conversation timeline；旧名只用于兼容对比 |
| `chat.remote_history.*` / `im_core_messages.remote_history*` | 后台远端 history reconcile、Dart 映射、merge/sort | 判断远端补齐、E2EE projection 和 native persist/merge 是否仍拖慢进入会话 |
| `chat.history.*` / `im_core_messages.history*` | 兼容旧日志名的消息历史边界 | 新链路优先看 `conversation_timeline` / `remote_history`；旧名只用于兼容对比 |
| `message_sync.coordinator.request` | App 侧可靠同步调度请求 | 判断 startup、resume、reconnect、realtime dirty/gap 是否合并为一次 SDK `syncDelta`；该事件是 verbose 级别 |
| `message_sync.delta` | App 调用 SDK 全局 reliable sync 入口 | 判断 Rust `im-core` 是否完成账号级 delta apply；App 只提供 `reason`/`limit`，不读写 checkpoint |
| `message_sync.conversation_after` | 打开会话后的 conversation-local 补新 | 判断本地 conversation timeline 首屏后，是否按当前 canonical conversation 的最大 `server_seq` 补齐新消息；不推进全局 checkpoint |
| `message_sync.thread_after` | legacy thread-local 补新日志名 | 仅用于兼容/低层诊断；AWiki Me display path 应优先看 `message_sync.conversation_after` |
| `chat.messages.merge_loop` / `chat.messages.merge` | 消息列表 merge、pending 匹配和排序前准备 | `indexed=true` 表示当前 merge 已用 remoteId/localId/pending 索引，避免每条 incoming 反复 `indexWhere` 扫描 current |
| `chat.mark_read*` | 打开未读会话后的本地清未读与已读同步 | 判断本地清 unread 和 SDK thread mark-read ack 是否慢 |
| `chat_page.build.*` / `conversation_list_page.*build.*` | Flutter build 准备阶段 | 判断是否是 UI 构建/重算慢 |
| `frame.slow` | Flutter 慢帧 build/raster 时间 | 判断是否出现明显 UI jank |

## E2E 性能指标

`dart run tests/e2e/runner.dart --case performance` 会在真实桌面 App +
`awiki-cli-rs2` peer + 后端链路上生成
`.e2e/desktop-cli-peer/<run-id>/reports/timings.json`，其中
顶层 `metrics` map（由 `appProductTimings` 明细汇总）必须包含消息首屏指标和
消息内存缓存有界化指标；顶层 `counters` map 必须包含缓存累计计数，用作
performance gate 的 hard evidence。

消息首屏相关指标：

| 指标 | 含义 | 通过要求 |
|---|---|---|
| `message.cli_send_to_app_open_first_paint_ms` | 从 CLI 向 App 发送消息开始，到 App 通过当前 provider open path 打开会话并在首屏 state 中看到该消息。 | required metric；默认 hard budget 90000ms，soft budget 5000ms。 |
| `thread.realtime_open_first_paint_ms` | conversation preview 已到达后，调用 App 打开会话路径到 `chatThreadProvider` 首屏出现该消息的耗时。 | required metric；默认 hard budget 5000ms，soft budget 1500ms。 |
| `message.cli_send_app_thread_after_ms` | 打开首屏之后显式 conversation-after / legacy thread-after 的后台补新耗时。 | 只能作为后台补同步证据，不能替代 first-paint 指标。 |
| `message.cli_send_to_app_history_visible_ms` | App history 查询最终可见该消息的耗时。 | 用于确认本地 projection/history 最终一致，不能替代 first-paint 指标。 |

first-paint gate 必须先等待 fast local conversation preview，然后使用
`ConversationSummary.effectiveConversationId` 打开会话，通过 `AppConversationReadRef`
读取 canonical conversation timeline 或等待 conversation timeline patch，最后轮询当前
`chatThreadProvider` UI window。它不能只通过 legacy `loadHistory(ThreadRef)`、手动
`syncThreadAfter(ThreadRef)`、alias prewarm 或远端 history response 证明“可见”。

消息内存缓存指标写入顶层 `metrics`：

| 指标 | 含义 | 通过要求 |
|---|---|---|
| `cache.raw_thread_state_count` | 当前 provider 保留的 raw thread state 数。 | required metric；用于发现 alias state 或 thread state 无界增长。 |
| `cache.canonical_thread_count` | 当前按 canonical conversation 聚合后的 thread 数。 | required metric；应受 cache policy 约束。 |
| `cache.total_retained_messages` | 当前内存中保留的消息总数。 | required metric；应受全局 retained messages 上限和 protected overflow 规则约束。 |
| `cache.active_patch_subscription_count` | 当前活跃的 thread patch subscription 数。 | required metric；不应随打开/关闭会话次数无界增长。 |
| `cache.message_route_entry_count` | 当前消息路由索引条目数。 | required metric；用于证明被 trim 的消息仍可通过轻量索引完成 source-message 路由。 |
| `cache.trimmed_message_count` | 本次 performance flow 观察到的累计 trim 消息数。 | required metric；同时写入 `counters`。 |
| `cache.evicted_thread_count` | 本次 performance flow 观察到的累计 evict thread 数。 | required metric；同时写入 `counters`。 |
| `cache.protected_overflow_count` | 因 protected message 不能被普通 trim 删除而产生的累计 overflow 数。 | required metric；同时写入 `counters`。 |

缓存累计计数同时写入顶层 `counters`：

| Counter | 含义 |
|---|---|
| `cache.trimmed_message_count` | 累计被 cache policy trim 的消息数量。 |
| `cache.evicted_thread_count` | 累计被 cache policy 回收的 thread 数量。 |
| `cache.protected_overflow_count` | 累计 protected overflow 次数。 |

这些 cache 指标和 counters 只记录数量，不包含消息正文、payload、thread id、
token、本地路径、附件路径或完整 DID。它们用于判断 UI 层消息内存缓存是否有界，
不代表 Rust `im-core` 的 reliable checkpoint 或 SQLite projection 状态。

`--case performance` 与 `--case full` 目的不同：performance gate 专门验证启动、
会话打开、App/CLI 互发可见延迟和 cache counters/budgets；full E2E 验证真实
backend App + CLI peer 的完整产品互发链路。运行命令分别是：

```bash
dart run tests/e2e/runner.dart --case performance
dart run tests/e2e/runner.dart --case full
```

## 可靠同步边界

可靠消息同步的 SDK / Rust 契约以
[awiki-cli-rs2/docs/flutter-sdk/awiki-im-core-flutter-sdk.md](../../awiki-cli-rs2/docs/flutter-sdk/awiki-im-core-flutter-sdk.md)
和
[awiki-cli-rs2/docs/api/im-core-interface/04-message-interface.md](../../awiki-cli-rs2/docs/api/im-core-interface/04-message-interface.md)
为准。AWiki Me 只负责根据 App 生命周期和 realtime 提示调度同步；全局 reliable
checkpoint 属于 Rust `im-core` / SQLite local state。

App 侧允许做的事情：

- 在启动、恢复前台、realtime 重连、realtime dirty / gap hint 后请求 `syncDelta`。
- 传入诊断用 `reason`，例如 `startup`、`app_resumed`、`realtime_reconnected`、
  `realtime_dirty`、`realtime_gap`。
- 在打开会话后，用当前 `AppConversationReadRef` 和本地 canonical timeline 的最大
  `server_seq` 调用 `syncConversationAfter`，做 conversation-local 补新；legacy
  `syncThreadAfter(ThreadRef)` 只作为 adapter/debug path。
- 在 SDK sync 成功后刷新本地 projection，例如重新读取 fast local conversation list。
- 对 sync/realtime/backfill 返回的消息页，等待或 repair core committed projection/read model；
  App 不直接把这些返回值 merge 为 UI authoritative truth。

App 侧禁止做的事情：

- 不读取、保存或修改全局 reliable checkpoint。
- 不传入 `since_event_seq`，不手动推进 `next_event_seq`。
- 不手写 `/im/rpc` 的 `sync.*` payload，不绕过 SDK 拼 wire 请求。
- 不把 realtime `sync` hint 或 realtime projection 成功视为 checkpoint commit。
- 不在 `snapshotRequired` / `snapshot_required` 时清空本地 projection；该状态应按
  SDK 契约 fail-closed，并等待后续 repair / snapshot 方案。

## 如何解读

1. 如果 `im_core_conversations.native_list` 很慢，优先怀疑 im-core native、SQLite/WAL、本地库版本。
2. 如果 `chat.conversation_timeline.*` / `im_core_messages.conversation_timeline*` 很快但 `chat.remote_history.load` / `im_core_messages.remote_history_native` 很慢，说明进入会话首屏已 local-first，剩余慢点在远端 history reconcile、E2EE projection persist 或 native local merge。
3. 如果 `chat.conversation_timeline.*` 本身慢，优先检查本地 projection 查询、SQLite/WAL、消息数量和 `chat.messages.merge` / `chat.messages.sort`。旧 `chat.local_history.*` 出现在主链路时，应确认它只是 legacy adapter 或日志名兼容。
4. 如果 `conversation_service.fast_local` 很快但 `conversation_service.enrich`、`conversation_service.agent_projection` 或 `agents.load.*` 很慢，说明首屏已经脱离远端 Agent inventory，慢点在后台补齐链路。
5. 如果 `product_store.legacy_migration` 或 `product_store.open_database` 很慢，优先看首次 DB open、旧库迁移和 WAL/SHM 拷贝；这些应通过 `app_refresh.product_store_warm_up` 后台预热，不能阻塞 `conversation_fast_local`。
6. 如果 `conversation_service.filter_sort`、`conversation_list.refresh_fast_local.merge`、`conversation_list.refresh_enrich.merge` 或 `chat.messages.sort` 很慢，优先看 Dart 侧列表规模、索引命中和排序。`conversation_list.*.merge` 与 `chat.messages.merge_loop` 应带 `indexed=true`，否则说明回归到线性扫描路径。
7. 如果 `message_sync.delta` 很慢，优先判断是 SDK delta apply、SQLite projection 写入、
   message-service sync 响应，还是随后 `conversation_list.refresh_fast_local` 读取本地
   projection 变慢。`message_sync.delta` 的返回诊断可用于判断 `eventsApplied`、
   `pagesFetched`、`hasMore`、`snapshotRequired` 和 `warnings`，但不能把
   `lastAppliedEventSeq` 当作 App 可写 checkpoint。
8. 如果 `message_sync.conversation_after` 很慢，优先看该 conversation 的远端补新、E2EE projection
   persist 和 projection repair/load。它只按 `afterServerSeq` 做 conversation-local freshness，
   不代表全局 reliable sync 落后。`message_sync.thread_after` 只应作为 legacy adapter/debug 线索。
9. 如果 `chat.mark_read` 很慢，优先看 `im_core_conversations.mark_read.native` 的
   `local_candidates`、`remote_ack`、`partial` 和 `warnings`；旧的
   `im_core_conversations.mark_read.history_page` 不应再出现，出现则说明回归到了
   history 分页找 unread ids。
10. 如果 `frame.slow` 很多而数据层日志不慢，说明主要是 Flutter build/raster 或大量 widget 重建。

## 当前性能门禁

- 启动或恢复时，应先看到 `app_refresh.conversation_fast_local` 与 `conversation_list.refresh_fast_local`，再看到 `conversation_list.refresh_enrich`、`app_refresh.agents`、`app_refresh.friends` 和 `app_refresh.groups`。
- `conversation_service.fast_local` 不应等待 `conversation_service.agent_projection.list_agents`；如果二者耗时同步增长，说明会话首屏又被 Agent RPC 绑定。
- `product_store.open_database` / `product_store.legacy_migration` 可在后台 warm-up 中出现，但不应成为 `conversation_list.refresh_fast_local` 的直接子链路。
- 进入已有本地 projection 的会话时，应先看到 `chat.conversation_timeline.*` / `im_core_messages.conversation_timeline*`，消息立即出现；`chat.remote_history.load` 只作为后台 reconcile，失败不应清空已显示的本地消息。
- 收到 CLI 远端新消息后，performance E2E 必须记录
  `message.cli_send_to_app_open_first_paint_ms` 和
  `thread.realtime_open_first_paint_ms`；这两项证明点击路径本身 memory/local-first，
  不能被 `message.cli_send_app_thread_after_ms` 或 history 查询替代。
- Performance E2E 必须在 `timings.json` 顶层 `metrics` / `counters` 写入
  `cache.*` 数量指标，并把缓存上限类指标作为 gate；这些字段只记录数量，不记录正文、
  payload、thread id、token 或本地路径。
- 启动、恢复前台、realtime 重连、realtime dirty / gap 后，App 侧应只调度 SDK `message_sync.delta`；不能出现 App 自己读写 checkpoint、传 `since_event_seq` 或手写 `sync.*` wire payload 的代码路径。
- 打开已有本地 projection 的会话时，canonical conversation timeline 应先完成；如需要补新，可随后看到 `message_sync.conversation_after`，该链路不得推进账号级 reliable checkpoint。
- 打开未读会话时只允许看到一次远端 `chat.remote_history.*` reconcile；`chat.mark_read*` 不应再触发 history 分页。
- 文本和 payload 发送/重试成功后，pending/failed/sent 由 core durable message row 与 `MessageMetadata.send_state` 表达；conversation list/detail 通过 core patch/read model 更新。App 不得本地 upsert conversation row 或 memory pending 来决定 send correctness。附件发送目前可保留明确标注的 presentation fallback，后续应单独收敛。

## 隐私说明

日志只记录耗时、数量、布尔值和 thread/DID 的短 hash，不应包含 token、私钥、消息正文或完整 DID。向协作者贴日志前仍建议检查并删除任何异常敏感内容。
