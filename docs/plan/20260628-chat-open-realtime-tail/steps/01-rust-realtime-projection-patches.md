# Step 01：Rust realtime projection 写库后发 patch

主 Plan：[../plan.md](../plan.md)  
Step index：01  
状态：draft

## 1. 执行状态

| 字段 | 值 |
|---|---|
| Status | pending |
| Branch | `awiki-cli-rs2: feature/perf/message-sync-opt-0627` |
| Started | 待填 |
| Completed | 待填 |
| Commit | 待填 |
| Review evidence | 待填 |
| Verification evidence | 待填 |
| Next action | 修改 realtime local projection 后的 patch emit，并补测试。 |

状态取值：`pending`、`in_progress`、`review`、`blocked`、`committed`、`done`。

## 2. 目标

- 结果：`im-core` 在 realtime incoming 成功写入 SQLite local projection 后，触发 conversation patch 和 thread message patch。
- 用户 / 系统可见行为：AWiki Me 的 `watchConversationPatches` / `watchThreadPatches` 可以收到来自远端实时新消息的 committed patch，UI 不必等下一次 reliable sync 或 remote history 才更新本地投影。
- 非目标：
  - 不改变 message-service realtime notification wire 格式。
  - 不推进 reliable global checkpoint。
  - 不修改 patch DTO shape 或引入 App-only 字段。
- 完成标准：
  - async realtime incoming 路径在 `store_messages`、group/contact local upsert 成功后调用 `emit_committed_local_message_projection("realtime_incoming")` 或等价封装。
  - blocking realtime projection 路径保持一致，避免 CLI / test feature 下行为分裂。
  - 新增或更新 Rust 测试能证明 conversation patch 和 thread patch subscriber 收到 realtime incoming。
  - SDK / architecture docs 明确 realtime committed projection 会发 patch，失败 projection 不发 authoritative patch。

## 3. 设计方法

- 设计边界：patch stream 是 committed local projection 的加速层；只有底层 SQLite 写入成功后才能发 patch。
- 核心决策：
  - 在 `project_realtime_message_received_async` 中，所有必须落库的写入 `await?` 成功后统一调用 `client.emit_committed_local_message_projection("realtime_incoming")`。
  - blocking `project_realtime_message_received` 在 `apply_realtime_message_local_projection`、group/contact projection 成功后也调用同一 emit。
  - 如果 `plan_realtime_message_local_projection` 返回 `None`，保持 no-op，不发 patch。
  - 如果 group/contact upsert 出错并返回 `Err`，保持现有 fail path，不发 authoritative patch；由 realtime projector warnings 暴露错误。
- 契约 / API / 数据流：
  - realtime event → local projection plan → SQLite `messages` / group / contact projection commit → `emit_committed_conversation_projection` + `emit_committed_message_projection` → Dart SDK patch stream。
  - 不写 `sync_state`，不触碰 `next_event_seq`。
- 兼容性：patch reason 新增 `realtime_incoming` 只用于诊断；subscriber 不应依赖 reason。
- 迁移策略：无 schema / protocol migration。
- 风险控制：测试覆盖 direct 和 group 中至少一个 thread patch；Review 检查 emit 不在 write 前发生。

## 4. 实现方法

1. 在 `awiki-cli-rs2` 执行 `git status --short --branch`，确认没有无关本地修改。
2. 阅读并定位：
   - `awiki-cli-rs2/crates/im-core/src/realtime/runner.rs`
   - `awiki-cli-rs2/crates/im-core/src/core/client.rs`
   - `awiki-cli-rs2/crates/im-core/src/internal/runtime_store/conversation_store.rs`
   - `awiki-cli-rs2/crates/im-core/src/internal/runtime_store/message_store.rs`
3. 修改 async 路径：
   - `db.store_messages(vec![projection.into_record()]).await?;`
   - optional `db.upsert_group(record).await?;`
   - optional `db.upsert_contact(record).await?;`
   - 成功后调用 `client.emit_committed_local_message_projection("realtime_incoming")`。
4. 修改 blocking 路径：
   - `apply_realtime_message_local_projection(...) ?;`
   - `project_realtime_message_group(...) ?;`
   - `project_realtime_message_contact(...) ?;`
   - 成功后调用同一 emit。
5. 补 Rust 测试：
   - 优先在 `awiki-cli-rs2/crates/im-core/src/realtime/runner.rs` 的 test module 或现有 realtime runner tests 中新增测试。
   - 测试思路：构造带 SQLite local state 的 `ImClient`，先订阅 `watch_conversation_patches` 和 `watch_thread_patches(thread)`，再调用 realtime projection helper 或 fake realtime projector，断言收到 upsert/reset 后包含新 message / thread。
   - 若 helper 是私有函数，测试放在同一 module 下；不要为了测试扩大 public API。
   - 断言 patch owner、thread kind/id、version 单调、message id / server seq 匹配。
6. 更新文档：
   - `awiki-cli-rs2/docs/architecture/im-core-sdk-architecture.md`：在 snapshot / runtime store 或 realtime sync 段落补充 realtime local projection 成功后也会 emit patch。
   - `awiki-cli-rs2/docs/api/im-core-interface/04-message-interface.md` 或 `awiki-cli-rs2/docs/flutter-sdk/awiki-im-core-flutter-sdk.md`：如当前文字把 realtime hint 排除为“不会发 patch”，改成“hint 不直接发 authoritative patch；成功落库的 realtime projection 会发 patch”。
7. 运行验证，进入 Review，修复问题后 commit。

## 5. 路径

本节所有路径都相对 AWiki workspace 根目录；不要记录本机绝对路径。

| 仓库 / 模块 / 文件 | 计划变更 | 备注 |
|---|---|---|
| `awiki-cli-rs2/crates/im-core/src/realtime/runner.rs` | 在 realtime message projection 写库成功后 emit patch；同步 blocking / async 路径。 | P0 主变更。 |
| `awiki-cli-rs2/crates/im-core/src/core/client.rs` | 只读 / 复用 emit helper；原则上不改 public API。 | 确认 helper 已同时触发 conversation + message store。 |
| `awiki-cli-rs2/crates/im-core/src/internal/runtime_store/conversation_store.rs` | 可能仅测试引用；不改 DTO。 | 确认 patch from committed projection。 |
| `awiki-cli-rs2/crates/im-core/src/internal/runtime_store/message_store.rs` | 可能仅测试引用；不改 DTO。 | thread patch 断言。 |
| `awiki-cli-rs2/crates/im-core/src/internal/message_runtime/sync.rs` | 只读参考现有 `sync_thread_after` emit 时序。 | 避免重复发射或错误 reason。 |
| `awiki-cli-rs2/docs/architecture/im-core-sdk-architecture.md` | 文档同步。 | 行为变化。 |
| `awiki-cli-rs2/docs/api/im-core-interface/04-message-interface.md` | 必要时文档同步。 | Public contract 文字。 |
| `awiki-cli-rs2/docs/flutter-sdk/awiki-im-core-flutter-sdk.md` | 必要时文档同步。 | Dart SDK 使用者可见行为。 |

## 6. 依赖

- 前置步骤：无。
- 外部文档或决策：主 Plan 第 2、5 节；`awiki-harness/features/message-sync-reliability.md` 的 committed projection 规则。
- 环境前提：`awiki-cli-rs2` 在 `feature/perf/message-sync-opt-0627`，Rust toolchain 可运行 cargo tests。

## 7. 验收标准

- [ ] realtime incoming async 写库成功后触发 conversation patch。
- [ ] realtime incoming async 写库成功后触发 thread message patch。
- [ ] blocking realtime projection 行为不落后 async 路径。
- [ ] projection 失败或无 projection 时不发 authoritative patch。
- [ ] 新增 / 更新 Rust 测试覆盖 patch subscriber。
- [ ] SDK / architecture docs 与行为一致。
- [ ] Review 发现已经修复或明确记录。
- [ ] 本步骤在进入下一步之前已经创建聚焦 commit。

## 8. 验证方式

| 检查项 | 命令 / 方法 | 预期证据 |
|---|---|---|
| Focused Rust tests | `cd awiki-cli-rs2 && cargo test -p im-core --locked realtime` | realtime tests 通过；如果 filter 没覆盖新增测试，记录实际 filter。 |
| Patch store tests | `cd awiki-cli-rs2 && cargo test -p im-core --locked patch` | conversation/thread patch store 相关测试通过；如耗时过长可用更精确 test name。 |
| Broader im-core | `cd awiki-cli-rs2 && cargo test -p im-core --locked` | `im-core` crate 回归通过。 |
| Docs check | `grep -R "realtime_incoming\|realtime projection" -n awiki-cli-rs2/docs/architecture/im-core-sdk-architecture.md awiki-cli-rs2/docs/api/im-core-interface/04-message-interface.md awiki-cli-rs2/docs/flutter-sdk/awiki-im-core-flutter-sdk.md` | 文档包含新语义，且无敏感信息。 |
| Git hygiene | `cd awiki-cli-rs2 && git status --short --branch` | commit 前后状态记录完整。 |

如果某个命令不能运行，记录原因、影响和替代证据。

## 9. Review 环节

- Review 时机：本步骤代码实现完成后、commit 前。
- Review 重点：
  - emit 是否严格在 SQLite write / upsert 全部成功后。
  - `emit_committed_local_message_projection` 是否同时覆盖 conversation 和 thread store。
  - realtime hint 是否仍只是 dirty/gap 调度 metadata，不推进 checkpoint。
  - direct/group thread key 是否与 `watchThreadPatches` 使用的 `ThreadRef` 一致。
  - 测试是否不扩大 public API、不依赖 sleep race。
  - 文档是否没有把 realtime hint 误写成 authoritative patch 来源。

| Review 项 | 结果 | 备注 |
|---|---|---|
| 发现问题 | 待填 | 待填 |
| 已修复问题 | 待填 | 待填 |
| 剩余风险 | 待填 | 待填 |
| 新增或缺失测试 | 待填 | 待填 |
| 已更新或缺失文档 | 待填 | 待填 |

## 10. Commit 要求

- Commit 时机：本步骤实现、验证、Review 都完成后。
- Commit 范围：只包含 `awiki-cli-rs2` 内 P0 相关代码、测试和文档。
- Commit 前状态：记录 `cd awiki-cli-rs2 && git status --short --branch`。
- 纳入文件：记录本步骤 commit 包含的文件。
- Commit 后证据：记录 commit hash 和 commit 后 `git status`。
- 遗留未提交变更：必须记录原因以及为什么安全。
- 建议消息：`fix(im-core): emit patches for realtime incoming projection`

## 11. Blocked 处理

| Blocker | 证据 | 已尝试方案 | 影响范围 | 下一步决策 |
|---|---|---|---|---|
| 待填 | 待填 | 待填 | 当前步骤 / 整体计划 | 待填 |

## 12. Plan 变更记录

| 日期 | 变更 | 原因 | 主 Plan 变更记录链接 |
|---|---|---|---|
| 2026-06-28 | 初始 Step 01 计划 | P0 是本任务最底层关键修复。 | [../plan.md#15-plan-变更记录](../plan.md#15-plan-变更记录) |

## 13. 风险、回滚与后续文档

- 风险：patch 发射过早、重复 patch、测试 race、blocking/async 行为分裂。
- 回滚 / 回退：回滚本步骤 commit 后，系统退回 realtime event + reliable sync / history 补齐路径。
- 后续文档：如实现中发现 `awiki-harness/features/message-sync-reliability.md` 对 realtime patch 语义描述不足，在 Step 05 统一更新 Harness feature doc。
