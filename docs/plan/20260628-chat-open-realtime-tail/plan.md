# Plan：AWiki Me 新消息点开首屏秒开优化

状态：in_progress
DOC：`awiki-me/docs/plan/20260628-chat-open-realtime-tail/`  
Harness：`awiki-harness/`  
创建时间：2026-06-28  
恢复指针：Step 03 已完成；恢复时从执行台账里第一个状态不是 `done` 的步骤继续，当前应从 Step 04 开始。

## 1. 目标

- 任务目标：实现用户列出的 P0、P1、P2、P3 四项优化，让 AWiki Me 在收到远端新消息后，点进会话时能优先用已落地 / 已预热的本地 tail 立即渲染，而不是等待远端 history 或较重的本地读取链路。
- 预期行为：
  - Rust `im-core` 在 realtime incoming 成功写入本地 SQLite projection 后，立即触发 conversation patch 和 thread message patch。
  - AWiki Me 收到 realtime update 后，把同一条消息预热到 ChatThreadState 的所有等价 alias key，避免“缓存到 A key，ChatView 监听 B key”。
  - 点击未读 / 新消息会话时，首屏只依赖内存 tail 或本地 SQLite 最近 20-50 条；`syncThreadAfter` 和 remote history 都是后台补齐，不阻塞首屏。
  - `localHistory` 热路径减少 Dart → Rust → SQLite 的成本：首屏 limit 降低，并缓存 owner DID；只有指标仍不达标时再走更大的 `loadThreadTailSnapshot` 契约变更。
- 非目标：
  - 不修改 message-service 的 `sync.delta` / `sync.thread_after` 服务端契约。
  - 不让 App 读写 global reliable checkpoint、`since_event_seq` 或 raw `/im/rpc`。
  - 不把 AWiki Me 的 presentation overlay 字段下沉到 SDK core DTO。
  - 不在 Mac 平台执行 Linux E2E 配置或安装 Linux-only 依赖。
- 完成标准：
  - `watchConversationPatches` 与 `watchThreadPatches` 能收到 realtime incoming 对应 patch。
  - 新消息到达后，打开对应会话的首屏命中 memory tail 或本地 SQLite tail；remote reconcile 失败不得清空已显示消息。
  - 单元 / 集成 / E2E 性能门禁覆盖“CLI 发送到 App 后点开新消息首屏可见”的指标。
  - 受影响文档、测试和执行台账同步更新；每个步骤一个聚焦 commit，最后完成全局 Review 与整体验证。

## 2. Harness 上下文

| 来源 | 作用 |
|---|---|
| `awiki-harness/AGENTS.md` | 多仓库任务入口、权威来源和完成标准。 |
| `awiki-harness/README.md` | Harness 控制面定位与读取顺序。 |
| `awiki-harness/context/00-context-map.md` | 将任务路由到 Client Architecture、Message Flow、System Test。 |
| `awiki-harness/context/02-repo-map.md` | 确认最新端侧权威仓库是 `awiki-cli-rs2`，App 是 `awiki-me`。 |
| `awiki-harness/context/03-cross-repo-architecture.md` | 确认 `im-core` 拥有 local projection / patch stream / checkpoint，AWiki Me 只经 SDK 使用。 |
| `awiki-harness/context/20-rules-index.md` | 路由到文档、架构、AI coding、验证规则。 |
| `awiki-harness/context/30-tools-env.md` | 提供 `awiki-cli-rs2`、`awiki-me`、`awiki-system-test` 验证命令。 |
| `awiki-harness/context/40-verification.md` | 本任务属于 L2 cross-repo 行为变更，需要 affected repo checks + focused system/E2E。 |
| `awiki-harness/context/50-task-workflow.md` | 非平凡任务的 context、analysis、solution、verification 沉淀要求。 |
| `awiki-harness/context/nodes/client-architecture.node.md` | App 不直连 wire / checkpoint；snapshot 和 patch 来自 committed local projection。 |
| `awiki-harness/context/nodes/message-flow.node.md` | `sync_thread_after` 是 thread-local 补新；realtime hint 不推进 checkpoint。 |
| `awiki-harness/context/nodes/system-test.node.md` | message sync focused suite 与 remote `awiki.info` gate。 |
| `awiki-harness/context/repo-profiles/awiki-cli-rs2.md` | `im-core`、Dart SDK、patch stream、local state 的仓库职责。 |
| `awiki-harness/context/repo-profiles/awiki-me.md` | AWiki Me 的 UI/state/cache 归属、Flutter 验证入口。 |
| `awiki-harness/context/repo-profiles/awiki-system-test.md` | 可靠同步相关系统测试入口。 |
| `awiki-harness/context/repo-profiles/message-service.md` | 确认本次不改服务端 sync/read-state API。 |
| `awiki-harness/features/message-sync-reliability.md` | 可靠同步端到端 feature map：patch 只能在 local projection commit 后发。 |
| `awiki-harness/rules/documentation-principles.md` | 行为、契约和验证期望变化时同步更新文档。 |
| `awiki-harness/rules/architecture-principles.md` | 依赖方向、source-of-truth 和 E2EE / checkpoint 边界。 |
| `awiki-harness/rules/ai-coding-rules.md` | 先分析影响面，再做小而可回滚的变更。 |
| `awiki-harness/rules/verification-policy.md` | L2 证据、security review 和未运行项报告要求。 |

## 3. 影响分析

| 领域 / 仓库 / 模块 | 影响 | 权威文档或代码 |
|---|---|---|
| Rust realtime local projection / `awiki-cli-rs2` | P0：realtime incoming 写库后触发 conversation 和 thread patch。 | `awiki-cli-rs2/crates/im-core/src/realtime/runner.rs`, `awiki-cli-rs2/crates/im-core/src/core/client.rs`, `awiki-cli-rs2/docs/architecture/im-core-sdk-architecture.md` |
| `im-core` runtime store | patch stream 由 committed local projection 驱动；需要覆盖 realtime incoming。 | `awiki-cli-rs2/crates/im-core/src/internal/runtime_store/conversation_store.rs`, `awiki-cli-rs2/crates/im-core/src/internal/runtime_store/message_store.rs` |
| Dart / Flutter SDK 文档 | 行为说明需要补充 realtime projection commit 后也会产生 patch。 | `awiki-cli-rs2/docs/flutter-sdk/awiki-im-core-flutter-sdk.md`, `awiki-cli-rs2/docs/api/im-core-interface/04-message-interface.md` |
| AWiki Me realtime provider | P1：`_applyRealtimeUpdate` 后预热 ChatThreadState aliases。 | `awiki-me/lib/src/presentation/app_shell/providers/app_runtime_provider.dart`, `awiki-me/lib/src/presentation/chat/chat_provider.dart` |
| AWiki Me Chat open path | P2：点击路径 memory/local-first，network sync 后台化；remote history 仅空本地兜底。 | `awiki-me/lib/src/presentation/chat/chat_provider.dart`, `awiki-me/lib/src/presentation/conversation_list/conversation_list_page.dart` |
| AWiki Me local history adapter | P3：首屏 limit 降低、owner DID 缓存、保留 snapshot API 决策 gate。 | `awiki-me/lib/src/application/messaging_service.dart`, `awiki-me/lib/src/application/ports/message_core_port.dart`, `awiki-me/lib/src/data/im_core/awiki_im_core_message_adapter.dart` |
| AWiki Me tests / E2E performance | 新增 alias、local-first、limit、点击新消息首屏指标。 | `awiki-me/tests/unit/`, `awiki-me/tests/e2e/runner.dart`, `awiki-me/tests/e2e/flutter/desktop_cli_peer/flows/performance_flow.dart` |
| AWiki System Test | focused message sync / WebSocket / thread-after gate；主要用于最终验证，不预计改服务端测试契约。 | `awiki-system-test/tests_v2/message_service/`, `awiki-system-test/docs/message-sync-reliability-system-tests.md` |
| message-service | 本次预计无代码变更；作为 remote E2E 依赖和 contract 边界。 | `message-service/docs/api/ANP-client-server-api-sync.md`, `message-service/docs/api/ANP-client-server-api-read-state.md` |
| 平台 / E2E 配置 | 在 Mac 主机必须使用 macOS E2E config，不运行 Linux config。 | `codex.md`, `awiki-me/codex.md`, `awiki-me/tests/e2e/configs/e2e.codex-macos-allowed.local.yaml` |

### 当前工作区观察

- `awiki-cli-rs2`：`feature/perf/message-sync-opt-0627`，Step 01 已提交 `94285c8 fix(im-core): emit patches for realtime incoming projection`。
- `awiki-me`：`feature/perf/message-sync-opt-0627`，最新已观察提交 `0a0d10b feat(app): gate conversation pagination performance`；执行前必须重新检查 `git status`，当前可能有 `codex.md` 本地修改，不能覆盖或误合并非本步骤变更。
- `awiki-system-test`：`release/0526`，最新已观察提交 `01bb3ed fix: skip local db cleanup in remote system tests`。

## 4. 假设与开放问题

### 假设

- message-service 已能发送包含消息主体和 readonly sync hint 的 realtime notification；本计划不要求改变服务端事件格式。
- `im-core` 的 `emit_committed_local_message_projection(reason)` 已可同时触发 conversation store 和 message store；P0 只需在 realtime local projection 成功 commit 后调用或补齐封装。
- AWiki Me 当前导航进入 ChatView 不等待 `openConversation` 的 Future；慢点主要来自 ChatThreadState 没命中正确 key、本地读取过重或 remote fallback 被过早触发。
- 首屏 50 条消息可以满足当前 UX；更老消息继续走分页 / 后台补齐。
- owner DID 在单个 `AwikiImCoreMessageAdapter` 当前 client 生命周期内稳定；logout / client switch 时必须自然失效或显式清空缓存。

### 开放问题

- P3 是否引入 `loadThreadTailSnapshot` 专门接口：默认不在第一轮实现，因为它是跨 Rust-Dart-FFI-public API 扩展；只有 Step 04 验证显示 limit + owner DID cache 后仍明显慢，才通过 Plan 变更记录纳入。
- 首屏 limit 采用 30 还是 50：默认 50，兼顾长消息场景和低风险；若 E2E 指标仍偏高，可在 Step 04 Review 中降到 30 并记录理由。
- thread alias 的最终 canonical 规则是否要统一为 alias registry：本计划先做最小可验证 alias fan-out，避免新增持久缓存事实源；如果 fan-out 复杂度过高，再通过 Plan 变更升级为 registry。

## 5. 总体设计方法

- 设计边界：
  - 最底层由 `im-core` 负责 realtime incoming 的本地 SQLite projection 和 runtime patch；App 不直接读 SQLite、不推进 checkpoint。
  - 中间层 Dart adapter 只减少调用成本，不改变 owner / thread / checkpoint 语义。
  - 上层 AWiki Me provider 只维护 UI 内存 tail 和 ChatThreadState key 命中，不新增主数据缓存。
- 关键决策：
  1. P0 是必需的根因修复：没有 committed projection patch，上层只能靠 realtime event 或后续 sync，无法获得稳定本地-first 入口。
  2. P1 解决 alias key 错配：收到消息时同时预热 `conversation.threadId`、`message.threadId`、direct DID / handle canonical key、group id / group DID key。
  3. P2 保证点击路径的优先级：memory tail → local SQLite tail → background `syncThreadAfter` → remote history 兜底；unread 不再等价于“必须阻塞 remote history”。
  4. P3 有必要，但它不是最大瓶颈；按低风险版本实现 limit + owner DID cache，避免提前扩大 FFI public API。
- 兼容性策略：
  - patch stream 是既有 API 行为增强，不改变 DTO shape。
  - App alias prewarm 只增加内存 state 写入，不改变会话列表 projection ownership。
  - `syncThreadAfter` 仍 thread-local，不推进账号级 checkpoint。
  - remote history fallback 保留，但只在本地确实没有可渲染消息时触发。
- 数据、协议、配置或迁移策略：
  - 不新增服务端 schema / protocol。
  - Rust 本地 projection 写入后才 emit patch；写库失败时不发 authoritative patch。
  - 不新增平台配置；E2E 只明确按宿主平台选择现有 config。
- 风险控制：
  - 每步独立测试和 commit，避免跨层大 diff。
  - 对 patch 发射点做“commit 后 emit”Review，避免内存 store 比 SQLite 领先。
  - 对 alias fan-out 做去重和消息 merge 去重测试，避免重复消息。
  - 对 remote history fallback 做 fake service 测试，避免未读会话首屏被远端阻塞。

## 6. 任务拆分

| Step | 标题 | 依赖 | 产出 | 小 Plan 文档 | Commit gate | 状态 |
|---|---|---|---|---|---|---|
| 01 | Rust realtime projection 写库后发 patch | 无 | `im-core` realtime incoming 触发 conversation/thread patch，含 Rust 测试和 SDK docs。 | [steps/01-rust-realtime-projection-patches.md](steps/01-rust-realtime-projection-patches.md) | 必须 | done |
| 02 | Flutter realtime thread-tail alias 预热 | Step 01 行为可独立测试；代码上可在 Step 01 后做 | AWiki Me 收到 realtime 后把消息预热到所有等价 ChatThreadState key。 | [steps/02-flutter-thread-tail-prewarm.md](steps/02-flutter-thread-tail-prewarm.md) | 必须 | done |
| 03 | 点击路径 local-first，网络补同步后台化 | Step 02 | 打开会话首屏使用 memory/local tail，`syncThreadAfter` 和 remote history 不阻塞。 | [steps/03-local-first-open-path.md](steps/03-local-first-open-path.md) | 必须 | done |
| 04 | 降低 Flutter → Rust → SQLite 首屏开销 | Step 03 | 首屏 `localHistory` limit 降低，owner DID 缓存；保留 snapshot API 决策 gate。 | [steps/04-local-history-tail-cost.md](steps/04-local-history-tail-cost.md) | 必须 | pending |
| 05 | 集成验证、性能门禁和文档收口 | Step 01-04 | E2E 指标覆盖新消息点击首屏，系统测试 / App E2E / 文档证据完整。 | [steps/05-integration-e2e-docs.md](steps/05-integration-e2e-docs.md) | 若修改文件则必须 | pending |

## 7. 执行台账

状态取值：`pending`、`in_progress`、`review`、`blocked`、`committed`、`done`。

| Step | 状态 | 分支 | 开始时间 | 完成时间 | Commit | Review 证据 | 验证证据 | 下一步 |
|---|---|---|---|---|---|---|---|---|
| 01 | done | `awiki-cli-rs2: feature/perf/message-sync-opt-0627` | 2026-06-28 20:28:56 CST | 2026-06-28 21:00:05 CST | `awiki-cli-rs2@94285c8` | Review 确认 emit 只在 `messages` 写入和 group/contact upsert 全部成功后执行；未新增 checkpoint 写入；patch DTO/API shape 未改变；新增 subscriber 测试不扩大 public API。 | `cargo fmt -p im-core`; `CARGO_BUILD_JOBS=1 cargo test -p im-core --locked realtime -- --nocapture` 通过 24 个 lib realtime 测试并通过 realtime integration tests；`CARGO_BUILD_JOBS=1 cargo test -p im-core --locked patch -- --nocapture` 通过 patch 过滤测试；`CARGO_BUILD_JOBS=1 cargo test -p im-core --locked` 通过；`--features blocking` focused patch 测试通过；docs grep 已确认。 | 开始 Step 02：Flutter realtime thread-tail alias 预热。 |
| 02 | done | `awiki-me: feature/perf/message-sync-opt-0627` | 2026-06-28 21:03:43 CST | 2026-06-28 21:22:50 CST | `awiki-me@e34f996` | Review 确认 `ChatThreadsController.applyRealtimeUpdate` 改为有序去重 alias fan-out；覆盖已有 opened state key、`conversation.threadId`、`message.threadId`、`visibilityKeys`、direct DID/handle/direct-did/direct aliases、handle 打开路径 `dm:pending:*`、group raw id 与 `group:` canonical key；每个 alias 仍走 `_mergeMessages` 去重；未新增持久缓存、checkpoint 或 raw sync payload。Review 中发现 handle alias 不应生成当前打开路径不会使用的 `dm:<owner>:<handle>`，并补齐 `dm:pending:<handle>`。 | `dart format lib/src/presentation/chat/chat_provider.dart tests/unit/app_runtime_notification_test.dart tests/unit/chat_provider_open_test.dart` 通过；`git diff --check` 通过；`flutter test tests/unit/app_runtime_notification_test.dart` 通过 19 个测试；`flutter test tests/unit/chat_provider_open_test.dart` 通过 50 个测试；`dart run tests/unit/runner.dart` 通过，最终 `+678: All tests passed!`；`dart analyze` 仅失败于既有无关 warning：`tests/e2e/flutter/desktop_cli_peer/support/cli_peer_process.dart:192:5 unused_element _groupCountFromCliOutput`。 | 开始 Step 03：点击路径 local-first，网络补同步后台化。 |
| 03 | done | `awiki-me: feature/perf/message-sync-opt-0627` | 2026-06-28 21:26:45 CST | 2026-06-28 21:35:18 CST | `awiki-me@b6d8c1f` | Review 确认 `openConversation` 仍不 await 后台工作；memory tail 命中直接记录 `chat.open.first_paint` 并只后台 `syncThreadAfter`；空内存才读 local history；local history 命中后不再因 unreadCount 或 lastMessageAt 触发 remote history；local 空或失败时 remote fallback 保留且 `force=true`；未新增 checkpoint、raw sync payload 或持久缓存。Review 中将旧 pending 回补测试从 remote history 改为 thread-after，保持新语义一致。 | `dart format lib/src/presentation/chat/chat_provider.dart tests/unit/chat_provider_open_test.dart` 通过；`git diff --check` 通过；`flutter test tests/unit/chat_provider_open_test.dart` 通过 50 个测试；`flutter test tests/unit/app_runtime_notification_test.dart` 通过 19 个测试；`dart run tests/unit/runner.dart` 通过，最终 `+678: All tests passed!`；`dart analyze` 仅失败于既有无关 warning：`tests/e2e/flutter/desktop_cli_peer/support/cli_peer_process.dart:192:5 unused_element _groupCountFromCliOutput`。 | 开始 Step 04：降低 Flutter → Rust → SQLite 首屏开销。 |
| 04 | pending | `awiki-me: feature/perf/message-sync-opt-0627` | 待填 | 待填 | 待填 | 待填 | 待填 | 等 Step 03 done |
| 05 | pending | `awiki-me: feature/perf/message-sync-opt-0627`; `awiki-system-test: release/0526` 如需测试文档 | 待填 | 待填 | 待填 | 待填 | 待填 | 等 Step 01-04 done |
| Final | pending | 全部受影响仓库 | 待填 | 待填 | 若有最终收口修改则填 | 待填 | 待填 | 所有步骤 done 后执行全局 Review |

## 8. Codex Goal 执行协议

- 将本 Plan 作为执行进度的唯一事实来源。
- 启动或恢复前，读取本 Plan、当前小 Plan、执行台账和当前 `git status --short --branch`。
- 同一时间只执行一个步骤；本计划没有标记任何步骤为并行安全。
- 恢复时，从第一个状态不是 `done` 的步骤继续。
- 每个步骤依次执行：标记 `in_progress`、实现、验证、Review、修复 Review 发现、提交、记录证据、标记 `done`。
- 上一个依赖步骤的完成工作未提交前，不要开始下一个依赖步骤。
- 改变范围、顺序、验收标准、公开契约、数据模型或验证策略前，先更新本 Plan 的变更记录。
- 执行 `awiki-me` E2E 前必须先识别宿主平台：`uname -s=Darwin` 时使用 macOS config，例如 `tests/e2e/configs/e2e.codex-macos-allowed.local.yaml`；不要使用默认 Linux config，也不要安装 Linux-only 依赖。
- 任何日志和证据不得包含 token、私钥、JWT、完整 DID 或消息正文；只记录耗时、数量、短 hash 或已脱敏标识。

## 8.1 Codex Goal 提示词

下面这段提示词用于启动后续 Codex Goal；最终回复中也会输出一份便于复制：

```text
请以 `awiki-me/docs/plan/20260628-chat-open-realtime-tail/plan.md` 为唯一规划入口，按文档执行完整实现。

开始前先读取：
- `awiki-me/docs/plan/20260628-chat-open-realtime-tail/plan.md`
- 当前第一个未 done 的 Step 文档
- 主 Plan 的执行台账、Codex Goal 执行协议、验证策略、Blocked 处理和 Plan 变更记录
- 当前 `git status --short --branch`

请从第一个状态不是 `done` 的步骤开始，一次只执行一个步骤。每步都要按对应小 Plan 实现、验证、Review、修复或记录 Review 发现，然后创建一个聚焦 commit，并回填主 Plan 执行台账和 Step 执行状态。需要改变范围、顺序、验收标准、公开契约、数据模型或验证策略时，先更新 Plan 变更记录。

所有步骤完成后，执行最终全局 Review 和整体验证，记录实际命令、通过/失败/跳过数量、失败或跳过原因、剩余风险和最终工作区状态。

核心注意点：Rust realtime patch 只能在 SQLite local projection commit 成功后发；App 不读写 reliable checkpoint 或 raw sync payload；打开会话首屏必须 memory/local-first，网络补同步后台化；Mac 平台 awiki-me E2E 必须用 macOS config，不能跑 Linux config；不要覆盖 `awiki-me/codex.md` 等已有本地修改。
```

## 9. 小 Plan 摘要

### Step 01：Rust realtime projection 写库后发 patch

- 小 Plan：[steps/01-rust-realtime-projection-patches.md](steps/01-rust-realtime-projection-patches.md)
- 目标：`project_realtime_message_received_async` / blocking counterpart 写入本地 projection 后触发 `emit_committed_local_message_projection("realtime_incoming")` 或等效封装。
- 设计方法：严格 commit 后 emit；projection 失败不发 patch；不推进 reliable checkpoint。
- 实现方法：修改 realtime runner，补 Rust 测试覆盖 conversation/thread patch subscriber。
- 路径：`awiki-cli-rs2/crates/im-core/src/realtime/runner.rs`、runtime store 测试、SDK docs。
- 验证方式：focused cargo tests + docs grep；必要时运行 `cargo test -p im-core --locked`。
- Review 环节：检查 patch 发射时序、重复 patch、thread kind/id 匹配、安全日志。
- Commit 要求：`fix(im-core): emit patches for realtime incoming projection`。
- 风险：异步写入 group/contact 后才 emit；如果其中失败则不发 authoritative patch，需要 warning 和测试。

### Step 02：Flutter realtime thread-tail alias 预热

- 小 Plan：[steps/02-flutter-thread-tail-prewarm.md](steps/02-flutter-thread-tail-prewarm.md)
- 目标：`AppRuntimeProvider._applyRealtimeUpdate` 或 `ChatThreadController.applyRealtimeUpdate` 对所有 alias key 预热同一消息。
- 设计方法：内存 fan-out + merge 去重；不新增持久主数据源。
- 实现方法：抽取 alias 计算函数，覆盖 conversation/thread/direct/group 多 key。
- 路径：`awiki-me/lib/src/presentation/chat/chat_provider.dart`、`awiki-me/lib/src/application/thread_id_utils.dart`、unit tests。
- 验证方式：`dart run tests/unit/runner.dart --name ...` 或 repo 现有 focused test 命令；最终跑完整 unit runner。
- Review 环节：检查 alias 去重、direct handle/DID 归一、group key、重复消息和 Agent control payload。
- Commit 要求：`fix(app): prewarm realtime thread aliases`。
- 风险：fan-out 过宽可能增加内存 state；通过只写入非空、去重 key 和单条 tail merge 控制。

### Step 03：点击路径 local-first，网络补同步后台化

- 小 Plan：[steps/03-local-first-open-path.md](steps/03-local-first-open-path.md)
- 目标：点开会话先渲染 memory/local tail；`syncThreadAfter` 和 remote history 只后台补，不影响首屏。
- 设计方法：memory tail 命中则跳过 loading；localHistory 只读小 page；remote history 仅本地空或本地读失败兜底。
- 实现方法：调整 `_openConversationLocalFirst`、`_shouldLoadHistory` / 新增 `_shouldLoadRemoteHistory`，增加测试。
- 路径：`awiki-me/lib/src/presentation/chat/chat_provider.dart`、`tests/unit/chat_provider_open_test.dart`。
- 验证方式：fake messaging service 断言 remote `loadHistory` 不在本地有消息时调用；unit runner。
- Review 环节：检查未读清零、mark-read best effort、thread-after 后台错误处理、不会饿死 remote 兜底。
- Commit 要求：`fix(app): keep chat open first paint local-first`。
- 风险：本地空时仍要有兜底；需确保失败提示只在真正空本地时显示。

### Step 04：降低 Flutter → Rust → SQLite 首屏开销

- 小 Plan：[steps/04-local-history-tail-cost.md](steps/04-local-history-tail-cost.md)
- 目标：首屏 localHistory limit 降到 50，并缓存 owner DID，减少 `identity.current()` + FFI + map 成本。
- 设计方法：低风险先优化现有 API；`loadThreadTailSnapshot` 作为指标失败后的 Plan 变更候选。
- 实现方法：传入 `limit: 50`，在 adapter 中增加 client 生命周期内 owner DID cache / helper，补测试。
- 路径：`awiki-me/lib/src/data/im_core/awiki_im_core_message_adapter.dart`、ports/service tests、performance docs。
- 验证方式：unit tests 验证 limit 和 identity.current 调用次数；性能 E2E 在 Step 05 验证。
- Review 环节：检查 session switch/logout 缓存失效、owner DID 不串号、接口兼容。
- Commit 要求：`perf(app): reduce local history first-paint overhead`。
- 风险：owner DID cache 不当会跨账号；必须绑定 current client 或清理点。

### Step 05：集成验证、性能门禁和文档收口

- 小 Plan：[steps/05-integration-e2e-docs.md](steps/05-integration-e2e-docs.md)
- 目标：把前四步串成可验证闭环，补新消息点击首屏指标和文档。
- 设计方法：E2E / performance 记录“CLI 发消息 → App 收到 realtime → 点击打开 → 首条消息可见”的时间；remote sync 系统测试作为服务契约 gate。
- 实现方法：扩展 `tests/e2e` performance flow / budget，更新 docs，运行 Mac config E2E。
- 路径：`awiki-me/tests/e2e/runner.dart`、`awiki-me/tests/e2e/flutter/desktop_cli_peer/flows/performance_flow.dart`、`awiki-me/docs/performance-tracing.md`。
- 验证方式：`awiki-me` unit/analyze/E2E performance，`awiki-cli-rs2` cargo tests，`awiki-system-test` remote focused suite。
- Review 环节：检查性能门禁是否稳定、Mac/Linux config 分流、文档是否准确。
- Commit 要求：若修改 E2E/docs，`test(app): gate realtime chat open performance`。
- 风险：remote `awiki.info` 未部署最新服务时 system-test 可能失败；需记录环境和失败原因，不放宽 contract。

## 10. Review 策略

- 每步骤 Review：实现完成后、commit 前进行，覆盖 correctness、regression、public contract、test、docs、security/privacy、compatibility。
- 全局 Review：所有步骤 done 后执行，检查跨 repo 一致性、未提交变更、Plan 台账、测试证据和剩余风险。
- 契约 / 安全 / 隐私 Review：确认不泄露消息正文、token、私钥、JWT；realtime hint 不推进 checkpoint；服务端仍不接触 E2EE 明文。
- 文档 Review：确认 `awiki-cli-rs2` SDK docs、`awiki-me` README / performance tracing、必要 Harness feature doc 与实际行为一致。

## 11. 验证策略

| 层级 | 命令 / 检查 | 预期证据 |
|---|---|---|
| Rust unit | `cd awiki-cli-rs2 && cargo test -p im-core --locked realtime` | realtime local projection patch 测试通过；如过滤名不匹配，记录实际命令。 |
| Rust broader | `cd awiki-cli-rs2 && cargo test -p im-core --locked`；最终可升级 `cargo test --workspace --locked` | `im-core` 相关回归通过；workspace 未跑时说明耗时或非影响原因。 |
| Dart unit | `cd awiki-me && dart run tests/unit/runner.dart` | alias prewarm、local-first open、limit/cache 相关测试通过。 |
| Dart analyze | `cd awiki-me && dart analyze` | 无新增 analyzer 错误。 |
| AWiki Me E2E performance | `cd awiki-me && dart run tests/e2e/runner.dart --case performance --config tests/e2e/configs/e2e.codex-macos-allowed.local.yaml`（Darwin） | 新增 realtime click-open 指标存在且预算通过；报告路径和 timings 记录到台账。 |
| AWiki System Test remote | `cd awiki-system-test && AWIKI_SYSTEM_TEST_MODE=remote E2E_DID_DOMAIN=awiki.info E2E_USER_SERVICE_URL=https://awiki.info E2E_MESSAGE_SERVICE_URL=https://awiki.info E2E_MESSAGE_SERVICE_WS_URL=wss://awiki.info/im/ws uv run --no-sync pytest tests_v2/message_service/test_sync_delta_local.py tests_v2/message_service/test_sync_thread_after_local.py tests_v2/message_service/test_ws_notifications.py tests_v2/message_service/test_read_watermark_local.py -q -rs` | focused sync/read-state/WS contract 通过；如远端部署未更新，记录失败和环境，不改弱断言。 |
| Docs / path | 使用脚本扫描 `awiki-me/docs/plan/20260628-chat-open-realtime-tail`、`awiki-cli-rs2/docs`、`awiki-me/docs` 中新增内容，确认没有本机绝对路径或本地 workspace 目录名前缀 | 生成计划和文档不含机器特定绝对路径；若命令覆盖仓库 docs，要排除历史既有内容并记录。 |
| Git hygiene | 各受影响仓库 `git status --short --branch` | 每步 commit 后无未解释的完成工作；已知本地修改需明确归属。 |

如果某个命令不能运行，必须在本 Plan 和对应 Step 文档记录原因、影响范围、替代证据和后续 owner。

## 12. 文档更新

- Harness 文档：若本次行为改变 message sync reliability feature map，则更新 `awiki-harness/features/message-sync-reliability.md`；若只是子仓库实现细节，可不改 Harness，但最终 Review 必须确认。
- 子仓库文档：
  - `awiki-cli-rs2/docs/architecture/im-core-sdk-architecture.md`：补充 realtime local projection 成功后 patch 行为。
  - `awiki-cli-rs2/docs/api/im-core-interface/04-message-interface.md` 或 `awiki-cli-rs2/docs/flutter-sdk/awiki-im-core-flutter-sdk.md`：如 public behavior 文档需要同步，补充 patch stream 语义。
  - `awiki-me/README.md`：如 local-first sync 行为说明需要更新，保持与实现一致。
  - `awiki-me/docs/performance-tracing.md`：新增点击新消息首屏、memory tail / local tail、background sync 指标说明。
- 本次生成的任务文档：`awiki-me/docs/plan/20260628-chat-open-realtime-tail/plan.md` 和 `awiki-me/docs/plan/20260628-chat-open-realtime-tail/steps/*.md` 作为执行事实来源。

## 13. Commit 计划

- Step 01 在 `awiki-cli-rs2` 创建一个聚焦 commit。
- Step 02、03、04 在 `awiki-me` 各创建一个聚焦 commit。
- Step 05 若修改 E2E/docs，在对应仓库创建一个聚焦 commit；若只运行验证，不创建 commit 但必须记录证据。
- 每个 commit 前记录 `git status` 和纳入文件；commit 后记录 commit hash 和 post-commit `git status`。
- 不要把所有步骤积累到一个大 commit。
- `awiki-me/codex.md` 如仍是执行前已有本地修改，除非该步骤明确更新 Mac E2E 记忆，否则不要纳入功能 commit；如需要纳入，必须在 Step Review 中说明原因。

## 14. Blocked 处理

| Blocker | Step | 证据 | 已尝试方案 | 影响范围 | 下一步决策 |
|---|---|---|---|---|---|
| 待填 | 待填 | 待填 | 待填 | 当前步骤 / 整体计划 | 待填 |

- 只有依赖允许且风险已记录时，才继续另一个 pending 步骤。
- 只有没有安全假设、回退方案或独立下一步时，才询问用户。
- 对远端 `awiki.info` 部署未更新、账号注册限流、E2E 平台依赖等外部 blocker，必须记录实际命令、失败摘要、环境和可替代本地证据。

## 15. Plan 变更记录

| 日期 | 变更 | 原因 | 影响步骤 | 是否需要 Review |
|---|---|---|---|---|
| 2026-06-28 | 初始计划 | 用户要求制定计划并实现 P0-P3 全部工作。 | Step 01-05 | 是 |

## 16. 风险与回滚

| 风险 | 缓解措施 | 回滚 / 回退方案 |
|---|---|---|
| Rust patch 在 SQLite commit 前发出，导致 UI 显示未持久化消息 | 只在 `store_messages` / group / contact upsert 全部 `await?` 后 emit；测试写入失败不发 patch。 | 回滚 Step 01 commit，恢复仅 realtime event + sync 路径。 |
| alias fan-out 重复插入消息 | `_mergeMessages` 依赖 remoteId/localId/pending index 去重；新增测试覆盖同一消息多 key。 | 回滚 Step 02 或收窄 alias 计算。 |
| remote history 兜底过度延后导致本地空时无消息 | `_shouldLoadRemoteHistory` 明确本地空 / 本地失败时立即后台兜底，并允许 loading/error。 | 回滚 Step 03 中 remote fallback 判定。 |
| owner DID cache 跨账号串号 | cache 绑定 current client 或 session switch 清理；测试模拟两次 identity。 | 关闭 owner DID cache，只保留 limit 优化。 |
| Mac E2E 误用 Linux config | Plan 和 Step 05 明确 `uname -s` 分流；命令必须使用 macOS config。 | 停止错误 E2E，重新用 macOS config 跑并记录。 |
| `loadThreadTailSnapshot` 未实现被认为 P3 不完整 | 本计划明确 P3 首轮实现 limit + owner DID cache；只有指标仍失败才通过 Plan 变更纳入 snapshot API。 | 若用户要求强制 snapshot，则更新 Plan，拆新 Step，补 Rust-Dart-FFI 契约和测试。 |

## 17. 最终全局 Review 与整体验证

- 触发条件：Step 01-05 全部完成、Review、验证并按要求提交后执行。
- Review 范围：`awiki-cli-rs2`、`awiki-me`、可能的 `awiki-system-test` 变更；SDK / App public behavior；patch stream 契约；local-first click path；E2E 配置；文档；执行台账；剩余风险；所有相关 `git status`。
- 重点关注：
  - realtime incoming 从最底层到 UI 的链路是否连续：service notification → Rust local projection → patch stream → Dart mapping → App alias prewarm → ChatView first paint → background sync。
  - 任何 App 代码是否绕过 SDK 读 SQLite、读写 checkpoint 或拼 raw sync payload。
  - remote history 是否真的只作为本地无数据兜底。
  - 性能门禁是否覆盖“收到远端新消息后点开”的路径，而不只是手动调用 `syncThreadAfter`。
  - Mac 平台是否使用 Mac config。
- 整体验证命令 / 检查：按第 11 节执行，并记录通过 / 失败 / 跳过数量、报告路径、失败原因和最终工作区状态。
- Review 发现：待执行时填写。
- 已修复问题：待执行时填写。
- 剩余风险：待执行时填写。
- 最终证据：待执行时填写。
- 最终 `git status`：待执行时填写。
- 如果本阶段修改文件：记录 Review、验证和最终集成 commit。
