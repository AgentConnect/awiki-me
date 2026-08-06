# Step 01：协议 DTO 与 SDK payload 能力

主 Plan：[../plan.md](../plan.md)
Step index：01
状态：done

## 1. 执行状态

| 字段 | 值 |
|---|---|
| Status | done |
| Branch | `awiki-cli-rs2-group:feauture/release-0526/group`; `awiki-me-group:feauture/release-0526/group` |
| Started | 2026-06-14T19:55:38+08:00 |
| Completed | 2026-06-14T20:17:46+08:00 |
| Commit | `awiki-cli-rs2-group:3bf3557 feat(im-core): support ANP P9 mention payloads` |
| Review evidence | 手工 Review 通过：确认 P9 未新增 content type/profile/proof/sender；selector 保持 all/agents/humans 不展开；display_name 仅展示快照；Dart payload 校验不再强制 schema；Group E2EE mention payload 只进入 inner plaintext。修复项：移除 Dart analyze 新增 const 提示，并顺手修复已触发的 null-aware lint。 |
| Verification evidence | 通过：`cd awiki-cli-rs2-group && cargo test -p im-core --locked mention`（5 passed）；`cd awiki-cli-rs2-group && cargo test -p im-core --locked --features group-e2ee,blocking mention_group_e2ee_application_body_places_payload_in_inner_plaintext`（1 passed）；`cd awiki-cli-rs2-group && PATH=/Users/cs/development/flutter/bin:$PATH scripts/flutter/codegen-check.sh`（Done）；`cd awiki-cli-rs2-group/packages/awiki_im_core && dart analyze lib test/message_payload_api_test.dart`（No issues）；`cd awiki-cli-rs2-group/packages/awiki_im_core && flutter test test/message_payload_api_test.dart`（9 passed）；`git diff --check`（通过）。部分失败：`cd awiki-cli-rs2-group && cargo test --workspace --locked` 运行到 `awiki-cli --test identity_live_contract` 时 9 个 live contract 因本地 `http://127.0.0.1:* /user-service/did-auth/rpc` transport_unavailable 失败，属于本地 live 依赖未启动，不是 P9 改动失败。 |
| Next action | Step 01 已完成；下一步执行 Step 02 App composer 候选与 draft range |

状态取值：`pending`、`in_progress`、`review`、`blocked`、`committed`、`done`。

## 2. 目标

- 结果：SDK 层能够表达、校验、发送和接收 ANP-P9 mention-bearing group payload。
- 用户 / 系统可见行为：App 和 Daemon 不再各自手写不一致的 mention validator；App 可以发送不含 `schema` 的 P9 JSON payload。
- 非目标：不新增外层 `meta.profile`、content type、JSON-RPC 方法、mention proof 或服务端 selector 展开。
- 完成标准：
  - P9 DTO 覆盖 `MessageMention`、`MentionRange`、`MentionTarget`、`MentionRole`。
  - validator 覆盖 unique id、range、target kind、selector、role、禁止 sender/proof 字段。
  - Dart SDK 不再阻塞 P9 最小 payload。
  - Rust / Dart 测试覆盖 schema-less P9 payload。

## 3. 设计方法

- 设计边界：协议语义放 `awiki-cli-rs2/crates/im-core`，Dart facade 暴露 typed DTO 或至少暴露不强制 `schema` 的 payload 入口；`awiki-me` 只做 UI draft 和展示适配。
- 核心决策：优先新增 typed mention API；如果排期压缩，先放宽 `SendPayloadRequest` JSON object 校验并让 App 使用本地 P9 builder。
- 契约 / API / 数据流：
  - `SendGroupMentionTextRequest { target/group, text, mentions, security, idempotency }` 或等价 DTO。
  - `MessageBodyView::Payload` 保留原始 JSON；可增加 helper / projection 返回 `mention_text` 和 typed `mentions`。
- 兼容性：原有 `awiki.agent.*` payload 的 `schema` 不受影响；只是不再要求所有 JSON payload 都有 `schema`。
- 迁移策略：新增可选字段 / API，避免破坏现有 Dart 调用；codegen 变更必须提交生成物。
- 风险控制：validator 必须严格禁止 mention 内 sender/proof 字段，避免 App 或 Daemon 错误信任局部证明。

## 4. 实现方法

1. 在 `crates/im-core` 新增 P9 DTO 与 validator，或放入 `messages` 模块下的 mention 子模块。
2. 在 send path 中支持 group payload `text + mentions`，确保普通 group base 使用 `application/json`，Group E2EE 放入 inner plaintext payload。
3. 调整 Dart facade：
   - 推荐新增 typed mention request / response model；
   - 或放宽 `_validatePayloadJson`，只检查 JSON object 和大小。
4. 更新 `crates/im-core-dart` DTO / bridge，运行 codegen。
5. 补测试：schema-less payload、非法 range、禁止 proof、selector all/agents/humans、role default addressee。

## 5. 路径

| 仓库 / 模块 / 文件 | 计划变更 | 备注 |
|---|---|---|
| `awiki-cli-rs2/crates/im-core/src/messages/` | 新增 P9 mention DTO / validator / send projection | 协议语义权威层。 |
| `awiki-cli-rs2/crates/im-core-dart/` | 暴露 DTO / API 给 Dart | 需要 codegen。 |
| `awiki-cli-rs2/packages/awiki_im_core/lib/src/models/message.dart` | 新增 Dart mention model 或调整 payload validation | 不引入 App UI DTO。 |
| `awiki-cli-rs2/packages/awiki_im_core/lib/src/awiki_im_core_native.dart` | 解决 `_validatePayloadJson` 强制 `schema` 的冲突 | P9 payload 不应依赖 `schema`。 |
| `awiki-cli-rs2/docs/api/im-core-interface/04-message-interface.md` | 更新 message interface 文档 | 代码变更时同步。 |
| `awiki-cli-rs2/docs/flutter-sdk/awiki-im-core-flutter-sdk.md` | 更新 Dart SDK mention / payload 说明 | 代码变更时同步。 |

## 6. 依赖

- 前置步骤：无。
- 外部文档或决策：`anp/AgentNetworkProtocol/chinese/message/09-消息Mention扩展.md`。
- 环境前提：Rust / Flutter SDK codegen 环境可用。

## 7. 验收标准

- [ ] P9 valid payload 可以不带 `schema` 通过 Dart SDK 发送入口校验。
- [ ] 非法 mention 对象不会被 validator 标记为可触发。
- [ ] `@all/@agents/@humans` selector 保留为 selector，不展开为 DID list。
- [ ] Group E2EE 仅把 mentions 放入 inner plaintext，不复制到外层 metadata。
- [ ] Review 发现已经修复或明确记录。
- [ ] 本步骤在进入下一步之前已经创建聚焦 commit。

## 8. 验证方式

| 检查项 | 命令 / 方法 | 预期证据 |
|---|---|---|
| Rust focused | `cd awiki-cli-rs2 && cargo test -p im-core --locked mention` | P9 DTO / validator / send projection 测试通过。 |
| Rust workspace | `cd awiki-cli-rs2 && cargo test --workspace --locked` | 无跨 crate 回归。 |
| Dart codegen | `cd awiki-cli-rs2 && scripts/flutter/codegen-check.sh` | 生成物一致。 |
| Dart package | `cd awiki-cli-rs2/packages/awiki_im_core && flutter test` | Dart model / wrapper 测试通过。 |
| Docs | `git diff --check` | 文档和代码 diff 无格式问题。 |

如果某个命令不能运行，必须记录原因、影响和替代证据。

## 9. Review 环节

- Review 时机：本步骤代码实现完成后、commit 前。
- Review 重点：P9 MUST/MUST NOT、schema-less payload 兼容、E2EE 放置、DTO 命名、Dart API 不污染 App UI 模型。
- Review 结论必须在 commit 前记录；必须修复必要问题，或明确记录剩余风险。

| Review 项 | 结果 | 备注 |
|---|---|---|
| 发现问题 | 已处理 / 已记录 | `cargo test --workspace --locked` 的 live contract 依赖本地 user-service，失败已归类为环境依赖；Dart analyze 新增提示已修复。 |
| 已修复问题 | 已修复 | Dart payload 校验移除 schema 强制；新增 P9 DTO / validator；Group E2EE payload inner plaintext；Dart lint 提示。 |
| 剩余风险 | 有记录 | 未完成真实端到端验证；workspace 全量测试受本地 live user-service 依赖影响，留到后续集成步骤复验。 |
| 新增或缺失测试 | 已新增 | 新增 Rust `message_mention` focused tests、Group E2EE inner plaintext focused test、Dart package payload / mention tests。 |
| 已更新或缺失文档 | 已更新 | 更新 `awiki-cli-rs2-group/docs/api/im-core-interface/04-message-interface.md` 与 `awiki-cli-rs2-group/docs/flutter-sdk/awiki-im-core-flutter-sdk.md`。 |

## 10. Commit 要求

- Commit 时机：本步骤实现、验证、Review 都完成后。
- Commit 范围：SDK DTO / validator / API、生成物、对应 docs 和测试。
- Commit 前状态：记录 `git status`。
- 纳入文件：记录本步骤 commit 包含的文件。
- Commit 后证据：记录 commit hash 和 commit 后 `git status`。
- 建议消息：`feat(im-core): support ANP P9 mention payloads`

## 11. Blocked 处理

| Blocker | 证据 | 已尝试方案 | 影响范围 | 下一步决策 |
|---|---|---|---|---|
| codegen 环境不可用 | codegen 命令失败 | 记录版本和错误，尝试 repo 文档推荐命令 | Dart SDK API | 若无法恢复，先完成 Rust API 并记录阻塞。 |
| message runtime 不支持 group payload | send path 测试失败 | 检查 group message runtime payload 分支 | App 发送 | 先补 SDK group payload，再继续。 |

## 12. Plan 变更记录

| 日期 | 变更 | 原因 | 主 Plan 变更记录链接 |
|---|---|---|---|
| 2026-06-14 | 创建 Step 01 | 初始设计 | `../plan.md#16-plan-变更记录` |

## 13. 风险、回滚与后续文档

- 风险：放宽 payload validation 可能让更多 schema-less payload 进入 SDK；需保持 JSON object / size / send target 校验。
- 回滚 / 回退：如果 typed API 来不及，可临时只在 App feature flag 下放宽 payload；若出现兼容风险，关闭 mention 发送入口。
- 后续文档：同步 `awiki-cli-rs2/docs/api/im-core-interface/04-message-interface.md` 与 Flutter SDK 文档。


## 14. 本步骤执行记录

- Commit 前状态：`awiki-cli-rs2-group` 有 Step 01 SDK / docs / tests 修改；`awiki-me-group` 有本 Plan 文档未提交。
- 纳入代码 Commit 文件：`crates/im-core/src/messages/mention.rs`、`crates/im-core/src/messages/mod.rs`、`crates/im-core/tests/message_mention.rs`、`crates/im-core/src/internal/group_e2ee/runtime.rs`、`crates/im-core/src/internal/message_runtime/local_projection.rs`、`packages/awiki_im_core/lib/src/models/message_mention.dart`、`packages/awiki_im_core/lib/src/models/message_payload.dart`、`packages/awiki_im_core/lib/src/awiki_im_core_native.dart`、`packages/awiki_im_core/test/message_payload_api_test.dart`、`docs/api/im-core-interface/04-message-interface.md`、`docs/flutter-sdk/awiki-im-core-flutter-sdk.md`。
- Commit 后状态：`awiki-cli-rs2-group` 工作区干净；本 Plan 回填在 `awiki-me-group` 中另行提交。
- 代码 Commit：`awiki-cli-rs2-group:3bf3557 feat(im-core): support ANP P9 mention payloads`。
