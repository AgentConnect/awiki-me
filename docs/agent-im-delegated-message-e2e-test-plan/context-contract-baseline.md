# Step 01 契约与缺口基线

状态：Step 01 输出草案，随 Step 01 commit 固化  
日期：2026-06-13  
关联主 Plan：[plan.md](plan.md)  
关联 Step：[steps/01-context-contract-baseline.md](steps/01-context-contract-baseline.md)

## 1. 范围与方法

本基线只做只读调研与文档校准，不修改产品代码、不登录远端、不运行真实 E2E。调研对象包括：

- `awiki-me` App 侧 bootstrap、control payload、E2E harness、现有单元测试。
- `awiki-cli-rs2` CLI peer、`im-core` delegated signing 入口、`awiki-deamon` bootstrap / delegated inbox / message agent / sync outbox。
- `message-service` delegated local view、DID proof、普通消息与 E2EE opaque 边界。
- `user-service` DID Document delegated public key 注册、撤销与 registry 管理面。
- `awiki-system-test` 已有 App -> Daemon control E2E 作为相邻参考。
- ANP SDK 依赖边界：本 E2E 首选 CLI peer，不直接在 `awiki-me` 中引入 Python SDK。

## 2. 仓库状态基线

执行 Step 01 前观测到的相关仓库状态如下。后续 Step 提交时不得把既有无关变更混入当前步骤 commit。

| 仓库 | 分支 | HEAD | 状态 | 备注 |
|---|---|---|---|---|
| `awiki-me` | `feature/release-0526/agent-im-hutong` | `fc9ce73` | 未跟踪本计划目录 | Step 01 只提交 `docs/agent-im-delegated-message-e2e-test-plan/`。 |
| `awiki-cli-rs2` | `feature/release-0526/agent-im-hutong` | `b2e54b4` | 有既有修改 | `crates/awiki-deamon/docs/local-dev.md`、`crates/awiki-deamon/src/plugins/hermes/gateway.rs`、`crates/awiki-deamon/tests/hermes_gateway.rs`；Step 01 不修改。 |
| `awiki-system-test` | `feature/release-0526/agent-im-hutong` | `50d85f7` | 干净 | 只读参考。 |
| `message-service` | `feature/release-0526/agent-im-hutong` | `a3a8f3d` | 有既有修改 | `Cargo.lock`、`crates/im-app/src/app.rs`；Step 01 不修改。 |
| `user-service` | `feature/release-0526/agent-im-hutong` | `a7df611` | 干净 | 只读参考。 |

## 3. 已确认契约

### 3.1 App 侧 bootstrap 与 payload 可见性

| 契约 | 当前证据 | 结论 |
|---|---|---|
| Bootstrap schema | `awiki-me/lib/src/domain/entities/agent/agent_bootstrap.dart` 定义 `awiki.daemon.bootstrap.v1` 与 `awiki.daemon.user_subkey_package.v2`。 | App 侧已具备生成 bootstrap envelope 的 domain model。 |
| 子 key 固定 fragment | `defaultDaemonVerificationMethod(userDid)` 固定为 `{userDid}#daemon-key-1`，非该 verification method 会本地拒绝。 | 与 Agent IM MVP 契约一致。 |
| 私钥包格式 | v2 package 使用 `private_key_encoding: pem` 与 `private_key_pem`，同时要求 public key 与 verification method。 | E2E 报告必须把 raw package 与 PEM 私钥作为敏感内容处理。 |
| 默认 runtime / role | `DesiredMessageAgent` 默认 `runtime: hermes`、`role: app_message_handler`。 | E2E 断言应使用 Hermes message agent，而不是旧 runtime 名。 |
| MVP action allowlist | `message.summarize_plain`、`message.create_draft`、`contact.read`、`contact.update_display_name`、`contact.update_note`。 | 与 Step 08 已落地 allowlist 一致。 |
| E2EE 边界 | `sync_policy.e2ee_default = not_supported_in_mvp`、`plain_default = agent_visible`。 | 首批 E2E 只验证普通非 E2EE 消息进入 Agent。 |
| 发送方式 | `AgentControlService.ensureMessageAgentBootstrap` 通过 `_sendDaemonPayload` 发送普通 payload，并使用稳定 idempotency key。 | Step 04 需要提供可自动触发和观测的 App E2E entry。 |
| 聊天污染防护 | `AgentControlPayloads.isControl` 将所有 `awiki.*` schema 视作 system/control；conversation mapper 和 preview 会隐藏 control payload。 | E2E 应断言 bootstrap/sync/action 不显示为普通聊天气泡。 |
| 现有测试 | `tests/unit_test/agents/agent_control_service_test.dart`、`agent_control_payload_test.dart`、`data/im_core/*payload_mapper*` 覆盖 bootstrap、allowlist、private-state reject 与 payload hiding。 | Step 02-05 可复用这些契约作为 harness 单测基线。 |

### 3.2 `awiki-me` E2E harness 当前能力

| 能力 | 当前状态 | 缺口 |
|---|---|---|
| 平台 | `tests/e2e_test/harness/desktop_e2e_runner.dart` 支持 `--platform=macos|linux` 与平台工具检查。 | 平台 adapter 已有雏形。 |
| dry-run | 支持 `--dry-run`，会打印命令并生成 timing report。 | 还没有 Agent IM scenario dry-run。 |
| CLI 构建与 workspace | 可构建 `awiki-cli-rs2` CLI，创建 `.e2e/<platform>/cli-workspaces/<runId>` 并执行 `init`、`config show`、`status`。 | 还没有 CLI peer 账号登录/恢复、发送消息、查询消息结果的 adapter。 |
| App smoke | 支持 `integration_test/im_core_open_smoke_test.dart`。 | 还没有触发 message agent bootstrap 的 integration entry 或 UI 自动化。 |
| config | 现有 runner 只从 env 读取基本 URL、domain、CLI repo。 | 还没有 `--config`、Agent IM yaml、账号/remote/timeouts 配置。 |
| scenario | `tests/e2e_test/scenarios/README.md` 只是占位。 | 还没有 scenario registry 和 `agent_im_delegated_message` 实现。 |
| report / redaction | 仅有 `timings.json`，日志原样写入命令输出。 | 需要统一 report writer 与 secret redactor，扫描本地 report、CLI workspace、App logs、远端 logs。 |
| 路径可移植性 | runner 代码内存在 host-specific Flutter fallback。 | Step 02 应避免在报告和 docs 中继续传播本机路径，并考虑改为 env/`PATH` 优先。 |

### 3.3 CLI peer 与 im-core

| 契约 | 当前证据 | 结论 |
|---|---|---|
| CLI command catalog | `awiki-cli-rs2/crates/awiki-cli/src/command_catalog/mod.rs` 暴露 `id.register`、`id.refresh-token`、`msg.send`、`msg.inbox`、`msg.history`。 | CLI 具备作为 peer 的基础命令面。 |
| CLI parser | `cli_parser/mod.rs` 分发同步/异步 `msg.send`、`msg.inbox`、`msg.history`、`id.register`、`id.refresh-token`。 | Step 03 需要封装非交互式调用和 JSON 输出解析。 |
| 普通消息发送 | `m_core_cli_adapter/messages.rs` 通过 `send_text_via_im_core*` 调用 im-core；CLI peer 默认 `delegated_signing: None`。 | CLI peer 应代表另一个测试用户，不应绕过 im-core 或伪造 delegated signing。 |
| im-core delegated signing | `im-core` DTO / direct runtime 已有 `DelegatedSigningOptions`，daemon 可消费。 | E2E 主路径仍由 daemon 使用子 key，CLI peer 不直接使用该能力。 |
| 账号与 OTP | CLI 有注册/刷新 token 命令，但当前 `awiki-me` harness 没有账号生命周期编排。 | Step 03 的 P0 是隔离 workspace + 账号登录/恢复 + 普通消息发送；OTP/token 必须脱敏。 |

### 3.4 Daemon / Hermes delegated inbox

| 契约 | 当前证据 | 结论 |
|---|---|---|
| Bootstrap parser | `awiki-deamon/src/app_bridge/bootstrap.rs` 定义 `DAEMON_BOOTSTRAP_SCHEMA`，接受 v2 package，要求 `private_key_encoding=pem`、`private_key_pem`、`#daemon-key-1`、controller 与 sender/user DID 一致。 | Daemon 已有 bootstrap import/validation 基础。 |
| DID Document 验证 | bootstrap 校验 DID Document method、`authentication`、controller、public key 与 private key match、expiration。 | E2E 失败时应按 DID Document / key owner / authentication 二分。 |
| Message agent binding | `app_bridge/message_agent.rs` 要求 `role=app_message_handler`、`runtime=hermes`，首次创建需要 `runtime_registration_token`，相同 `ensure_once_key` 幂等。 | AIM-E2E-002 可断言幂等绑定。 |
| Delegated inbox | `inbox/user_delegated.rs` 使用 `fetch_user_delegated_inbox` 拉取 `inbox_owner_did` + `inbox_auth_verification_method` 对应普通消息。 | AIM-E2E-001 的核心服务侧入口已存在。 |
| 去重与 cursor | 持久化 `inbox_cursor`、`processed_message`、`message_event`，dispatch 失败进入 retryable，E2EE opaque 标记为 `ignored_e2ee_opaque`。 | AIM-E2E-003/004 后续可基于这些状态验证。 |
| Prompt 安全 | 普通消息进入 `user_message_untrusted` envelope；E2EE opaque 不进入 Agent prompt。 | E2E 和日志 Review 要检查 Hermes prompt 不含 E2EE 明文。 |
| Runtime status/final | runtime status/final 会写入 `message_sync_outbox`，final 只保存 text hash，不保存完整 final 明文。 | 隐私边界合理，但 App 收到 sync 的真实发送链路仍需补证据。 |
| 出站发送 | delegated runtime `send_message` / `send_attachment` 当前显式拒绝，原因是该路径尚未开启。 | MVP E2E 不应断言 Agent 直接代发；只测摘要/状态/草稿或 queued sync。 |
| Sync outbox 投递 | 当前只看到 `upsert_message_sync_outbox` / `load_message_sync_outbox` 和相关测试，未发现完整 pending outbox flusher/mark-sent 路径。 | 这是 Step 05/06 的 P0 风险：如果 App 必须收到 `awiki.message.sync.v1`，需要先证明或补齐 delivery path。 |

### 3.5 Message Service delegated proof / fanout 边界

| 契约 | 当前证据 | 结论 |
|---|---|---|
| delegated local view | `message-service/docs/api/ANP-client-server-api-direct.md` 第 13 章规定 delegated local view 只适用于 `inbox.get` 与 `direct.get_history`。 | Daemon 拉取 inbox/history 的服务端契约已记录。 |
| owner/key 一致性 | 请求需同时携带 `body.inbox_owner_did` 与 `body.inbox_auth_verification_method`，`body.user_did`、`meta.sender_did` 与认证 DID 必须等于 owner，origin proof keyid 必须等于 delegated method。 | E2E 的 invalid proof / 401 排查路径明确。 |
| DID Document 授权源 | 服务端只通过 DID proof、DID Document `authentication`、key owner 一致性和普通非 E2EE scope 判定授权；MVP 不查 user-service registry。 | 撤销场景以 DID Document `authentication` 为事实源。 |
| E2EE 边界 | delegated local view 只返回 `transport-protected` 普通消息；E2EE opaque 通知可 fanout，但 daemon 自行丢弃/标记。 | AIM-E2E-004 是 P1，不属于首批 P0。 |
| 测试 | `im-direct/src/service.rs` 有 delegated inbox/history accept、wrong owner/keyid/not-in-authentication、E2EE filtering tests。 | 服务端契约有单仓测试支撑；本计划后续需要 E2E 覆盖真实链路。 |

### 3.6 User Service delegated public key

| 契约 | 当前证据 | 结论 |
|---|---|---|
| public-only registration | `user-service/docs/api/did-internal.md` 定义 `delegated_key_public_registration`，user-service 只登记 daemon delegated public key，不生成、不接收、不返回 daemon private key。 | App 侧私钥包只通过 bootstrap 给 Daemon，不能进入 user-service。 |
| fixed fragment | MVP 固定 `daemon-key-1`，relationship 固定 `authentication`。 | 与 App / Daemon / Message Service 一致。 |
| forbidden private material | registration 明确拒绝 private key / private multibase / daemon subkey private material。 | E2E 测试账号创建必须只传 public key。 |
| proof 重签 | DID Document 插入 `#daemon-key-1` 后 user-service 需要重新签 proof，避免保存后 patch 造成 proof 失效。 | Step 03/04 账号创建失败时应检查 DID proof。 |
| registry 边界 | registry 是管理/审计/查询面，不是 message-service MVP 运行时授权事实源。 | AIM-E2E-005 撤销以 signed DID Document update 移除 `authentication` 为核心。 |
| 测试 | `test_service_managed.py` 覆盖 delegated public key 写入、proof 验证、private material 拒绝、幂等、冲突、revoked reuse、revoke 前需 signed DID update。 | User Service 侧契约已有单元/集成测试支撑。 |

### 3.7 `awiki-system-test` 相邻覆盖

`awiki-system-test/docs/plan/app-daemon-control-e2e/plan.md` 与 `tests_v2/daemon/test_app_daemon_control_e2e.py` 已覆盖相邻的 App payload -> Daemon foreground -> runtime status/final 链路，但该路径的默认 P0 runtime 是 deterministic `test-runtime-uds`，并且主要验证 App/Daemon 控制 payload、非 controller 拒绝、install/inventory mapper 和 gated remote smoke。

结论：这套测试是可复用参考，但不能替代本计划的 Agent IM delegated inbox E2E，因为它没有覆盖：

- `user_did#daemon-key-1` delegated identity bootstrap 导入。
- Daemon 以 delegated identity 拉取用户普通 inbox/history。
- CLI peer 给 App 用户发送普通消息后，App 与 Daemon 同时收到并 fanout。
- Hermes message agent 对普通用户消息处理后的 App sync/action result 闭环。

### 3.8 ANP SDK 依赖边界

| 仓库 | 当前依赖状态 | 对本 E2E 的影响 |
|---|---|---|
| `awiki-me` | App 是 Dart-only；仓库规则要求使用 Dart ANP SDK 和 Dart service clients，不引入 Python manifest。 | `awiki-me` E2E harness 不应直接依赖 Python `anp` SDK；应通过 App 与 `awiki-cli-rs2` CLI peer 走真实路径。 |
| `awiki-cli-rs2` | 当前工作区依赖本地 `../anp/anp/rust`。 | Step 03/05 构建 CLI 时要记录 ANP source；提交前不要无意切换依赖。 |
| `message-service` | `Cargo.toml` 使用发布版 `anp = "0.8.7"`。 | 远端/本地服务端行为应按发布版 Rust SDK 验证，除非后续 Step 明确切本地 SDK。 |
| `user-service` | `pyproject.toml` 写 `anp==0.8.7`，同时 `tool.uv.sources` 指向本地 editable 源。 | 本地开发可能消费 `0.8.7` 之后的未发布 Python 代码；若 Step 03/06 依赖这些能力，必须先发布新 SDK 或在计划中明确 local-source gate。 |
| `awiki-system-test` | Python tests 依赖 `anp`，当前 lock 中仍可见旧发布版。 | 本计划不把 Python ANP SDK 作为 Agent IM E2E 主路径，只在系统测试 helper 必要时记录版本与 source。 |

## 4. P0 缺口与后续 Step 映射

| 缺口 | 影响 | 后续 Step |
|---|---|---|
| `desktop_e2e_runner.dart` 缺少 `--scenario`、`--config`、scenario registry、structured report、secret redactor、remote adapter。 | 无法以统一命令运行 Agent IM E2E，也无法复用 Mac/Linux 架构。 | Step 02 |
| `tests/e2e_test/scenarios/` 没有 Agent IM scenario 实现。 | AIM-E2E-001/002/006 无自动化承载位置。 | Step 02 / Step 05 |
| CLI peer 账号登录/恢复/发送普通消息还没有被 `awiki-me` harness 封装。 | 无法稳定产生“另一个用户给 App 用户发普通消息”的真实输入。 | Step 03 |
| App bootstrap 只有 service/domain model 和 provider 调用，缺少 E2E 可控 entry / UI 自动化入口 / 状态观察器。 | 无法在 E2E 中稳定触发 `awiki.daemon.bootstrap.v1` 并判断成功。 | Step 04 |
| Daemon `message_sync_outbox` 已 queued，但未在当前调研中找到完整发送到 App 的 flusher/mark-sent 路径。 | AIM-E2E-001 中“App 收到 summary/status”可能先只能验证 queued sync，或需要补 daemon delivery。 | Step 05 / Step 06 |
| delegated runtime `send_message` / `send_attachment` 当前拒绝。 | MVP 不应测 Agent 直接代发；代发功能要另立功能计划或后续扩展。 | Step 05 场景约束 |
| 远端 `awiki.info` 服务管理、部署版本和日志路径仍未发现。 | remote evidence 需要执行期通过 `ssh ali` 发现，并脱敏写入报告。 | Step 06 |
| ANP 本地源码可能领先发布版。 | 如果测试依赖未发布 SDK API，部署和 CI 会不可复现。 | Step 03 / Step 06 版本 gate |

## 5. 场景优先级校准

- 首批自动化仍建议锁定 AIM-E2E-001、AIM-E2E-002、AIM-E2E-006。
- AIM-E2E-001 的验收需要拆成两个 gate：
  1. Daemon delegated inbox 收到并 dispatch 普通消息给 Hermes message agent。
  2. App 收到 `awiki.message.sync.v1` / action result。若当前 outbox delivery 缺口属实，先标记第二个 gate blocked 或补齐 delivery path。
- AIM-E2E-003 daemon 重启恢复依赖 Step 05 场景稳定后再启用。
- AIM-E2E-004 E2EE opaque 不进入 Agent 属 P1，但已有 daemon/message-service 单仓测试支撑，后续可作为 focused E2E 补强。
- AIM-E2E-005 delegated key 撤销需要 signed DID Document update，不应只改 user-service registry。

## 6. 安全与隐私基线

- 本计划文档只能记录环境变量名、相对路径、schema、commit 和脱敏证据。
- 本计划文档、report、CLI stdout/stderr、App logs、远端 logs 均不得包含：DID 私钥、daemon subkey private package、JWT、access/refresh token、runtime token、OTP 值、数据库密码、E2EE 明文。
- 普通消息测试文本允许包含 runId，但必须使用固定短句，不能使用真实用户内容。
- App/Daemon 当前会处理 raw private package；Step 02 的 redactor 必须在命令输出、timing/report JSON、remote evidence 写入前统一脱敏。
- 对 E2EE 消息，MVP 只验证 opaque ignored，不允许把明文交给 Hermes。

## 7. Step 01 结论

Step 01 基线确认：Agent IM 的核心产品代码和跨仓契约已基本存在，但 E2E 自动化缺口集中在 `awiki-me` harness、CLI peer 编排、App bootstrap 自动化、Daemon sync outbox delivery 证据和 remote evidence 采集。后续应按主 Plan 顺序推进，先补 harness 基础，再补 CLI peer 与 App bootstrap，最后实现 Agent IM delegated message scenario 与 `awiki.info` 联调。
