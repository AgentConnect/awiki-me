# Plan：Agent IM 真实端到端闭环验证与修复

状态：in_progress
DOC：`awiki-me/docs/agent-im-real-e2e-completion-plan/`
Harness：`awiki-harness/`
创建时间：2026-06-14
恢复指针：执行开始前从 Step 01 开始；当前目标是把 `awiki-cli-rs2/docs/agent-im` 描述的 App ↔ 远端 Daemon/Hermes 消息委托闭环做成真实 E2E gate，不再用 skipped 代替通过。

## 1. 目标

- 任务目标：参考 `awiki-cli-rs2/docs/agent-im/` 的 Agent IM 设计和步骤文档，使用 `awiki-me/tests/e2e_test/` 已建立的 E2E 框架补齐真实端到端测试，执行测试，并修复测试发现的问题。
- 预期行为：
  1. `AIM-E2E-001` 在非 dry-run 下必须验证真实链路：App 发送 `awiki.daemon.bootstrap.v1` -> 远端 Daemon 导入 delegated key -> 创建/复用 Hermes message agent -> CLI peer 给 App 用户发普通消息 -> Daemon/Hermes 处理 -> 生成 `awiki.message.sync.v1` / `awiki.app.action.result.v1` 或等价状态 -> App 侧收到并识别为系统状态，不显示为普通聊天。
  2. `AIM-E2E-002` 必须验证同一 bootstrap idempotency key 不重复创建 runtime/message agent。
  3. 远端证据必须可按 `runId` 或本次消息 ID 收口到 Daemon、Hermes、Message Service、User Service / agent inventory / daemon state。
  4. 对端收发工具只使用 `awiki-cli-rs2` 中的 `awiki-cli`，不使用 legacy `awiki-agent-id-message`。
- 非目标：本轮不扩展移动端自动化；不把 E2EE Agent 处理、公钥撤销、Daemon 重启恢复作为 P0 完成条件，但不能破坏既有 P1/P2 设计；不在最终报告输出 OTP、JWT、私钥、registration token 或 raw private package。
- 完成标准：
  - 非 dry-run `AIM-E2E-001` / `AIM-E2E-002` 不再 skipped；通过时必须有 App、CLI、远端 Daemon/Hermes 和消息回传证据。
  - 发现的阻塞缺陷已在本地代码或远端服务代码中修复、部署或明确记录为外部 blocker；不能伪造通过。
  - 受影响仓库完成对应 lint/test/E2E 验证、Review、文档同步和聚焦 commit。

## 2. Harness 上下文

| 来源 | 作用 |
|---|---|
| `awiki-harness/AGENTS.md` | 多仓库任务阅读顺序、权威来源和完成标准。 |
| `awiki-harness/README.md` | Harness 控制面定位和导航入口。 |
| `awiki-harness/context/00-context-map.md` | 将本任务路由到 Identity、Message Flow、Client Architecture、Agent Runtime Host、System Test。 |
| `awiki-harness/context/02-repo-map.md` | 确认 `awiki-cli-rs2` 是最新 CLI/Daemon/SDK 权威，`awiki-me` 是 App，`message-service`/`user-service` 是远端服务。 |
| `awiki-harness/context/03-cross-repo-architecture.md` | 确认 App/CLI/Daemon 依赖方向、runtime 不直连 message-service、daemon 是 Agent Runtime Host。 |
| `awiki-harness/context/20-rules-index.md` | 路由到架构、编码、验证和文档规则。 |
| `awiki-harness/context/30-tools-env.md` | 记录各仓库验证命令和系统测试入口。 |
| `awiki-harness/context/40-verification.md` | 本任务属于 L3：协议/身份/消息/安全敏感跨仓 E2E，必须有 focused E2E 和安全 Review。 |
| `awiki-harness/context/50-task-workflow.md` | 非平凡任务执行、记录、验证和复盘方式。 |
| `awiki-harness/context/nodes/client-architecture.node.md` | App 通过 Dart/Flutter SDK 使用 `im-core`，不直接拼 wire。 |
| `awiki-harness/context/nodes/agent-runtime-host.node.md` | Daemon/Hermes runtime host 边界、local RPC、runtime 不能持有私钥或直连消息服务。 |
| `awiki-harness/context/nodes/message-flow.node.md` | Message Service v2 和 direct/inbox/fanout 边界。 |
| `awiki-harness/context/nodes/identity.node.md` | DID、delegated key、JWT、Handle 身份边界。 |
| `awiki-harness/context/nodes/system-test.node.md` | 系统测试和 E2E 证据要求。 |
| `awiki-harness/rules/architecture-principles.md` | 跨仓边界、依赖方向、E2EE/身份安全约束。 |
| `awiki-harness/rules/ai-coding-rules.md` | 先分析再改、保持 diff 可 Review、文档同步。 |
| `awiki-harness/rules/verification-policy.md` | L3 验证和最终报告证据要求。 |
| `awiki-harness/rules/documentation-principles.md` | 文档权威层级和更新规则。 |

## 3. 影响分析

| 领域 / 仓库 / 模块 | 影响 | 权威文档或代码 |
|---|---|---|
| Agent IM 功能设计 | 验证完整委托消息处理闭环 | `awiki-cli-rs2/docs/agent-im/agent_im_core_design.md`、`awiki-cli-rs2/docs/agent-im/agent_delegated_identity_message_proof_plan.md`、`awiki-cli-rs2/docs/agent-im/plan/steps/*.md` |
| `awiki-me` E2E 框架 | 将 `AIM-E2E-001/002` 从骨架/skipped 改成真实 gate；新增或修改 App probe、scenario、remote evidence parser、report | `awiki-me/tests/e2e_test/`、`awiki-me/tests/integration_test/`、`awiki-me/tool/`、`awiki-me/docs/testing.md` |
| App 侧真实路径 | 使用 Dart App/SDK adapter 创建或恢复 App 用户、确保 session、生成 delegated subkey package、发送 bootstrap、轮询回传 payload | `awiki-me/lib/src/data/im_core/*`、`awiki-me/lib/src/application/agent/agent_control_service.dart`、`awiki-me/lib/src/data/agent/user_service_agent_inventory_adapter.dart` |
| CLI peer | 使用 `awiki-cli-rs2/target/debug/awiki-cli` 作为对端，复用持久 peer identity，发送带 runId 的普通消息 | `awiki-me/tests/e2e_test/harness/src/cli_peer_adapter.dart`、`awiki-cli-rs2/crates/awiki-cli` |
| Daemon/Hermes | 若测试发现缺口，需要修复 bootstrap 处理、message-agent binding、delegated inbox sync、Hermes gateway、message sync outbox delivery 或 observability | `awiki-cli-rs2/crates/awiki-deamon/src/app_bridge/`、`awiki-cli-rs2/crates/awiki-deamon/src/inbox/user_delegated.rs`、`awiki-cli-rs2/crates/awiki-deamon/src/foreground.rs`、`awiki-cli-rs2/crates/awiki-deamon/src/outbox/` |
| Message Service / User Service | 若 delegated proof、fanout、DID public method 或 token 刷新失败，需要修复服务代码并部署到 `ssh ali` | `message-service/docs/api/`、`message-service/crates/`、`user-service/docs/api/`、`user-service/src/` |
| 远端联调 | 通过 `ssh ali` 查看/修改/部署远端 Daemon、Hermes、Message Service、User Service；所有输出必须脱敏 | `awiki-me/codex.md`、`awiki-me/tests/e2e_test/harness/src/remote_adapter.dart` |
| 文档与测试组织 | 更新测试说明、计划台账、remote runbook 和相关 L2 文档 | `awiki-me/docs/`、`awiki-me/tests/e2e_test/README.md`、必要时 `awiki-cli-rs2/docs/agent-im/` |

## 4. 假设与开放问题

### 假设

- `awiki.info` 可通过 SSH alias `ali` 访问；用户口误中的 SSH ARI 按既有项目约定理解为 `ssh ali`。
- 远端 `awiki-deamon.service`、`hermes-gateway.service`、`message-service.service`、`user-service.service` 均部署在 `ssh ali` 对应服务器。
- E2E 使用 non-production OTP 测试账号，配置只通过环境变量读取，不写入提交文件或最终报告。
- Peer 测试账号可以用 `awiki-cli-rs2` CLI 创建一次后长期复用，不需要每次测试重建。
- 本地已有 `awiki-me/tests/e2e_test/configs/agent_im_delegated.local.yaml` 属本机私有配置，不提交。

### 开放问题

- 远端 Daemon 状态库和部署脚本的实际路径需要在 Step 01 中确认；不能在 Plan 中硬编码本机绝对路径。
- 远端当前是否已经有 App 用户对应的 Daemon binding / Hermes runtime，需要通过 agent inventory 和 daemon state 查询确认。
- `message_sync_outbox` 是否已经有生产 flusher；初步代码审计显示可能只 queued 未回传，需 Step 02/03 以真实测试证据确认。
- App 侧最终证据使用 Flutter UI、Dart probe 还是两者组合：本轮优先使用 `tool/` 下 Dart probe 作为稳定 App path，必要时再补 UI smoke。

## 5. 总体设计方法

- 设计边界：E2E 的核心 assertion 放在 `awiki-me/tests/e2e_test/`；服务侧缺口只在对应服务/daemon 仓库修复；不在测试中绕过真实 IM / DID / User Service / Message Service。
- 关键决策：
  - 非 dry-run 的 P0 场景不允许 skipped；没有核心证据时必须 fail。
  - App 侧真实入口使用 `awiki-me` Dart code path：`AwikiImCoreRuntime` + `AwikiImCoreIdentityAdapter` + `AwikiImCoreAuthAdapter` + `AwikiImCoreMessageAdapter` + `UserServiceAgentInventoryAdapter` + `DefaultAgentControlService`。
  - CLI peer 只调用 `awiki-cli-rs2` 的 `awiki-cli`。
  - 远端 evidence 不只 grep 日志，还要优先读取 daemon state / agent inventory / message-service 可观测数据中与 runId 或 message ID 相关的脱敏字段。
- 兼容性策略：新增配置字段必须有 example、local 不提交；旧 dry-run 仍输出计划；P1/P2 场景可继续 skipped，但 P0 不能用 skipped 掩盖真实链路失败。
- 数据、协议、配置或迁移策略：如果需要扩展 bootstrap payload 的 `run_id` 或 message sync delivery，先确保 Daemon parser 兼容 `extra` 字段；如新增 state 方法或表迁移，保持向后兼容。
- 风险控制：所有 report/log 经过 redaction；远端命令只输出脱敏摘要；服务端部署前先本地测试或在远端构建验证；保留回滚命令/commit；不输出 OTP、JWT、private key、registration token。

## 6. 任务拆分

| Step | 标题 | 依赖 | 产出 | 小 Plan 文档 | Commit gate | 状态 |
|---|---|---|---|---|---|---|
| 01 | 基线审计与远端可观测点确认 | 无 | 当前实现缺口、远端状态路径、真实验收证据清单 | [steps/01-baseline-observability.md](steps/01-baseline-observability.md) | 必须 | review |
| 02 | App 真实 bootstrap probe 与 P0 gate 改造 | Step 01 | App 使用真实 SDK/服务发送 bootstrap；`AIM-E2E-001/002` 不再假 pass/skipped | [steps/02-real-app-bootstrap-gate.md](steps/02-real-app-bootstrap-gate.md) | 必须 | committed |
| 03 | Daemon/Hermes 回传闭环修复 | Step 01、Step 02 初跑结果 | 修复 delegated inbox、Hermes、message sync outbox 或 App 接收链路中的真实缺口 | [steps/03-daemon-hermes-return-loop.md](steps/03-daemon-hermes-return-loop.md) | 必须 | committed |
| 04 | 远端 `awiki.info` 部署联调与真实 E2E 执行 | Step 02、Step 03 | 远端服务部署/重启记录，真实 E2E 通过报告，失败则修复后重跑 | [steps/04-remote-awiki-info-e2e.md](steps/04-remote-awiki-info-e2e.md) | 必须 | blocked |
| 05 | 最终 Review、文档同步与跨仓验证 | Step 01-04 | 全局 Review、验证矩阵、提交和最终证据 | [steps/05-final-review-verification.md](steps/05-final-review-verification.md) | 必须 | pending |

## 7. 执行台账

状态取值：`pending`、`in_progress`、`review`、`blocked`、`committed`、`done`。

| Step | 状态 | 分支 | 开始时间 | 完成时间 | Commit | Review 证据 | 验证证据 | 下一步 |
|---|---|---|---|---|---|---|---|---|
| 01 | review | `feature/release-0526/agent-im-hutong` | 2026-06-14 | - | - | 已读 Harness、目标仓库入口、当前 `awiki-me` E2E skeleton、`awiki-cli-rs2/docs/agent-im` 相关设计；确认旧逻辑把核心链路缺证据标为 skipped 是测试门禁缺陷。 | `git status` 已复核；本地 dry-run 可生成计划；后续远端查询受 SSH banner timeout 阻塞。 | 等远端 SSH 恢复后补齐远端 state/log 路径证据。 |
| 02 | committed | `feature/release-0526/agent-im-hutong` | 2026-06-14 | 2026-06-14 | `awiki-me` `0c72111` | 已新增真实 App probe、bootstrap runId、App return wait、P0 缺证据 fail gate、secret redaction；App return 必须是 control payload 且 `hiddenFromChat=true`，否则 P0 fail；非 dry-run 不再允许核心缺证据 skipped。 | `flutter test tests/unit_test/e2e_harness/desktop_agent_im_harness_test.dart` 22 passed；targeted `dart analyze` No issues；E2E dry-run PASS。 | 等真实远端 E2E 验证后最终 Review/commit。 |
| 03 | committed | `feature/release-0526/agent-im-hutong` | 2026-06-14 | 2026-06-14 | `awiki-cli-rs2` `fab900a` | 已实现 CLI 可指定 client message/idempotency、im-core 透传 deterministic message id、daemon message_sync outbox flush/retry/sent、runtime final source fields、Hermes gateway stdout noise 修复。 | `cargo test -p awiki-cli send_message_request_accepts_client_message_id_and_idempotency_key --locked` 通过；`cargo test -p awiki-deamon user_delegated --locked` 10 passed；此前 `cargo test -p im-core --locked`、`cargo test -p awiki-deamon --locked -j1`、`cargo build -p awiki-cli --bin awiki-cli --locked` 均通过。 | 等部署到 `ssh ali` 后跑真实 App↔Daemon/Hermes E2E。 |
| 04 | blocked | `feature/release-0526/agent-im-hutong` | 2026-06-14 | - | - | 尚未取得真实远端 App↔Daemon/Hermes 回传证据；runner 已增加 remote evidence gate，必须看到 `daemon_bootstrap_received`、`delegated_key_imported`、`hermes_agent_ready`、`cli_message_received`、`hermes_runtime_finished`、`summary_return_sent` 六个阶段才算远端通过。 | 新 `ssh ali` 连接返回 `Connection timed out during banner exchange`；本地 shell 未导出 E2E OTP/peer env，无法安全启动真实 run；本地 dry-run 已生成包含 SQLite evidence 查询的 SSH 计划。 | 需要恢复/释放 SSH 会话并导出测试账号 env 后，部署远端并运行真实 E2E。 |
| 05 | pending | `feature/release-0526/agent-im-hutong` | - | - | - | - | - | 等全部实现和远端 E2E 完成。 |

## 8. Codex Goal 执行协议

- 将本 Plan 作为执行进度的唯一事实来源。
- 启动或恢复前，读取本 Plan、当前小 Plan、执行台账和当前 `git status --short --branch`。
- 同一时间只执行一个步骤，除非本 Plan 明确标记多个步骤彼此独立且可以并行。
- 恢复时，从第一个状态不是 `done` 的步骤继续。
- 每个步骤依次执行：标记 `in_progress`、实现、验证、Review、修复 Review 发现、提交、记录证据、标记 `done`。
- 上一个依赖步骤的完成工作未提交前，不要开始下一个依赖步骤。
- 改变范围、顺序、验收标准、公开契约、数据模型或验证策略前，先更新本 Plan。
- 不得用 skipped 替代 P0 通过；P0 缺证据必须 fail 或 blocked。

## 8.1 Codex Goal 提示词

```text
请以 `awiki-me/docs/agent-im-real-e2e-completion-plan/plan.md` 为唯一规划入口，按文档执行完整实现。

开始前先读取：
- `awiki-me/docs/agent-im-real-e2e-completion-plan/plan.md`
- 当前第一个未 done 的 Step 文档
- 主 Plan 的执行台账、Codex Goal 执行协议、验证策略、Blocked 处理和 Plan 变更记录
- 当前 `git status --short --branch`

请从第一个状态不是 `done` 的步骤开始，一次只执行一个步骤。每步都要按对应小 Plan 实现、验证、Review、修复或记录 Review 发现，然后创建一个聚焦 commit，并回填主 Plan 执行台账和 Step 执行状态。需要改变范围、顺序、验收标准、公开契约、数据模型或验证策略时，先更新 Plan 变更记录。

所有步骤完成后，执行最终全局 Review 和整体验证，记录实际命令、通过/失败/跳过数量、失败或跳过原因、剩余风险和最终工作区状态。

核心注意点：P0 Agent IM 真实链路不能 skipped；App 侧必须用 `awiki-me` Dart/SDK 真实路径；CLI peer 只用 `awiki-cli-rs2`；远端通过 `ssh ali` 联调且不输出秘密；所有私钥/JWT/token/OTP/raw package 必须脱敏。
```

## 9. 小 Plan 摘要

### Step 01：基线审计与远端可观测点确认

- 小 Plan：[steps/01-baseline-observability.md](steps/01-baseline-observability.md)
- 目标：确认当前 skeleton 与 `awiki-cli-rs2/docs/agent-im` 目标之间的真实缺口，找到远端可观测点。
- 设计方法：先只读审计，确认 state/log/API/DB 路径，不改功能代码。
- 实现方法：读取关键源文件和远端 service/state；形成 P0 证据清单。
- 路径：`awiki-me/tests/e2e_test/`、`awiki-cli-rs2/crates/awiki-deamon/`、远端 `ssh ali` 服务状态。
- 验证方式：`git status`、只读远端命令、路径/日志/DB 可访问性。
- Review 环节：确认不把健康检查误当功能通过。
- Commit 要求：计划/审计文档可提交；无功能修改时也允许与 Step 02 合并成文档 commit，但需记录。
- 风险：远端 SSH 连接短暂不可用时继续本地审计，稍后重试。

### Step 02：App 真实 bootstrap probe 与 P0 gate 改造

- 小 Plan：[steps/02-real-app-bootstrap-gate.md](steps/02-real-app-bootstrap-gate.md)
- 目标：非 dry-run 使用真实 App/SDK path 完成 App 用户登录/恢复、delegated subkey、bootstrap 发送和 App 侧回传轮询。
- 设计方法：新增稳定 Dart probe/adapter，runner 调 probe；P0 case 只在完整证据满足时 pass。
- 实现方法：扩展 config、scenario result、probe、unit tests、docs。
- 路径：`awiki-me/tool/`、`awiki-me/tests/e2e_test/`、`awiki-me/tests/unit_test/`。
- 验证方式：`dart analyze`、focused unit tests、dry-run、非 dry-run 初跑。
- Review 环节：安全脱敏、真实 SDK 边界、P0 gate 语义。
- Commit 要求：`test: enforce real agent im app e2e gate`。
- 风险：真实 App 用户本地状态/OTP 不可用时 P0 fail 并记录缺口，不跳过。

### Step 03：Daemon/Hermes 回传闭环修复

- 小 Plan：[steps/03-daemon-hermes-return-loop.md](steps/03-daemon-hermes-return-loop.md)
- 目标：修复测试暴露出的服务侧缺口，尤其是 delegated inbox 处理和 message sync/action result 回传 App。
- 设计方法：以测试失败为入口，优先补 daemon unit/integration，再本地/远端验证；不把 runtime 明文私钥暴露给 Hermes。
- 实现方法：可能新增 message sync outbox flusher、state retry 方法、audit/log runId、Hermes stdout noise 修复或 message-service delegated proof 修复。
- 路径：`awiki-cli-rs2/crates/awiki-deamon/`，必要时 `message-service/`、`user-service/`。
- 验证方式：`cargo test -p awiki-deamon --locked` 或 focused tests；必要时服务仓库 cargo/pytest。
- Review 环节：安全/隐私、幂等、重试、状态迁移、日志脱敏。
- Commit 要求：每个仓库聚焦 commit，避免混入无关改动。
- 风险：远端环境已有用户数据，修复必须向后兼容并可回滚。

### Step 04：远端 `awiki.info` 部署联调与真实 E2E 执行

- 小 Plan：[steps/04-remote-awiki-info-e2e.md](steps/04-remote-awiki-info-e2e.md)
- 目标：在 `ssh ali` 上部署修复，执行真实 macOS E2E，收集完整证据。
- 设计方法：先部署受影响服务，再按 runId/message ID 查询远端 state/log，并让 App probe 轮询收到的 payload。
- 实现方法：构建、部署、重启、health check、运行 runner、解析 report。
- 路径：远端 `awiki-space/awiki-cli-rs2`、`message-service`、`user-service`；本地 `awiki-me/.e2e/` report。
- 验证方式：真实 E2E 命令、remote evidence JSON、远端 service health、敏感信息扫描。
- Review 环节：确认远端运行版本和本地 commit 对齐，失败原因不被截断。
- Commit 要求：部署脚本/文档变更需要提交；纯远端部署记录回填文档。
- 风险：远端 SSH/服务窗口不可用时按 blocked protocol 记录，不伪造通过。

### Step 05：最终 Review、文档同步与跨仓验证

- 小 Plan：[steps/05-final-review-verification.md](steps/05-final-review-verification.md)
- 目标：全局核对功能、测试、文档、提交和工作区状态，证明目标完成。
- 设计方法：按需求逐项审计证据，而不是仅看测试绿。
- 实现方法：更新 docs/README/CLAUDE/计划台账，跑最终检查，提交并推送。
- 路径：受影响仓库全部变更文件。
- 验证方式：`git diff --check`、repo tests、真实 E2E report、敏感扫描、`git status`。
- Review 环节：跨仓契约、安全、文档漂移、未提交变更。
- Commit 要求：最终文档/收口 commit；如无文件变更则只回填台账。
- 风险：如果仍有 P1/P2 skipped，要明确不影响 P0 完成；P0 不能 skipped。

## 10. Review 策略

- 每步骤 Review：实现后、commit 前检查行为正确性、回归、公开契约、测试覆盖、文档同步、敏感信息泄漏和未提交无关文件。
- 全局 Review：所有步骤完成后跨仓检查 `awiki-me`、`awiki-cli-rs2`、`message-service`、`user-service`、`awiki-system-test`、`awiki-harness` 状态。
- 契约 / 安全 / 隐私 Review：重点检查 delegated private key 只进 bootstrap 发送链路；Hermes 不接触私钥；E2EE opaque 不进 prompt；report/log 不含 OTP/JWT/private key/token；service-side auth fail closed。
- 文档 Review：行为、配置、测试入口和远端联调方式变化必须同步到子仓 docs，不用 Harness summary 替代子仓权威文档。

## 11. 验证策略

| 层级 | 命令 / 检查 | 预期证据 |
|---|---|---|
| Unit | `cd awiki-me && flutter test tests/unit_test/e2e_harness tests/unit_test/e2e_scenarios` | E2E harness/gate/probe unit 通过，P0 skipped 语义被测试阻止。 |
| App analyze | `cd awiki-me && dart analyze` | No issues。 |
| Daemon focused | `cd awiki-cli-rs2 && cargo test -p awiki-deamon --locked user_delegated message_sync hermes_gateway -- --nocapture` | delegated inbox、message sync flusher、Hermes gateway 相关测试通过。 |
| Daemon full | `cd awiki-cli-rs2 && cargo test -p awiki-deamon --locked -j1` | daemon crate 通过；真实 Hermes ignored 需记录。 |
| Message/User service | 根据实际修改运行 `cd message-service && cargo test --workspace` 或 `cd user-service && uv run pytest ...` | 如修改则必须通过或记录阻塞。 |
| E2E dry-run | `cd awiki-me && dart run tests/e2e_test/harness/desktop_e2e_runner.dart --platform=macos --scenario=agent-im-delegated-message --config tests/e2e_test/configs/agent_im_delegated.example.yaml --dry-run --skip-cli-build --skip-flutter-smoke` | 输出计划，不执行真实链路，P0 为 dry-run skipped。 |
| E2E real | `cd awiki-me && dart run tests/e2e_test/harness/desktop_e2e_runner.dart --platform=macos --scenario=agent-im-delegated-message --config tests/e2e_test/configs/agent_im_delegated.local.yaml --skip-flutter-smoke` | `AIM-E2E-001`、`AIM-E2E-002` pass；`AIM-E2E-006` pass；remote evidence 可按 runId 收口。 |
| Remote | `ssh ali` 只读 health / state / journal / DB 查询 | 服务运行版本、Daemon/Hermes/message-service/user-service 证据完整且脱敏。 |
| Docs/Security | `git diff --check`、report/log redaction scan | 无 whitespace；无私钥/JWT/token/OTP 泄漏。 |

## 12. 文档更新

- Harness 文档：只有跨仓职责或工具入口变化时更新 `awiki-harness/context/*`；纯子仓 E2E 细节优先放在 `awiki-me/docs/`。
- 子仓库文档：更新 `awiki-me/docs/testing.md`、`awiki-me/tests/e2e_test/README.md`、本计划；如修复 Daemon 回传链路，更新 `awiki-cli-rs2/docs/agent-im/` 或 `crates/awiki-deamon/docs/local-dev.md`。
- 本次生成的任务文档：`awiki-me/docs/agent-im-real-e2e-completion-plan/plan.md` 和 `steps/*.md`。

## 13. Commit 计划

- 每个完成、验证、Review 通过的步骤创建一个聚焦 commit。
- Commit 前记录 `git status` 和纳入文件。
- Commit 后记录 commit hash 和工作区状态。
- 不要把所有步骤的修改积累到一个最终大 commit。
- 当前已知：`awiki-cli-rs2` 存在既有未提交 Hermes gateway 修改；后续如果属于本目标修复，纳入 Step 03 Review 和 commit；如不属于，保持不覆盖并记录。

## 14. Blocked 处理

| Blocker | Step | 证据 | 已尝试方案 | 影响范围 | 下一步决策 |
|---|---|---|---|---|---|
| 远端 SSH 临时超时或 banner exchange 失败 | 01/04 | 记录 ssh 命令、时间和错误 | 重试、减少并发 SSH、使用只读短命令、本地继续实现 | 当前远端验证 | 未连续三轮相同 blocker 前不标记 goal blocked；继续本地可推进步骤。 |
| App 用户 OTP/账号不可恢复 | 02/04 | App probe stderr/report 脱敏错误 | 用配置账号 register/recover；确认 handle；必要时清理本地 App workspace | P0 E2E | 不跳过，标记 P0 fail 并修复账号/配置。 |
| Daemon 不回传 App | 03/04 | message_sync_outbox pending 或 App history 无 payload | 补 flusher/state retry/日志/部署，重跑 | 核心目标 | 必须修复，不得把 queued 当 pass。 |
| Hermes runtime 启动失败 | 03/04 | Daemon/Hermes logs、audit、runtime status | 修复 gateway stdout/noise/config，部署重启 | 核心目标 | 必须修复或记录真实外部 blocker。 |

- 只有依赖允许且风险已记录时，才继续另一个 pending 步骤。
- 只有没有安全假设、回退方案或独立下一步时，才询问用户。

## 15. Plan 变更记录

| 日期 | 变更 | 原因 | 影响步骤 | 是否需要 Review |
|---|---|---|---|---|
| 2026-06-14 | 创建真实 Agent IM E2E completion Plan | 用户要求按 `awiki-cli-rs2/docs/agent-im` 真正验证并修复，不再 skipped | 全部 | 是 |
| 2026-06-14 | 回填当前执行状态：Step 02/03 本地实现和验证进入 Review，Step 04 因 SSH/env 阻塞 | 回应“核心能力为什么 skipped”质疑，明确 CLI 对端跑通不等于 App↔Daemon/Hermes 完整回传通过 | 01-04 | 是 |
| 2026-06-14 | 补强 App 侧和远端证据 gate | 用户目标要求 App 收到 summary/status 后进入正确状态、不进入普通聊天，并且远端必须按 runId 证明 Daemon/Hermes 全链路阶段 | 02、04 | 是 |

## 16. 风险与回滚

| 风险 | 缓解措施 | 回滚 / 回退方案 |
|---|---|---|
| 真实 bootstrap 传输 private package，report/log 可能泄漏 | 统一 redaction；probe/report 只保存摘要；远端查询只输出 hash/状态 | 回滚 probe/report 输出变更；保留 send path，删除敏感 report。 |
| 远端服务修复影响生产/staging 运行 | 先本地测试；远端构建后逐服务重启；记录版本和回滚 commit | `git checkout` 上一 commit、重新构建/重启对应 service。 |
| Message sync flusher 重复发送 | 使用 outbox `status`、`idempotency_key`、`sending/pending/sent` 和 retry backoff | 停止 flusher或回滚 daemon commit；检查 outbox 状态。 |
| App/CLI 测试账号状态污染 | 使用固定测试 handle 和隔离 workspace；只存本地 `.e2e/`；不提交本地 config | 清理 `.e2e/` workspace；重新 recover/register 测试账号。 |

## 17. 最终全局 Review 与整体验证

- 触发条件：所有步骤完成、Review、验证并提交后执行。
- Review 范围：全部变更仓库、公开契约、测试、文档、执行台账、远端部署状态、E2E report、敏感扫描和工作区状态。
- 重点关注：`AIM-E2E-001/002` 是否真实 pass；App 是否收到回传；Daemon/Hermes 是否按 runId/message ID 处理；CLI peer 是否只用 `awiki-cli-rs2`；是否有秘密泄漏；P1/P2 skipped 是否不影响 P0。
- 整体验证命令 / 检查：见第 11 节，最终以真实 E2E report 和 remote evidence 为准。
- Review 发现：待 Step 05 回填。
- 已修复问题：待 Step 05 回填。
- 剩余风险：待 Step 05 回填。
- 最终证据：待 Step 05 回填。
- 最终 `git status`：待 Step 05 回填。
- 如果本阶段修改文件：记录 Review、验证和最终集成 commit。
