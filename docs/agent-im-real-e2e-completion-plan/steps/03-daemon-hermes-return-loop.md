# Step 03：Daemon/Hermes 回传闭环修复

主 Plan：[../plan.md](../plan.md)
Step index：03
状态：committed

## 1. 执行状态

| 字段 | 值 |
|---|---|
| Status | committed |
| Branch | `feature/release-0526/agent-im-hutong` |
| Started | 2026-06-14 |
| Completed | 2026-06-14 |
| Commit | `awiki-cli-rs2` `fab900a fix: complete agent im delegated return loop` |
| Review evidence | 已实现 CLI deterministic message id / idempotency 参数、im-core direct send 透传、daemon `message_sync_outbox` due/sending/sent/retry/stale recovery/failed terminal、foreground flush、runtime final source fields 和 Hermes gateway stdout noise 修复。 |
| Verification evidence | `cargo test -p awiki-cli send_message_request_accepts_client_message_id_and_idempotency_key --locked` 通过；`cargo test -p awiki-deamon user_delegated --locked` 10 passed；此前 `cargo build -p awiki-cli --bin awiki-cli --locked`、`cargo test -p im-core --locked`、`cargo test -p awiki-deamon --locked -j1` 均通过；真实远端 E2E 仍待 Step 04。 |
| Next action | 等 SSH 恢复后部署 `fab900a` 到 `ssh ali`，再用真实 App↔Daemon/Hermes E2E 验证回传链路。 |

状态取值：`pending`、`in_progress`、`review`、`blocked`、`committed`、`done`。

## 2. 目标

- 结果：修复真实 E2E 暴露的服务侧缺口，让 Daemon/Hermes 能处理 App 用户普通消息，并把摘要/状态回传给 App。
- 用户 / 系统可见行为：CLI peer 给 App 用户发消息后，App 可收到 Agent 处理状态/摘要；远端 state/log 能证明 Hermes 处理。
- 非目标：不让 Hermes 持有 App 私钥；不启用 Agent 直接代发普通消息；不实现 E2EE Agent 明文处理。
- 完成标准：服务侧 focused tests 通过；真实 E2E 不再因 Daemon/Hermes/回传缺口失败。

## 3. 设计方法

- 设计边界：按失败点最小修复；优先 `awiki-cli-rs2/crates/awiki-deamon`，只有 delegated proof/fanout 或 DID auth 真失败时才改 `message-service` / `user-service`。
- 核心决策：`message_sync_outbox` 如果只 queued 未发送，必须实现 delivery/retry/mark-sent，不能把 queued 当 App 收到。
- 契约 / API / 数据流：Daemon 使用自身 agent identity 向 App user DID 发送 `awiki.message.sync.v1` payload；payload 不含明文 final，只含摘要/状态/hash 或允许的 action result。
- 兼容性：已有 runtime final outbox 不受影响；新增 message sync flusher 复用相同 retry 思路。
- 迁移策略：如新增 state 方法不需要新表；如改表需迁移并兼容旧数据库。
- 风险控制：outbox 幂等、retry backoff、日志脱敏、Hermes stdout 噪声处理。

## 4. 实现方法

1. 用 Step 02 初跑和远端 state/log 定位失败阶段。
2. 若 `message_sync_outbox` pending：
   - 在 `DaemonState` 增加 list_due / mark_sending / mark_sent / mark_retry / recover_stale / failed_terminal 方法；
   - 在 daemon foreground loop 调用 `flush_message_sync_outbox`；
   - 通过 `ImCoreAgentOutbox::send_payload` 由 daemon agent 发给 `owner_did`；
   - 增加 tests 覆盖 sent/retry/idempotency/no plaintext。
3. 若 Hermes gateway 启动/输出异常：修复 stdio adapter 或 gateway 配置，补 `hermes_gateway` tests。
4. 若 delegated inbox proof/fanout 失败：在 `message-service` 补 focused tests/修复；只使用 published ANP crate。
5. 若 DID Document / public method 失败：在 `user-service` 或 App subkey registration 路径修复，并补 tests/docs。
6. 更新相关 docs 和本 Plan 台账。

## 5. 路径

| 仓库 / 模块 / 文件 | 计划变更 | 备注 |
|---|---|---|
| `awiki-cli-rs2/crates/awiki-deamon/src/inbox/user_delegated.rs` | 可能补 outbox flush 或 payload evidence | 核心回传。 |
| `awiki-cli-rs2/crates/awiki-deamon/src/foreground.rs` | 调用 flush / 记录 audit | daemon loop。 |
| `awiki-cli-rs2/crates/awiki-deamon/src/state/mod.rs` | outbox retry 状态方法 | 需向后兼容。 |
| `awiki-cli-rs2/crates/awiki-deamon/src/outbox/mod.rs` | 复用 payload send | 不绕过 im-core。 |
| `awiki-cli-rs2/crates/awiki-deamon/tests/*` | focused tests | 必须覆盖修复。 |
| `message-service/`、`user-service/` | 只在真实失败要求时修改 | 修改则各自验证和提交。 |
| `awiki-cli-rs2/docs/agent-im/` | 更新实现/剩余风险 | 若行为改变。 |

## 6. 依赖

- 前置步骤：Step 01、Step 02 初跑结果。
- 外部文档或决策：`awiki-cli-rs2/docs/agent-im/plan/steps/05-awiki-deamon-user-delegated-inbox-sync.md`、`07-message-service-delegated-key-policy-and-fanout.md`、`08-app-action-schema-and-visibility.md`。
- 环境前提：本地 Rust toolchain；远端可部署验证。

## 7. 验收标准

- [ ] 失败点有明确 root cause，不做盲修。
- [ ] 服务侧修复有 focused tests。
- [ ] message sync/action result 能实际发给 App，而不是仅 queued。
- [ ] Hermes 处理普通消息，不接触 private key，不处理 E2EE opaque 明文。
- [ ] Review 发现已经修复或明确记录。
- [ ] 本步骤在进入下一步之前已经创建聚焦 commit。

## 8. 验证方式

| 检查项 | 命令 / 方法 | 预期证据 |
|---|---|---|
| Daemon focused | `cd awiki-cli-rs2 && cargo test -p awiki-deamon --locked user_delegated message_sync hermes_gateway -- --nocapture` | focused tests 通过。 |
| Daemon full | `cd awiki-cli-rs2 && cargo test -p awiki-deamon --locked -j1` | crate 全量通过或记录已有 ignored。 |
| Message Service | `cd message-service && cargo test --workspace` | 仅修改时运行；通过或记录失败。 |
| User Service | `cd user-service && uv run pytest ...` | 仅修改时运行；通过或记录失败。 |
| Secret scan | `rg -n "private_key_pem|Authorization|Bearer|DEV_OTP|jwt" <changed reports/docs>` | 没有真实秘密。 |

## 9. Review 环节

- Review 时机：本步骤代码实现完成后、commit 前。
- Review 重点：幂等和 retry、状态迁移、App 回传是否真实发送、Hermes 私钥边界、日志脱敏、测试覆盖。
- Review 结论必须在 commit 前记录；必须修复必要问题，或明确记录剩余风险。

| Review 项 | 结果 | 备注 |
|---|---|---|
| 发现问题 | 待回填 | - |
| 已修复问题 | 待回填 | - |
| 剩余风险 | 待回填 | - |
| 新增或缺失测试 | 待回填 | - |
| 已更新或缺失文档 | 待回填 | - |

## 10. Commit 要求

- Commit 时机：实现、验证、Review 都完成后。
- Commit 范围：按仓库拆分；不要把 `awiki-me` E2E gate 和 daemon flusher 混成无法 review 的大 diff，除非测试契约必须同提交并记录原因。
- Commit 前状态：记录 `git status`。
- 纳入文件：记录本步骤 commit 包含的文件。
- Commit 后证据：记录 commit hash 和 commit 后 `git status`。
- 遗留未提交变更：必须记录原因以及为什么安全。
- 建议消息：`awiki-deamon: deliver delegated message sync to app`

## 11. Blocked 处理

| Blocker | 证据 | 已尝试方案 | 影响范围 | 下一步决策 |
|---|---|---|---|---|
| 远端 Hermes 依赖缺失无法安装 | gateway/service log | 修复 stdout noise、安装依赖、配置 gateway command | 核心目标 | 未连续三轮不标 blocked；继续可本地修复部分。 |
| message-service delegated proof 与 docs 不一致 | E2E/服务测试失败 | 补服务测试和修复 | 核心目标 | 修改 message-service 并验证。 |

## 12. Plan 变更记录

| 日期 | 变更 | 原因 | 主 Plan 变更记录链接 |
|---|---|---|---|
| 2026-06-14 | 创建 Step 03 | 服务侧真实闭环修复需要单独 Review 和 commit | [../plan.md#15-plan-变更记录](../plan.md#15-plan-变更记录) |

## 13. 风险、回滚与后续文档

- 风险：重复发送 message sync；需要 idempotency/status/sent_at 控制。
- 回滚 / 回退：回滚 daemon commit 并重启远端 service；测试会重新 fail，不能声称完成。
- 后续文档：更新 daemon local-dev / Agent IM docs 的 message sync delivery 状态。
