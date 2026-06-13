# Plan：Agent IM 委托消息处理 E2E 测试落地

状态：in_progress  
DOC：`awiki-me/docs/agent-im-delegated-message-e2e-test-plan/`  
Harness：`awiki-harness/`  
创建时间：2026-06-13  
恢复指针：Step 05 已完成 Agent delegated message E2E 场景骨架与 redaction scan；下一步从 Step 06 开始 `awiki.info` 远端联调与服务侧补强。当前未登录远端。

## 1. 目标

- 任务目标：基于 `awiki-me` 已建立的 E2E 测试框架，为 Agent IM 委托消息处理功能建立可落地、可复用、可联调 `awiki.info` 的端到端测试体系。
- 预期行为：后续实现完成后，可以在 macOS 先跑通 App + `awiki-cli-rs2` CLI peer + `awiki.info` Daemon/Hermes + User Service + Message Service 的真实链路，并且 Linux 仅通过 platform adapter 差异复用同一套 scenario、CLI peer、config、report、redaction 和联调逻辑。
- 非目标：本 Plan 不直接修改生产功能代码，不立即执行 E2E，不在文档中写入远端真实路径、密钥、JWT、私钥或 OTP 值；不在 MVP 中要求 Agent 解密 E2EE 明文。
- 完成标准：测试方案、场景矩阵、远端联调 Runbook、证据模板与本落地 Plan 已写入 `awiki-me/docs/agent-im-delegated-message-e2e-test-plan/`；未来执行者可按步骤逐个实现、Review、验证、commit，并最终完成全局 Review 和整体验证。

## 2. Harness 上下文

| 来源 | 作用 |
|---|---|
| `awiki-harness/AGENTS.md` | 确认 Harness 是多仓库控制面，子仓库是实现权威。 |
| `awiki-harness/README.md` | 确认读取顺序与文档放置原则。 |
| `awiki-harness/context/00-context-map.md` | 将需求路由到 Client Architecture、Agent Runtime Host、Message Flow、Identity、E2EE、System Test。 |
| `awiki-harness/context/02-repo-map.md` | 确认 `awiki-me`、`awiki-cli-rs2`、`message-service`、`user-service`、`awiki-system-test` 的职责。 |
| `awiki-harness/context/03-cross-repo-architecture.md` | 确认 `im-core`/Dart SDK/App/Daemon/message-service 的依赖方向和 runtime 边界。 |
| `awiki-harness/context/20-rules-index.md` | 路由到文档、架构、AI coding、验证规则。 |
| `awiki-harness/context/30-tools-env.md` | 确认各仓库常用验证命令。 |
| `awiki-harness/context/40-verification.md` | 确认本任务属于 L3：协议、DID、auth、E2EE 边界和系统 E2E。 |
| `awiki-harness/context/50-task-workflow.md` | 确认 Plan、执行台账、验证证据和 blocker 处理要求。 |
| `awiki-harness/rules/documentation-principles.md` | 确认方案归属子仓库 docs，Harness 不复制实现细节。 |
| `awiki-harness/rules/architecture-principles.md` | 确认身份、消息、E2EE、客户端和系统测试边界。 |
| `awiki-harness/rules/ai-coding-rules.md` | 确认先分析、再小步可 Review 实现。 |
| `awiki-harness/rules/verification-policy.md` | 确认 L3 security review 与 E2E 证据 gate。 |

## 3. 影响分析

| 领域 / 仓库 / 模块 | 影响 | 权威文档或代码 |
|---|---|---|
| `awiki-me` E2E 框架 | 新增 Agent IM delegated message scenario、config、report/redaction、可选 Flutter integration shim | `awiki-me/docs/awiki-me-test-framework-plan.md`, `awiki-me/docs/testing.md`, `awiki-me/tests/e2e_test/` |
| `awiki-cli-rs2` CLI peer / im-core / daemon | 作为测试对端与 Daemon 行为权威；必要时补 CLI 命令、daemon observability 或测试 helper | `awiki-cli-rs2/docs/agent-im/`, `awiki-cli-rs2/crates/awiki-deamon/docs/` |
| `message-service` | 验证 delegated key proof、普通消息 fanout、E2EE opaque 边界 | `message-service/docs/api/`, `message-service/docs/architecture/` |
| `user-service` | 验证 DID Document delegated public key、authentication、撤销行为 | `user-service/docs/api/did-auth.md`, `user-service/docs/api/did-verify.md`, `user-service/docs/api/handle.md` |
| `awiki-system-test` | 若 App-side E2E 不能覆盖服务端契约，补跨服务 focused suite 或复用 remote system test | `awiki-system-test/README.md`, `awiki-system-test/tests_v2/` |
| `awiki.info` remote 环境 | 联调 Daemon/Hermes/User Service/Message Service 日志、部署版本、健康状态 | `awiki-me/codex.md`, 本目录 [remote-awiki-info-runbook.md](remote-awiki-info-runbook.md) |
| 安全 / 隐私 | 私钥包、JWT、token、OTP、E2EE 明文不得进入日志和报告 | `awiki-harness/rules/verification-policy.md`, [evidence-template.md](evidence-template.md) |

Step 01 基线输出：[context-contract-baseline.md](context-contract-baseline.md)。

## 4. 假设与开放问题

### 假设

- 当前目标分支是 `feature/release-0526/agent-im-hutong`。
- `awiki-me` 当前 E2E 基线目录为 `tests/e2e_test/`，真实实现不放在仓库一级目录。
- `awiki.info` 可通过 SSH alias `ali` 联调，但 Plan 不硬编码远端部署路径。
- Agent IM 生产功能代码已基本完成；本任务重点是建立完整测试与联调闭环。
- Mac 优先落地，Linux 只在平台 adapter 层分叉，scenario 和 CLI 交互复用。
- E2EE 明文由客户端/SDK 持有，MVP Agent 不解密 E2EE 消息。

### 开放问题

- `awiki-me` 当前 UI 是否已经暴露可自动化触发 bootstrap 的稳定入口；若没有，需要 Step 04 设计测试 hook 或 integration entrypoint。
- `awiki-cli-rs2` CLI 是否已有足够命令创建 peer 账号、登录、发送普通消息、发送 E2EE 消息、查询状态；若缺失，Step 03 需要补最小测试入口。
- `awiki.info` 上 Daemon/Hermes 的服务管理方式和日志入口需要在执行期通过 `ssh ali` 发现，不写入仓库绝对路径。
- Delegated key 撤销是否已有公开测试 API；若没有，AIM-E2E-005 可能先落为 manual/nightly gate 或 `awiki-system-test` 服务侧 case。
- 远端环境是否允许测试期间重启 Daemon；若不允许，AIM-E2E-003 需要在本地或独立测试环境覆盖。

### Step 01 基线结论

- `awiki-me` 已有 `awiki.daemon.bootstrap.v1` / `awiki.daemon.user_subkey_package.v2` domain model、普通 payload 发送服务、`#daemon-key-1` 本地校验、MVP action allowlist 和 system/control payload hiding 单测。
- `awiki-me/tests/e2e_test/` 目前只有 desktop/mobile smoke harness；缺少 `--scenario`、`--config`、Agent IM scenario registry、structured report、统一 redaction 和 remote adapter。
- `awiki-cli-rs2` CLI command catalog 已有 `id.register`、`id.recover`、`id.refresh-token`、`msg.send`、`msg.inbox`、`msg.history`，但 `awiki-me` harness 尚未封装 CLI peer 账号与普通消息发送。
- `awiki-deamon` 已有 bootstrap parser、Hermes `app_message_handler` binding、delegated inbox sync、cursor/processed-message/E2EE opaque ignore 与 `message_sync_outbox` 写入；但本次调研未找到完整 pending sync outbox 投递到 App 的 flusher/mark-sent 路径，Step 05/06 需要先证明或补齐。
- `message-service` 已记录 delegated local view 契约并有相关单仓测试；`user-service` 已记录 delegated public key public-only 注册、signed DID Document update 撤销和 registry 管理面边界。
- ANP SDK 依赖边界：本 E2E 主路径应通过 `awiki-cli-rs2` CLI peer 和 App/Daemon 真实路径，不在 `awiki-me` 引入 Python `anp` SDK；若后续依赖本地未发布 ANP 能力，必须在计划中明确 SDK 版本或 local-source gate。

## 5. 总体设计方法

- 设计边界：`awiki-me` 拥有 App E2E 编排与报告；`awiki-cli-rs2` 拥有 CLI peer、im-core、Daemon 行为；服务端仓库拥有 auth/message 行为；`awiki-system-test` 拥有跨服务契约验证。
- 关键决策：首批不另起一套 E2E 框架，而是在 `awiki-me/tests/e2e_test/` 下扩展 scenario；CLI peer 使用 `awiki-cli-rs2`；`awiki.info` remote 联调用 `ssh ali`，但所有证据必须脱敏。
- 兼容性策略：macOS 与 Linux 共享 scenario/config/report/CLI peer，只在 Flutter device、tooling check、xvfb 等 platform adapter 分叉；根级 `integration_test/` 如需新增文件，只保留 shim。
- 数据、协议、配置或迁移策略：新增 example config 只提交占位；local config、测试账号状态、report、日志不提交；协议 schema 按现有 Agent IM 文档，不在 E2E 中发明新 schema。
- 风险控制：每一步一个聚焦 commit；L3 安全 gate 必须覆盖 DID proof、delegated key、E2EE opaque、日志脱敏；remote 不可用时记录 blocker，不伪造通过。

## 6. 任务拆分

| Step | 标题 | 依赖 | 产出 | 小 Plan 文档 | Commit gate | 状态 |
|---|---|---|---|---|---|---|
| 01 | 上下文与契约基线核对 | 无 | 确认测试入口、schema、CLI/Daemon/service 能力缺口；更新必要 docs | [steps/01-context-contract-baseline.md](steps/01-context-contract-baseline.md) | 必须 | done |
| 02 | E2E harness 基础扩展 | Step 01 | scenario registry、agent_im config、report/redaction、remote adapter dry-run | [steps/02-e2e-harness-foundation.md](steps/02-e2e-harness-foundation.md) | 必须 | done |
| 03 | CLI peer 与测试账号编排 | Step 02 | CLI peer workspace、账号登录/恢复、普通消息发送、可选 E2EE 发送能力 | [steps/03-cli-peer-and-test-accounts.md](steps/03-cli-peer-and-test-accounts.md) | 必须 | done |
| 04 | App bootstrap 自动化与 integration entry | Step 02 | App 触发 bootstrap、状态观测、根级 integration shim（如必要） | [steps/04-app-bootstrap-automation.md](steps/04-app-bootstrap-automation.md) | 必须 | done |
| 05 | Agent delegated message E2E 场景 | Step 03, Step 04 | AIM-E2E-001/002/006 首批自动化，003/004 可选扩展 | [steps/05-agent-delegated-message-scenarios.md](steps/05-agent-delegated-message-scenarios.md) | 必须 | done |
| 06 | `awiki.info` 远端联调与服务侧补强 | Step 05 | SSH 联调脚本/Runbook 验证、服务侧日志/测试缺口修复策略 | [steps/06-remote-awiki-info-integration.md](steps/06-remote-awiki-info-integration.md) | 必须 | pending |
| 07 | 最终全局 Review 与整体验证收口 | Step 01-06 | 全量证据、文档同步、最终状态与风险记录 | [steps/07-final-review-verification.md](steps/07-final-review-verification.md) | 如修改文件则必须 | pending |

## 7. 执行台账

状态取值：`pending`、`in_progress`、`review`、`blocked`、`committed`、`done`。

| Step | 状态 | 分支 | 开始时间 | 完成时间 | Commit | Review 证据 | 验证证据 | 下一步 |
|---|---|---|---|---|---|---|---|---|
| 01 | done | `feature/release-0526/agent-im-hutong` | 2026-06-13 20:44:29 +0800 | 2026-06-13 20:47:00 +0800 | `docs: baseline agent im e2e contracts`；短 hash 以本步骤提交后的 `git log -1` 为准 | Review 完成：确认基线覆盖 App bootstrap、CLI peer、Daemon delegated inbox、Message Service delegated local view、User Service delegated public key、system-test 相邻覆盖、ANP SDK 依赖边界和 P0 缺口；未发现需要修改生产代码的问题。 | 文档路径、相对链接、敏感信息扫描、`git diff --check` 均通过；未运行功能测试，原因是 Step 01 为 docs-only/read-only 基线。 | 启动 Step 02 |
| 02 | done | `feature/release-0526/agent-im-hutong` | 2026-06-13 20:52:31 +0800 | 2026-06-13 20:57:55 +0800 | `test: add agent im e2e harness foundation`；短 hash 以本步骤提交后的 `git log -1` 为准 | Review 完成：确认旧 smoke dry-run 保持兼容；新增 scenario/config 仅在显式参数下启用；example config 只含占位和 env 名；report writer 和 command log 统一 redaction；remote adapter 只生成 dry-run plan，不登录远端。 | `dart analyze` No issues；`flutter test tests/unit_test/e2e_harness` 22 passed；`flutter test tests/unit_test` 402 passed；Agent IM dry-run PASS；兼容 dry-run PASS；report sensitive scan 通过。 | 启动 Step 03 |
| 03 | done | `feature/release-0526/agent-im-hutong` | 2026-06-13 21:10:17 +0800 | 2026-06-13 21:13:38 +0800 | `test: add cli peer orchestration`；短 hash 以本步骤提交后的 `git log -1` 为准 | Review 完成：确认 CLI peer adapter 只调用 `awiki-cli-rs2` 命令，不拼 message-service RPC；workspace 按 runId/peer-b 隔离；dry-run 只输出 env 名；command stdout/stderr/report 经过 redaction；未修改 `awiki-cli-rs2`。 | `flutter test tests/unit_test/e2e_harness` 25 passed；`dart analyze` No issues；`cargo build -p awiki-cli --bin awiki-cli` 通过；Agent IM dry-run PASS 并生成 `cli-peer-plan.json`；report sensitive scan 通过。真实 CLI send 未执行，原因是当前未配置 peer 测试账号 env。 | 启动 Step 04 |
| 04 | done | `feature/release-0526/agent-im-hutong` | 2026-06-13 21:21:18 +0800 | 2026-06-13 21:41:58 +0800 | `test: automate agent im app bootstrap`；短 hash 以本步骤提交后的 `git log -1` 为准 | Review 完成：确认 App bootstrap hook 复用生产 `DefaultAgentControlService` 并只替换端口为 fake；根级 `integration_test/` 只有 shim；report 投影显式替换 private package；system/control payload 保持不可渲染；`message.sync` 与 `app.action.result` 可被 App 识别；本步骤未修改生产 `lib/src`。剩余风险：当前为 fake-port App bootstrap smoke，真实远端 Daemon ack、peer message 处理与 App 回传展示仍由 Step 05/06 覆盖。 | `dart analyze` No issues；`flutter test tests/unit_test` 406 passed；`flutter test tests/unit_test/e2e_scenarios/agent_im_app_bootstrap_scenario_test.dart` 通过；`flutter test integration_test/agent_im_delegated_message_e2e_test.dart -d macos` 1 passed；`flutter test integration_test/im_core_open_smoke_test.dart -d macos` 1 passed；Agent IM dry-run PASS 并生成 scenario/cli peer plans；report sensitive scan 通过；`git diff --check` 通过。macOS integration 构建出现既有 duplicate library / newer macOS object / foreground warning，但 exit code 0 且测试通过。 | 启动 Step 05 |
| 05 | done | `feature/release-0526/agent-im-hutong` | 2026-06-13 21:43:09 +0800 | 2026-06-13 21:50:20 +0800 | `test: add agent im delegated message e2e scenario`；短 hash 以本步骤提交后的 `git log -1` 为准 | Review 完成：确认 `agent-im-scenario-result.json` 将 AIM-E2E-001/002/006 与 P1 skeleton 统一记录为 pass/fail/skipped；dry-run 不伪造远端通过；真实 Daemon/Hermes/App summary 证据明确留给 Step 06；redaction scanner 只扫 report 与 CLI log，不误扫 CLI credential store；result/report 经过 redaction。 | `dart analyze` No issues；`flutter test tests/unit_test/e2e_harness tests/unit_test/e2e_scenarios` 28 passed；Agent IM dry-run PASS，生成 `agent-im-scenario-result.json`（pass=1/fail=0/skipped=6）；real E2E skipped：`tests/e2e_test/configs/agent_im_delegated.local.yaml` 不存在；report sensitive scan OK；`git diff --check` OK。 | 启动 Step 06 |
| 06 | pending | `feature/release-0526/agent-im-hutong` | 待执行 | 待执行 | 待填写 | 待填写 | 待填写 | 等待 Step 05 |
| 07 | pending | `feature/release-0526/agent-im-hutong` | 待执行 | 待执行 | 待填写 | 待填写 | 待填写 | 等待 Step 01-06 |

Step 01 观测到的仓库状态详见 [context-contract-baseline.md](context-contract-baseline.md#2-仓库状态基线)：`awiki-me` 仅纳入本计划目录；`awiki-cli-rs2` 与 `message-service` 有既有未提交变更，本步骤不修改；`awiki-system-test` 与 `user-service` 干净。后续每个 Step 前仍必须重新运行并记录相关仓库 `git status --short --branch`。

## 8. Codex Goal 执行协议

- 将本 Plan 作为执行进度的唯一事实来源。
- 启动或恢复前，读取本 Plan、当前小 Plan、执行台账、[README.md](README.md)、[scenario-matrix.md](scenario-matrix.md)、[remote-awiki-info-runbook.md](remote-awiki-info-runbook.md) 和当前 `git status`。
- 同一时间只执行一个步骤；Step 03 与 Step 04 只有在 Step 02 完成后才可并行，但默认仍串行执行。
- 恢复时，从第一个状态不是 `done` 的步骤继续。
- 每个步骤依次执行：标记 `in_progress`、实现、验证、Review、修复 Review 发现、提交、记录证据、标记 `done`。
- 上一个依赖步骤的完成工作未提交前，不要开始下一个依赖步骤。
- 改变范围、顺序、验收标准、公开契约、数据模型或验证策略前，先更新本 Plan 的变更记录。
- 远端 `ssh ali` 联调只收集脱敏证据；不要在 Plan、commit、日志或最终回复中输出密钥、JWT、私钥、OTP 值。

## 8.1 Codex Goal 提示词

```text
请以 `awiki-me/docs/agent-im-delegated-message-e2e-test-plan/plan.md` 为唯一规划入口，按文档执行 Agent IM 委托消息处理 E2E 测试落地。

开始前先读取：
- `awiki-me/docs/agent-im-delegated-message-e2e-test-plan/plan.md`
- 当前第一个未 done 的 Step 文档
- `awiki-me/docs/agent-im-delegated-message-e2e-test-plan/README.md`
- `awiki-me/docs/agent-im-delegated-message-e2e-test-plan/scenario-matrix.md`
- `awiki-me/docs/agent-im-delegated-message-e2e-test-plan/remote-awiki-info-runbook.md`
- 当前相关仓库 `git status --short --branch`

请从第一个状态不是 `done` 的步骤开始，一次只执行一个步骤。每步都要按对应小 Plan 实现、验证、Review、修复或记录 Review 发现，然后创建一个聚焦 commit，并回填主 Plan 执行台账和 Step 执行状态。需要改变范围、顺序、验收标准、公开契约、数据模型或验证策略时，先更新 Plan 变更记录。

所有步骤完成后，执行最终全局 Review 和整体验证，记录实际命令、通过/失败/跳过数量、失败或跳过原因、剩余风险和最终工作区状态。

核心注意点：基于现有 `awiki-me/tests/e2e_test/` 框架扩展；CLI peer 使用 `awiki-cli-rs2`；`awiki.info` 通过 `ssh ali` 联调；MVP 只验证普通非 E2EE 消息进入 Agent；严禁日志和报告泄漏私钥、JWT、token、OTP 或 E2EE 明文。
```

## 9. 小 Plan 摘要

### Step 01：上下文与契约基线核对

- 小 Plan：[steps/01-context-contract-baseline.md](steps/01-context-contract-baseline.md)
- 基线输出：[context-contract-baseline.md](context-contract-baseline.md)
- 目标：确认现有代码、schema、CLI、Daemon、service 能力与测试缺口。
- 设计方法：只读调研优先，先冻结测试契约和缺口清单。
- 实现方法：读取目标 docs、代码入口、现有测试，必要时更新测试方案 docs。
- 路径：`awiki-me/docs/agent-im-delegated-message-e2e-test-plan/`、`awiki-me/tests/e2e_test/`、`awiki-cli-rs2/docs/agent-im/`。
- 验证方式：文档路径和链接检查；不运行功能测试。
- Review 环节：确认没有把 Harness 摘要当 API 真相源，没有遗漏安全边界。
- Commit 要求：docs-only 或调研输出独立 commit。
- 风险：上下文漂移；通过记录 git status 和权威 docs 缓解。

### Step 02：E2E harness 基础扩展

- 小 Plan：[steps/02-e2e-harness-foundation.md](steps/02-e2e-harness-foundation.md)
- 目标：让桌面 E2E runner 支持 Agent IM scenario、config、report、redaction 和 remote adapter dry-run。
- 设计方法：复用 `desktop_e2e_runner.dart`，只把共用能力抽象到 `harness/src/`。
- 实现方法：新增 config parser、scenario registry、report writer、secret redactor、remote adapter。
- 路径：`awiki-me/tests/e2e_test/harness/`、`awiki-me/tests/e2e_test/configs/`、`awiki-me/tests/unit_test/e2e_harness/`。
- 验证方式：`dart analyze`、`flutter test tests/unit_test`、desktop runner dry-run。
- Review 环节：重点看跨平台复用、脱敏、local config 不提交。
- Commit 要求：一个 `test:` 或 `e2e:` 聚焦 commit。
- 风险：runner 过早复杂化；首批只实现最小 scenario registry。

### Step 03：CLI peer 与测试账号编排

- 小 Plan：[steps/03-cli-peer-and-test-accounts.md](steps/03-cli-peer-and-test-accounts.md)
- 目标：建立可复用 CLI peer workspace 与测试账号登录/发送消息能力。
- 设计方法：CLI 作为对端，账号与 workspace 完全隔离。
- 实现方法：扩展 harness 调用 `awiki-cli-rs2/target/debug/awiki-cli` 的 init/login/send/status；缺口回到 CLI repo 补最小接口。
- 路径：`awiki-me/tests/e2e_test/harness/`、`awiki-cli-rs2/crates/awiki-cli/`、`awiki-cli-rs2/crates/im-core/`。
- 验证方式：CLI dry-run、CLI focused tests、redaction scan。
- Review 环节：重点看账号状态隔离、OTP/token 不输出、CLI 不绕过 im-core。
- Commit 要求：按仓库拆 commit；跨仓同步记录台账。
- 风险：CLI 命令不完整；可先实现 ordinary message P0。

### Step 04：App bootstrap 自动化与 integration entry

- 小 Plan：[steps/04-app-bootstrap-automation.md](steps/04-app-bootstrap-automation.md)
- 目标：让 E2E 能稳定触发 App bootstrap 并观测结果。
- 设计方法：优先走真实 UI / integration entry；必要时新增测试专用 entrypoint，但不污染生产行为。
- 实现方法：补 App scenario hook、状态查询、可选 root integration shim。
- 路径：`awiki-me/tests/e2e_test/scenarios/`、`awiki-me/tests/integration_test/`、`awiki-me/integration_test/`、`awiki-me/lib/src/`。
- 验证方式：Flutter integration smoke、unit/widget tests、desktop dry-run。
- Review 环节：重点看 private package 不进 UI/log、system payload 不进聊天。
- Commit 要求：App 侧聚焦 commit。
- 风险：UI 自动化不稳定；可用 integration entry 先覆盖状态闭环。

### Step 05：Agent delegated message E2E 场景

- 小 Plan：[steps/05-agent-delegated-message-scenarios.md](steps/05-agent-delegated-message-scenarios.md)
- 目标：实现首批 P0 场景 AIM-E2E-001/002/006，并为 P1 场景预留扩展。
- 设计方法：按 scenario matrix 编排 App、CLI peer、remote observability。
- 实现方法：新增 `agent_im_delegated_message` scenario，写入 report 和 evidence template。
- 路径：`awiki-me/tests/e2e_test/scenarios/agent_im_delegated_message/`、`awiki-me/tests/e2e_test/harness/`。
- 验证方式：macOS dry-run、macOS real E2E、unit tests、redaction scan。
- Review 环节：重点看去重、幂等、脱敏、普通/E2EE 边界。
- Commit 要求：scenario 聚焦 commit。
- 风险：远端服务不可用；记录 blocker 和可替代 dry-run 证据。

### Step 06：`awiki.info` 远端联调与服务侧补强

- 小 Plan：[steps/06-remote-awiki-info-integration.md](steps/06-remote-awiki-info-integration.md)
- 目标：把本地 E2E 与 `ssh ali` 远端日志、部署版本和服务健康证据打通。
- 设计方法：先观测和脱敏；只有发现真实服务端缺口才修改服务端仓库。
- 实现方法：按 runId 收集 User Service、Message Service、Daemon、Hermes 证据；必要时补服务端测试或日志。
- 路径：`awiki-me/docs/agent-im-delegated-message-e2e-test-plan/remote-awiki-info-runbook.md`、`awiki-cli-rs2/`、`message-service/`、`user-service/`、`awiki-system-test/`。
- 验证方式：remote health/log evidence、相关服务 repo tests、focused system test。
- Review 环节：重点看不泄密、部署/回滚可追踪、服务端改动不破坏契约。
- Commit 要求：每个受影响仓库独立 commit。
- 风险：远端生产状态不可控；必要时请求用户确认部署窗口。

### Step 07：最终全局 Review 与整体验证收口

- 小 Plan：[steps/07-final-review-verification.md](steps/07-final-review-verification.md)
- 目标：完成所有 step 后做全局 Review、整体验证、文档和台账收口。
- 设计方法：从 changed files、contracts、tests、security、docs、git status 六条线核对。
- 实现方法：运行最终验证命令，回填 plan/evidence，修复或记录剩余风险。
- 路径：本目录全部文档、所有受影响仓库的 docs/tests/source。
- 验证方式：`dart analyze`、`flutter test tests/unit_test`、desktop E2E、相关 cargo/pytest/system tests。
- Review 环节：全局 Review 必须覆盖安全 / 隐私和 E2EE 边界。
- Commit 要求：如本步骤修改文件，创建最终集成 docs/test commit。
- 风险：跨仓状态混乱；通过每仓 `git status` 和 commit hash 记录缓解。

## 10. Review 策略

- 每步骤 Review：实现完成后、commit 前进行，重点看正确性、回归、公开契约、测试覆盖、文档漂移和安全隐私。
- 全局 Review：Step 07 执行，覆盖所有仓库、测试、远端证据、执行台账、剩余风险。
- 契约 / 安全 / 隐私 Review：重点检查 DID Document delegated public key、proof 校验、private package 生命周期、token/OTP redaction、E2EE opaque 边界。
- 文档 Review：检查 `README.md`、`scenario-matrix.md`、`remote-awiki-info-runbook.md`、`evidence-template.md`、本 Plan 和 Step 文档是否与实际实现一致。

## 11. 验证策略

| 层级 | 命令 / 检查 | 预期证据 |
|---|---|---|
| Docs | `cd awiki-me && find docs/agent-im-delegated-message-e2e-test-plan -type f -name '*.md' -print`；人工检查相对链接 | 文档存在，链接可读，未出现本机绝对路径或敏感值。 |
| Unit | `cd awiki-me && flutter test tests/unit_test` | harness parser、redaction、scenario planner 单元测试通过。 |
| Analyze | `cd awiki-me && dart analyze` | 无新增 analyze 错误。 |
| Integration | `cd awiki-me && flutter test integration_test/im_core_open_smoke_test.dart -d macos`；如新增 shim，再跑对应 shim | macOS native/integration smoke 通过。 |
| Desktop E2E dry-run | `cd awiki-me && dart run tests/e2e_test/harness/desktop_e2e_runner.dart --platform=macos --scenario=agent-im-delegated-message --config tests/e2e_test/configs/agent_im_delegated.example.yaml --dry-run` | 打印计划命令、生成 report，不执行真实远端写操作。 |
| Desktop E2E real | `cd awiki-me && dart run tests/e2e_test/harness/desktop_e2e_runner.dart --platform=macos --scenario=agent-im-delegated-message --config tests/e2e_test/configs/agent_im_delegated.local.yaml` | AIM-E2E-001/002/006 通过；失败/跳过有原因。 |
| CLI / Daemon | `cd awiki-cli-rs2 && cargo test -p awiki-deamon --locked`；必要时 `cargo test -p im-core --locked` | delegated inbox、message agent、schema/action 相关 tests 通过。 |
| Message Service | `cd message-service && cargo test --workspace` | delegated proof/fanout/E2EE opaque 相关测试不回归。 |
| User Service | `cd user-service && uv run pytest tests/app/did -v` | DID Document public method/authentication 相关测试通过。 |
| System / E2E | `cd awiki-system-test && AWIKI_SYSTEM_TEST_MODE=remote E2E_DID_DOMAIN=awiki.info E2E_USER_SERVICE_URL=https://awiki.info E2E_MESSAGE_SERVICE_URL=https://awiki.info E2E_MESSAGE_SERVICE_WS_URL=wss://awiki.info/im/ws AWIKI_CLI_RUST_REPO=../awiki-cli-rs2 uv run awiki-system-test --show-command` | 如服务侧契约受影响，记录通过/失败/跳过数量和 remote 环境变量。 |
| Security | 扫描 `.e2e` report、CLI workspace、App logs、远端脱敏日志 | 不包含私钥、JWT、token、OTP、raw private package、E2EE 明文。 |

如果某个命令不能运行，执行者必须记录原因、影响和替代证据，不得省略。

## 12. 文档更新

- Harness 文档：只有当跨仓架构、规则或索引发生变化时才更新 `awiki-harness/`；本计划本身不要求更新 Harness。
- 子仓库文档：本次方案放在 `awiki-me/docs/agent-im-delegated-message-e2e-test-plan/`；如果后续修改 `awiki-cli-rs2` Agent IM 契约或服务端 API，必须同步更新对应仓库 docs。
- 本次生成的任务文档：`README.md`、`scenario-matrix.md`、`remote-awiki-info-runbook.md`、`evidence-template.md`、`plan.md`、`steps/*.md`。

## 13. Commit 计划

- 每个完成、验证、Review 通过的步骤创建一个聚焦 commit。
- Commit 前记录 `git status --short --branch` 和纳入文件。
- Commit 后记录 commit hash 和工作区状态。
- 跨仓变更按仓库独立 commit；如果两个仓库必须同步才能编译或运行，台账要记录 commit 顺序和兼容原因。
- 不要把所有步骤的修改积累到一个最终大 commit。
- 规划文档本身可作为 docs-only commit，后续实现按 Step 分 commit。

## 14. Blocked 处理

| Blocker | Step | 证据 | 已尝试方案 | 影响范围 | 下一步决策 |
|---|---|---|---|---|---|
| `ssh ali` 不可连接 | 06 | 待执行时记录 SSH 错误 | 本地 dry-run、unit、integration 继续；远端证据标 blocked | 当前步骤 / remote gate | 等待远端恢复或用户提供替代联调入口 |
| CLI 缺少必要登录或发送命令 | 03 | 待记录 CLI help / test 失败 | 补最小 CLI peer 命令或用现有 im-core 测试 helper | 当前步骤 | 更新 Step 03 scope 后实现 |
| App 无稳定 bootstrap 自动化入口 | 04 | 待记录 UI/integration 探查结果 | 新增 test-only integration entry 或稳定语义按钮定位 | 当前步骤 | 更新 Step 04 设计并 Review 安全边界 |
| 远端 Daemon/Hermes 未部署对应功能 | 05/06 | remote version / log evidence | 请求部署窗口或在独立环境验证 | 整体 E2E | 用户确认后部署或标记 blocked |
| Delegated proof 返回 401/invalid token | 05/06 | Message Service/User Service/Daemon logs | 二分 DID Document、proof、owner、key fragment、scope | 当前场景 | 修复测试数据或服务端缺口 |

- 只有依赖允许且风险已记录时，才继续另一个 pending 步骤。
- 只有没有安全假设、回退方案或独立下一步时，才询问用户。

## 15. Plan 变更记录

| 日期 | 变更 | 原因 | 影响步骤 | 是否需要 Review |
|---|---|---|---|---|
| 2026-06-13 | 创建 Agent IM 委托消息处理 E2E 测试方案与落地 Plan | 用户要求把方案写入 `awiki-me/docs/` 并使用 `awiki-plan` 整理详细计划 | 全部 | 是 |

## 16. 风险与回滚

| 风险 | 缓解措施 | 回滚 / 回退方案 |
|---|---|---|
| E2E 泄漏私钥、JWT、OTP 或 raw private package | 统一 redaction、report 扫描、Review gate；文档只记录 env 名 | 立即删除泄漏 report，轮换测试凭证，修复 redactor 后重跑 |
| 远端 `awiki.info` 状态不稳定 | runId 关联证据，记录服务版本和健康状态 | 标记 remote gate blocked，用 dry-run/local/system-test 替代证据暂存 |
| CLI/App/Daemon 契约漂移 | Step 01 建立契约基线，Step 07 全局 Review | 回滚不兼容 commit，更新 Plan 后重新分步实现 |
| E2EE 边界被误测为 Agent 可读明文 | P1 专门测试 opaque ignored；Review 强制检查 Hermes prompt | 回滚相关行为，恢复 Agent 不处理 E2EE 明文 |
| Linux 复用失败导致复制一套 harness | 平台 adapter-only 原则；unit test 覆盖 config/scenario planner | 回退到 Mac 首发，Linux adapter 独立后续 step，不复制业务 scenario |
| 远端服务端临时 hotfix 无法追踪 | 必须本地 commit 后部署；记录部署 commit 和回滚方式 | 回滚远端部署到上一个已知版本，Plan 标记风险 |

## 17. 最终全局 Review 与整体验证

- 触发条件：Step 01-06 完成、Review、验证并提交后执行。
- Review 范围：`awiki-me` E2E harness/scenario/config/report、`awiki-cli-rs2` CLI/Daemon/im-core 改动、`message-service`/`user-service` 服务端改动、`awiki-system-test` 覆盖、所有文档和执行台账。
- 重点关注：跨步骤一致性、回归风险、兼容性、安全 / 隐私、E2EE boundary、文档漂移、未提交变更、每个步骤 Review 发现是否已解决或记录。
- 整体验证命令 / 检查：按第 11 节执行；无法运行项必须记录原因和替代证据。
- Review 发现：待执行时填写。
- 已修复问题：待执行时填写。
- 剩余风险：待执行时填写。
- 最终证据：待执行时填写 `evidence-template.md` 对应信息。
- 最终 `git status`：待执行时填写所有受影响仓库 `git status --short --branch`。
- 如果本阶段修改文件：记录 Review、验证和最终集成 commit。
