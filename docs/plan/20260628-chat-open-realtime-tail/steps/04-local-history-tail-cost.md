# Step 04：降低 Flutter → Rust → SQLite 首屏开销

主 Plan：[../plan.md](../plan.md)  
Step index：04  
状态：draft

## 1. 执行状态

| 字段 | 值 |
|---|---|
| Status | pending |
| Branch | `awiki-me: feature/perf/message-sync-opt-0627` |
| Started | 待填 |
| Completed | 待填 |
| Commit | 待填 |
| Review evidence | 待填 |
| Verification evidence | 待填 |
| Next action | 降低 localHistory 首屏 limit，并缓存 owner DID。 |

状态取值：`pending`、`in_progress`、`review`、`blocked`、`committed`、`done`。

## 2. 目标

- 结果：减少会话首屏本地读取的 Dart → Rust → SQLite 热路径成本。
- 用户 / 系统可见行为：当 memory tail 没命中但 SQLite 本地已有消息时，首屏读取更快，且不会每次都重复 `identity.current()` 和映射 100 条消息。
- 非目标：
  - 默认不新增 `loadThreadTailSnapshot` public API；除非 Step 04 指标 / Review 证明现有 API 优化不足。
  - 不改变 remote `loadHistory` 默认语义。
  - 不牺牲账号隔离或 owner DID 正确性。
- 完成标准：
  - Chat open 首屏 local history limit 从默认 100 降到 50（或 Review 记录后降到 30）。
  - `AwikiImCoreMessageAdapter.loadLocalHistory` / 相关热路径能复用 current owner DID，避免同一 client 生命周期内重复 `identity.current()`。
  - owner DID cache 在 client switch / logout 时不会串号。
  - unit tests 覆盖 limit 传递和 owner DID cache 调用次数 / 失效。

## 3. 设计方法

- 设计边界：先优化 AWiki Me adapter 和调用参数，不扩大 Rust-Dart-FFI public surface。
- 核心决策：
  - `_loadLocalHistory` 调用 `localMessaging.loadLocalHistory(..., limit: 50)`；thread patch repair 仍可保持 100，避免 repair 窗口过小。
  - 在 `AwikiImCoreMessageAdapter` 内增加 private helper，例如 `_currentOwnerDid(client)`，按当前 `client` 或 runtime generation 缓存 DID。
  - 如果 runtime 没有 generation，可将 cache 绑定 adapter 当前 client identity object / DID 字符串，并在 `withCurrentClient` 返回不同 client 时重新读取。
  - `loadHistory` 是否复用 owner DID cache 由 Review 决定；优先覆盖 `loadLocalHistory` 和 `watchThreadPatches` / `repairThreadStore` 这些 first paint / patch hot path。
- 契约 / API / 数据流：
  - public `LocalHistoryMessagingService.loadLocalHistory` 已支持 `limit` optional 参数；优先只改变调用参数。
  - owner DID 仍来自 SDK `identity.current()`，只是缓存读取结果，不由 App 手写 owner。
- 兼容性：保持接口默认 limit=100 不变，避免影响其他调用者；只在 chat open first paint 传 50。
- 迁移策略：无数据迁移。
- 风险控制：缓存必须随 client / session 变化失效；测试模拟 owner 切换。

## 4. 实现方法

1. 在 `awiki-me` 执行 `git status --short --branch`，确认 Step 03 已提交且没有无关完成工作。
2. 阅读：
   - `awiki-me/lib/src/presentation/chat/chat_provider.dart`
   - `awiki-me/lib/src/application/ports/message_core_port.dart`
   - `awiki-me/lib/src/application/messaging_service.dart`
   - `awiki-me/lib/src/data/im_core/awiki_im_core_message_adapter.dart`
   - `awiki-me/lib/src/data/im_core/awiki_im_core_runtime.dart`
   - `awiki-me/tests/unit/data/im_core/awiki_im_core_message_adapter_test.dart` 或现有 adapter tests。
3. 增加常量：例如 `static const int _initialLocalHistoryLimit = 50;`，在 `_loadLocalHistory` 首屏调用传入。
4. 检查其他调用：
   - thread patch `watchThreadPatches(limit: 100)` 可保持 100。
   - repair store 可保持 100，避免 repair 后缺消息。
   - remote `loadHistory` 默认可保持 100，除非 Step 03 fallback 也需要更快首屏；若改动，必须记录理由。
5. 实现 owner DID cache：
   - 在 `AwikiImCoreMessageAdapter` 中新增 private 字段保存 owner DID 和 client identity marker。
   - helper 内如果 marker 命中，直接返回缓存；否则调用 `client.identity.current()` 并更新缓存。
   - 如果 runtime 有 logout / clear 钩子，接入清理；否则确保 marker 不同会重新读取。
   - 所有日志仍只记录耗时和数量，不输出完整 DID。
6. 更新 tests：
   - fake client 记录 `localHistory` 接收的 limit，断言 Chat open 使用 50。
   - fake identity 记录 `identity.current()` 调用次数，连续两次 localHistory / patch map 只调用一次或按设计减少。
   - 模拟 current client / identity marker 变化，断言重新读取 owner DID。
7. 决策 gate：
   - 如果实现中发现 owner DID cache 需要大改 runtime lifecycle 或存在串号风险，先只做 limit 降低，并在 Plan 变更记录说明 cache 延后；但因为用户要求 P3，必须至少给出可验证的成本下降证据。
   - 只有当 E2E / unit 指标显示仍不满足目标时，新增 Plan 变更把 `loadThreadTailSnapshot` 拆为新 Step，覆盖 Rust-Dart-FFI docs/tests/codegen。
8. 运行验证，Review，commit。

## 5. 路径

| 仓库 / 模块 / 文件 | 计划变更 | 备注 |
|---|---|---|
| `awiki-me/lib/src/presentation/chat/chat_provider.dart` | 首屏 local history limit 传 50；必要时记录 perf fields。 | P3 调用侧。 |
| `awiki-me/lib/src/application/ports/message_core_port.dart` | 原则上不改；确认已有 limit 参数。 | 如新增 snapshot API 才改。 |
| `awiki-me/lib/src/application/messaging_service.dart` | 原则上不改；确认 limit 透传。 | 保持兼容。 |
| `awiki-me/lib/src/data/im_core/awiki_im_core_message_adapter.dart` | owner DID cache helper；复用到 localHistory / thread patch mapping。 | P3 adapter 侧。 |
| `awiki-me/lib/src/data/im_core/awiki_im_core_runtime.dart` | 只读或接入 cache invalidation。 | 防止 session switch 串号。 |
| `awiki-me/tests/unit/application/messaging_conversation_service_test.dart` | 如 port/service 行为涉及 tests，可更新。 | 视实际影响。 |
| `awiki-me/tests/unit/data/im_core/` | 增加 / 更新 adapter tests。 | 验证 limit/cache。 |
| `awiki-me/tests/unit/chat_provider_open_test.dart` | 断言 open path 传递 limit。 | 与 Step 03 测试衔接。 |
| `awiki-me/docs/performance-tracing.md` | Step 05 或本步骤更新 local_history limit/cache 说明。 | 文档同步。 |

## 6. 依赖

- 前置步骤：Step 03 完成，确保 localHistory 仅在 memory tail 不命中时用于首屏。
- 外部文档或决策：主 Plan 对 P3 的低风险实现决策。
- 环境前提：Dart unit tests 和 analyzer 可运行。

## 7. 验收标准

- [ ] chat open 首屏 `loadLocalHistory` 显式 limit 为 50 或 Review 认可的 30。
- [ ] adapter owner DID cache 减少重复 `identity.current()`。
- [ ] client / session switch 不复用旧 owner DID。
- [ ] 不改变 public SDK DTO 或 checkpoint 语义。
- [ ] unit tests 覆盖 limit、cache、失效。
- [ ] 如未实现 `loadThreadTailSnapshot`，Plan / Review 明确记录“为何当前 P3 已通过低风险优化满足，何时升级”。
- [ ] Review 发现已经修复或明确记录。
- [ ] 本步骤在进入下一步之前已经创建聚焦 commit。

## 8. 验证方式

| 检查项 | 命令 / 方法 | 预期证据 |
|---|---|---|
| Focused adapter tests | `cd awiki-me && dart run tests/unit/runner.dart --name im_core_message_adapter` | owner DID cache / limit tests 通过。 |
| Focused chat tests | `cd awiki-me && dart run tests/unit/runner.dart --name local_history` | chat open limit tests 通过。 |
| Full unit | `cd awiki-me && dart run tests/unit/runner.dart` | 单元回归通过。 |
| Analyze | `cd awiki-me && dart analyze` | 无新增 analyzer 错误。 |
| Performance log check | 检查 `chat.local_history.service` / `im_core_messages.local_history_native` fields 包含 limit=50 | 日志能证明 first paint limit 降低，且不含敏感信息。 |
| Git hygiene | `cd awiki-me && git status --short --branch` | commit 前后状态记录完整。 |

如果某个命令不能运行，记录原因、影响和替代证据。

## 9. Review 环节

- Review 时机：本步骤代码实现完成后、commit 前。
- Review 重点：
  - limit 降低是否只影响首屏，不影响 repair / remote fallback 完整性。
  - owner DID cache 是否绑定 client/session，不跨账号。
  - 是否仍通过 SDK identity 获取 owner，而不是 App 手写 DID。
  - 是否没有引入 `loadThreadTailSnapshot` 半成品 API。
  - 性能日志是否脱敏。

| Review 项 | 结果 | 备注 |
|---|---|---|
| 发现问题 | 待填 | 待填 |
| 已修复问题 | 待填 | 待填 |
| 剩余风险 | 待填 | 待填 |
| 新增或缺失测试 | 待填 | 待填 |
| 已更新或缺失文档 | 待填 | 待填 |

## 10. Commit 要求

- Commit 时机：本步骤实现、验证、Review 都完成后。
- Commit 范围：只包含 AWiki Me P3 localHistory 成本优化代码、测试和必要文档。
- Commit 前状态：记录 `cd awiki-me && git status --short --branch`。
- 纳入文件：记录本步骤 commit 包含的文件。
- Commit 后证据：记录 commit hash 和 commit 后 `git status`。
- 遗留未提交变更：必须记录原因以及为什么安全。
- 建议消息：`perf(app): reduce local history first-paint overhead`

## 11. Blocked 处理

| Blocker | 证据 | 已尝试方案 | 影响范围 | 下一步决策 |
|---|---|---|---|---|
| 待填 | 待填 | 待填 | 当前步骤 / 整体计划 | 待填 |

## 12. Plan 变更记录

| 日期 | 变更 | 原因 | 主 Plan 变更记录链接 |
|---|---|---|---|
| 2026-06-28 | 初始 Step 04 计划 | P3 降低首屏 Flutter→Rust→SQLite 成本。 | [../plan.md#15-plan-变更记录](../plan.md#15-plan-变更记录) |

## 13. 风险、回滚与后续文档

- 风险：limit 过低导致用户打开长会话只能看到太少上下文；owner DID cache 串号。
- 回滚 / 回退：回滚 owner DID cache，仅保留 limit；或恢复 limit=100。
- 后续文档：Step 05 更新性能追踪和 E2E budget；如果升级 `loadThreadTailSnapshot`，必须新增 Plan 变更、Rust-Dart-FFI docs/codegen/tests。
