# Plan：AWiki Me E2E 自动化与回归测试体系完善方案

状态：in_progress  
DOC：`test-awiki-me/docs/e2e/awiki-me-e2e-regression-plan/`  
Harness：`awiki-harness/`  
创建时间：2026-06-14  
恢复指针：Step 01 已完成；下一次从 Step 02 开始，先读取 [steps/02-scenario-matrix-tags.md](steps/02-scenario-matrix-tags.md)。

## 1. 目标

- 任务目标：在 `test-awiki-me` 当前测试框架基础上，设计一套可持续扩展的 E2E 测试方案，让后续新增功能时既能自动验证当前功能，又能回归保护既有核心能力。
- 预期行为：后续执行本方案后，PR 能运行确定性的本地/CI gate，nightly 或 release 能运行真实后端、真实账号、App + CLI peer、桌面和移动端的 E2E 场景，并输出可追踪、可脱敏、可复查的测试证据。
- 非目标：本方案不补大量测试实现，不把真实后端 + OTP 的 E2E 放入普通 PR required gate，不在 UI E2E 里重复实现复杂协议/加密验证，不提交 `.env`、OTP、JWT、私钥、CLI workspace、`.e2e/` 报告或本地设备状态。
- 完成标准：形成一份主 Plan 和分步骤小 Plan，明确当前测试基线、场景矩阵、测试环境契约、桌面/移动 E2E 分层、CI/nightly/release gate、Review 与验证标准，后续 Codex 可以按文档逐步执行。

## 2. Harness 上下文

| 来源 | 作用 |
|---|---|
| `awiki-harness/AGENTS.md` | 确认 Harness 是多仓库控制面，子仓库仍是实现权威。 |
| `awiki-harness/README.md` | 确认文档边界和读取顺序。 |
| `awiki-harness/context/00-context-map.md` | 将任务路由到 Client Architecture、Message Flow、Protocol、System Test。 |
| `awiki-harness/context/02-repo-map.md` | 确认 `test-awiki-me`、`awiki-cli-rs2`、`user-service`、`message-service`、`awiki-system-test` 职责。 |
| `awiki-harness/context/03-cross-repo-architecture.md` | 确认 App、Dart SDK、Rust `im-core`、CLI、Daemon、message-service 的依赖方向。 |
| `awiki-harness/context/20-rules-index.md` | 确认文档、架构、AI coding、验证规则入口。 |
| `awiki-harness/context/30-tools-env.md` | 确认 Flutter、Rust CLI、system-test 常用命令。 |
| `awiki-harness/context/40-verification.md` | 确认 E2E 相关任务需要 L2/L3 验证证据。 |
| `awiki-harness/context/50-task-workflow.md` | 确认 Plan、执行台账、验证证据和 blocker 处理方式。 |
| `awiki-harness/context/nodes/client-architecture.node.md` | 确认 App/CLI 都应通过 `im-core`/SDK 高层能力，不直接拼 message-service wire payload。 |
| `awiki-harness/context/nodes/message-flow.node.md` | 确认 v2 message-service 与 legacy `molt-message` 边界，E2E 不能按旧服务行为推断。 |
| `awiki-harness/context/nodes/system-test.node.md` | 确认跨服务测试和本地环境清理要求。 |

## 3. 当前基线

| 区域 | 当前状态 | 对本方案的影响 |
|---|---|---|
| 单元/Widget/Provider 测试 | `test-awiki-me/tests/unit_test/` 已覆盖 application、data、im-core、harness parser 等快速测试。 | PR required gate 应继续以这层为基础，保证新增功能有快速回归。 |
| Flutter integration smoke | 根级 `test-awiki-me/integration_test/*.dart` 是 Flutter tooling shim，真实实现位于 `test-awiki-me/tests/integration_test/`。 | 桌面 smoke 继续通过 shim 跑 macOS/Linux，不能把实现移回根目录。 |
| Linux Desktop runner/native smoke | `docs/testing.md` 已记录 Linux runner、`xvfb-run`、`im_core_open_smoke_test.dart`、`AWIKI_SQLITE3_SOURCE_DIR` 等约束。 | Linux 可以纳入确定性 smoke gate；真实 E2E 仍需要后端账号和服务配置。 |
| Desktop App + CLI peer smoke | `test-awiki-me/integration_test/desktop_cli_peer_smoke_test.dart` 已存在，默认 `AWIKI_E2E` 未开启时 skip。 | 可以作为真实桌面 E2E 的起点，后续扩展场景时不要绕过 App/CLI 正常边界。 |
| Desktop E2E runner | `test-awiki-me/tests/e2e_test/harness/desktop_e2e_runner.dart` 支持 `--platform=macos|linux`、dry-run、CLI build、scenario config、report/redaction。 | macOS/Linux 应共享 scenario、config、CLI peer 和 report，仅 platform adapter 分叉。 |
| Mobile E2E | `test-awiki-me/tests/e2e_test/harness/mobile_e2e_runner.dart` 和 Maestro flows 已存在，example config 支持 iOS/Android 两设备。 | 移动真实 E2E 需要设备池/模拟器池，适合 nightly/release，不适合默认 PR required gate。 |
| 后端和账号 | `user-service/.env` 本地可提供非生产测试 OTP key；文档只记录 env 名，不记录值。 | 真实 E2E 可以使用非生产账号池，但必须脱敏、隔离状态、避免 OTP 耗尽。 |

### 3.1 Step 01 覆盖地图

| 能力域 | 当前入口 | 当前覆盖 | 性质 | 缺口 / 后续动作 |
|---|---|---|---|---|
| App shell / onboarding shell | `test-awiki-me/tests/integration_test/app/app_smoke_test.dart`；root shim `test-awiki-me/integration_test/app_smoke_test.dart` | fake bootstrap 下验证 AppShell、OnboardingPage、authenticated shell。 | 确定性 integration smoke；无真实后端。 | Step 04 固化 macOS/Linux smoke gate；不扩展为真实 E2E。 |
| Native SDK open | `test-awiki-me/tests/integration_test/native/im_core_open_smoke_test.dart`；root shim `test-awiki-me/integration_test/im_core_open_smoke_test.dart` | 临时目录中打开 `AwikiImCore.open`，验证 native backend 和路径。 | 确定性 desktop native smoke；macOS/Linux。 | Step 04 继续保留 Linux `xvfb-run` 和 `AWIKI_SQLITE3_SOURCE_DIR` 前提。 |
| 账号注册 / 恢复 | `test-awiki-me/integration_test/desktop_cli_peer_smoke_test.dart`；`test-awiki-me/tool/desktop_cli_peer_e2e_runner.dart` | App 侧通过 `OnboardingService.recoverHandle` / `registerHandleWithPhone`；CLI peer 侧通过 `id recover` / `id register`。 | 真实后端 E2E 前置；默认 `AWIKI_E2E` 未开启时 skip。 | Step 03/05 梳理账号池、env、local state 隔离和失败证据。 |
| Direct App -> CLI | `test-awiki-me/integration_test/desktop_cli_peer_smoke_test.dart` | App 发送 runId 文本，CLI `msg history --with` 轮询确认。 | 真实 Desktop App + CLI peer E2E；manual/nightly/release。 | Step 05 增强报告、去重和失败诊断；不进入普通 PR required gate。 |
| Direct CLI -> App | `test-awiki-me/integration_test/desktop_cli_peer_smoke_test.dart` | CLI `msg send`，App `MessagingService.loadHistory` 轮询确认。 | 真实 Desktop App + CLI peer E2E；manual/nightly/release。 | Step 05 增加会话刷新、history/inbox 基础回归。 |
| 会话 history / inbox / 去重 | `desktop_cli_peer_smoke_test.dart` 有基础 history 轮询；`tests/unit_test/conversation_workspace_test.dart` 有 UI/fake 覆盖。 | 已有 service-level history 检查和 widget fake 回归。 | 部分覆盖；真实 E2E 不完整。 | Step 05 补真实 runId 去重、刷新、既有会话不被破坏的回归断言。 |
| 群组创建 / 加入 / 成员 | `tests/unit_test/group_flow_test.dart`；`tests/unit_test/conversation_workspace_test.dart` | fake gateway 下覆盖创建群、通过 Group DID 加入、群详情 DID、成员列表、添加成员失败等。 | Unit/widget fake 覆盖；无真实 E2E。 | Step 06 补最小两人群真实 E2E：创建/加入、成员可见、群内双向文本。 |
| 群组消息互通 | `tests/unit_test/group_flow_test.dart` 和 chat/group UI fake 覆盖相邻行为。 | 尚无 App + CLI peer 或双设备真实群消息互通。 | 缺口。 | Step 06 设计 `GROUP-E2E-002`，必要时记录 CLI/SDK 群组能力 blocker。 |
| 附件发送 / 接收 | `lib/src/application/models/attachment_models.dart` 被 Agent IM bootstrap scenario 引用；全局搜索未发现独立基础附件 E2E。 | 尚无基础 App/peer 附件真实 E2E；只有相邻模型或场景内部引用。 | 缺口。 | Step 06 补小型 fixture、metadata/hash/download 状态方案；如 CLI/SDK 暂缺命令，记录 blocker 或补最小高层能力。 |
| Profile / Settings | `tests/unit_test/profile_page_test.dart`；`tests/unit_test/settings_page_test.dart`；`tests/unit_test/profile_provider_test.dart` | fake-backed 覆盖 profile 编辑/展示、homepage fallback、settings 语言/凭证/更新入口等。 | Unit/widget fake 覆盖；无 desktop integration smoke。 | Step 04 可补 no-backend profile/settings smoke；Step 08 决定是否进 PR optional。 |
| Mobile 两设备消息 | `tests/e2e_test/harness/mobile_e2e_runner.dart`；`tests/e2e_test/mobile/maestro/*.yaml`；`tests/e2e_test/configs/mobile.example.yaml` | Runner 支持 dry-run、构建、两设备登录、A->B / B->A 消息 flow。 | dry-run 已有；real run 依赖设备池、Maestro、后端和账号。 | Step 07 梳理设备池、real run 证据、报告脱敏和 skipped/blocker。 |
| Agent 作为 IM App 处理者 | `tests/e2e_test/scenarios/agent_im_delegated_message/`；`tests/e2e_test/configs/agent_im_delegated.example.yaml`；`integration_test/agent_im_delegated_message_e2e_test.dart` | 已有独立 Agent IM P0 框架和历史完成证据。 | 本轮 `Skipped`。 | 保留 `AGENT-SKIP-001`，不实现、不运行、不进 gate、不要求验证证据。 |
| 端到端加密 | `awiki-system-test` 和相关 SDK/服务测试方向。 | 本计划不盘点具体 E2EE 细节。 | 本轮 `Skipped`。 | 保留 `E2EE-SKIP-001`，后续单独方案处理。 |

## 4. 影响分析

| 领域 / 仓库 / 模块 | 影响 | 权威文档或代码 |
|---|---|---|
| `test-awiki-me` E2E 文档 | 新增 E2E 回归体系方案、场景矩阵、执行步骤。 | `test-awiki-me/docs/testing.md`、本目录 |
| `test-awiki-me/tests/e2e_test/` | 后续扩展 scenario registry、desktop/mobile runner、config、report、redaction、test tags。 | `test-awiki-me/tests/e2e_test/README.md` |
| `test-awiki-me/tests/integration_test/` | 后续扩展 deterministic desktop smoke，不放真实多客户端后端闭环。 | `test-awiki-me/tests/integration_test/README.md` |
| `test-awiki-me/integration_test/` | 继续作为 Flutter tool root shim；真实 desktop E2E 入口可放 shim。 | Flutter `integration_test` 工具约束 |
| `awiki-cli-rs2` | 作为 CLI peer 和 native SDK 权威路径。 | `awiki-cli-rs2/docs/architecture/im-core-sdk-architecture.md`、`awiki-cli-rs2/docs/api/im-core-interface/` |
| `user-service` | 提供非生产测试账号、OTP、DID/Handle/User Service。 | `user-service/.env`、`user-service/docs/api/` |
| `message-service` | 提供 v2 `/im/rpc`、direct/group/attachment fanout、history、inbox 等消息能力。 | `message-service/docs/api/`、`message-service/docs/architecture/` |
| `awiki-system-test` | 承担协议、群组、附件、跨服务契约的 focused system tests，不把全部压力压到 UI E2E。 | `awiki-system-test/README.md`、`awiki-system-test/docs/` |

## 5. 假设与开放问题

### 假设

- 当前执行仓库为 `test-awiki-me`，后续实现仍遵守三层测试目录：`tests/unit_test/`、`tests/integration_test/`、`tests/e2e_test/`。
- macOS 与 Linux Desktop 复用同一套 E2E scenario 和 CLI peer；Linux 仅增加 `xvfb-run`、Linux runner/native SDK、SQLite source 等平台条件。
- 对端优先使用 `awiki-cli-rs2` 的 `awiki-cli`，不新增测试专用 mock peer。
- UI/App E2E 不使用 `ModMessage` 或静态测试数据伪造消息成功；真实闭环应通过 App 的正常 onboarding/messaging 边界和 CLI peer/服务证据验证。
- 复杂协议、DID proof、服务端 fanout 和存储契约优先由 `awiki-cli-rs2`、`message-service`、`awiki-system-test` 的单元/系统测试覆盖；App E2E 只验证用户可见关键路径和跨端互通。
- 端到端加密本轮列为 `Skipped`，不实现、不进 gate、不要求验证证据；后续如果要做，应另起独立方案和 gate。
- Agent 作为 IM App 处理者的互通场景本轮列为 `Skipped`，保留在场景矩阵中作为后续项；本轮只补齐基础 App/消息/群组/附件回归用例。

### 开放问题

- 测试账号池是否可以提供至少两组稳定非生产账号，分别给 App 端和 CLI/mobile peer 端复用。
- nightly 环境是否使用远端 `awiki.info`，还是先使用本地 `awiki-system-test` 管理的 message-service v2 拓扑。
- App 当前 UI selectors 是否足够支持更完整的聊天、设置、profile 回归；不足时需要新增稳定 semantics，但不应为测试改变生产行为。
- 移动端设备池由本地模拟器、CI self-hosted runner，还是人工 release 机负责。

## 6. 总体设计方法

- 分层 gate：PR 只跑确定性测试和 dry-run；真实后端、OTP、App + CLI peer、移动双设备 E2E 放 manual/nightly/release。
- 桌面优先：先把 macOS/Linux Desktop App + CLI peer 的最小闭环稳定下来，再扩展群组、附件和移动双设备基础场景。
- 当前功能与回归分离：每个 E2E case 标注 `feature`、`regression`、`smoke`、`nightly`、`release`，新增功能先加 feature case，稳定后提升为 regression case。
- 真实闭环优先：真实 E2E 必须至少跨越 App、SDK/native、User Service、Message Service、CLI peer 或移动 peer，不用纯 fixture 声称端到端通过。
- 观察性优先：所有真实 E2E 输出 runId、timings、scenario result、CLI/App/remote evidence 和 redaction scan 结果。
- 安全优先：报告和日志只能记录 env 名、脱敏路径、脱敏 handle 或 runId，不记录 OTP 值、JWT、私钥、raw local state。
- 兼容性优先：不要为了 Linux 或测试方便改动 Android/iOS/macOS/web runner；不要让 App/CLI 绕过 `im-core` 直接操作 service wire payload。

## 7. 分层测试策略

| 层级 | 名称 | 运行时机 | 覆盖内容 | 是否依赖真实后端 |
|---|---|---|---|---|
| L0 | Docs / plan checks | 文档变更 PR | 文档路径、链接、敏感信息扫描、方案一致性。 | 否 |
| L1 | Unit / Widget / Harness dry-run | 每个 PR required | Dart service、provider、widget、mapper、E2E runner parser、dry-run。 | 否 |
| L2 | Desktop deterministic integration smoke | PR optional 或 self-hosted required | App shell、Linux/macOS runner、native SDK open、基础 profile/settings smoke。 | 否 |
| L3 | Desktop real App + CLI peer E2E | nightly/manual/release | 账号恢复/注册、App->CLI、CLI->App、history/inbox、回归消息路径。 | 是 |
| L4 | Group / Attachment E2E | nightly/release | 群组创建、群成员消息、附件发送/接收、基础错误回归。 | 是 |
| L5 | Mobile two-device E2E | nightly/release | iOS/Android 双设备登录、发消息、收消息、基础回归。 | 是 |
| Skipped | Deferred scenarios | 本轮不运行 | Agent 作为 IM App 处理者、端到端加密。 | 不要求 |

## 8. 场景矩阵

| Case ID | 场景 | 目标 | 平台 | Gate | 当前基础 | 后续重点 |
|---|---|---|---|---|---|---|
| `APP-SMOKE-001` | App shell 启动 | 验证 App bootstrap、Shell、基础页面可启动。 | macOS/Linux | PR optional | `app_smoke_test.dart` | 保持确定性，不接真实后端。 |
| `SDK-SMOKE-001` | Native SDK open | 验证 `AwikiImCore.open` 和 native library 加载。 | macOS/Linux | PR optional | `im_core_open_smoke_test.dart` | Linux 下继续固定 `AWIKI_SQLITE3_SOURCE_DIR` 约束。 |
| `AUTH-E2E-001` | App 注册/恢复测试账号 | 验证 User Service、OTP、DID/Handle、App session。 | macOS/Linux | Nightly | `desktop_cli_peer_smoke_test.dart` 内已有准备逻辑 | 拆成可复用账号准备步骤，失败证据脱敏。 |
| `MSG-E2E-001` | App -> CLI direct message | 验证 App 发送真实消息，CLI peer 能查到 history/inbox。 | macOS/Linux | Nightly/Release | `desktop_cli_peer_smoke_test.dart` | 增加 runId、重试、去重和报告字段。 |
| `MSG-E2E-002` | CLI -> App direct message | 验证 CLI peer 发送真实消息，App 能通过正常消息服务读到。 | macOS/Linux | Nightly/Release | `desktop_cli_peer_smoke_test.dart` | 扩展到 UI 可见断言或稳定 service-level 断言。 |
| `MSG-REG-001` | 会话回归 | 验证 history、刷新、无重复、既有会话不被新消息破坏。 | macOS/Linux | Nightly | 待补 | 先用 App service boundary，UI 稳定后提升为 UI E2E。 |
| `GROUP-E2E-001` | 创建群组并添加成员 | 验证 App 创建群组、邀请/添加 CLI peer 或第二账号、群资料可见。 | macOS/Linux | Nightly/Release | 待补 | 先覆盖最小两人群，避免一次做复杂群管理矩阵。 |
| `GROUP-E2E-002` | 群组消息互通 | 验证 App 在群内发送消息，peer 能看到；peer 在群内发送消息，App 能看到。 | macOS/Linux | Nightly/Release | 待补 | 使用 runId，断言成员视角和 history 一致。 |
| `GROUP-REG-001` | 群组基础回归 | 验证群名/头像或基础资料、成员列表、退出/解散前的只读回归。 | macOS/Linux/mobile | Nightly | unit/widget 有部分基础 | 首批只做最小关键路径，避免脆弱 UI 全量覆盖。 |
| `ATTACH-E2E-001` | App -> peer 附件发送 | 验证 App 发送小文件/图片附件后，peer 能通过 CLI 或服务侧 history 看到附件 metadata 并下载/读取。 | macOS/Linux | Nightly/Release | 待补 | 使用小型测试 fixture，校验文件名、大小、hash 或内容摘要。 |
| `ATTACH-E2E-002` | peer -> App 附件接收 | 验证 CLI peer 发送附件后，App 能在会话中看到附件并完成基础打开/下载状态断言。 | macOS/Linux | Nightly/Release | 待补 | 先做小文件，后续再扩展图片、失败重试和大文件。 |
| `ATTACH-REG-001` | 附件错误与回归 | 验证附件缺失、上传失败、下载失败、重复发送不会破坏会话。 | macOS/Linux | Nightly | 待补 | 先做可控错误，不依赖真实网络抖动。 |
| `PROFILE-REG-001` | profile/settings 回归 | 验证设置页、profile、session 状态不被消息/账号改动破坏。 | macOS/Linux/mobile | PR optional/Nightly | unit/widget 已有基础 | 只补关键路径，不做全页面截图式脆弱测试。 |
| `MOBILE-E2E-001` | 两设备消息互通 | 验证设备 A 登录发送、设备 B 登录接收，再反向发送。 | iOS/Android | Nightly/Release | `mobile_e2e_runner.dart`、Maestro flows | 建立设备池、账号池、失败报告。 |
| `AGENT-SKIP-001` | Agent 作为 IM App 处理者 | Agent/Daemon 接收 App bootstrap，作为 IM App 的处理者消费普通消息并回传摘要。 | macOS/Linux | Skipped | 既有 `agent_im_delegated_message` 框架 | 本轮保留记录但不补齐、不运行、不作为回归 gate；后续单独方案处理。 |
| `E2EE-SKIP-001` | 端到端加密 E2E | Direct/group E2EE 明文、opaque 边界、密钥和协议验证。 | CLI/System/App 辅助 | Skipped | 既有系统测试方向 | 本轮不实现、不运行、不要求证据；后续单独方案处理。 |

## 9. 任务拆分

| Step | 标题 | 依赖 | 产出 | 小 Plan 文档 | Commit gate | 状态 |
|---|---|---|---|---|---|---|
| 01 | E2E 基线盘点与覆盖地图 | 无 | 当前测试入口、功能覆盖和缺口清单 | [steps/01-baseline-inventory.md](steps/01-baseline-inventory.md) | 必须 | done |
| 02 | 场景矩阵与标签/gate 契约 | Step 01 | `feature/regression/smoke/nightly/release` 标记和准入标准 | [steps/02-scenario-matrix-tags.md](steps/02-scenario-matrix-tags.md) | 必须 | pending |
| 03 | 测试环境、账号和数据隔离契约 | Step 01 | macOS/Linux/mobile/backend/env/account/report 契约 | [steps/03-environment-data-contract.md](steps/03-environment-data-contract.md) | 必须 | pending |
| 04 | Desktop 确定性 smoke 与回归基线 | Step 02, Step 03 | macOS/Linux no-backend smoke gate 和基础回归 | [steps/04-desktop-deterministic-smoke.md](steps/04-desktop-deterministic-smoke.md) | 必须 | pending |
| 05 | Desktop App + CLI peer 真实 E2E | Step 03, Step 04 | App/CLI 双向消息和账号闭环场景 | [steps/05-desktop-app-cli-peer-e2e.md](steps/05-desktop-app-cli-peer-e2e.md) | 必须 | pending |
| 06 | 群组与附件基础回归 E2E | Step 03, Step 05 | 群组消息、附件发送/接收、基础错误回归方案 | [steps/06-group-attachment-basic-regression.md](steps/06-group-attachment-basic-regression.md) | 必须 | pending |
| 07 | Mobile 双设备 E2E | Step 03 | iOS/Android 双设备消息互通和设备池策略 | [steps/07-mobile-two-device-e2e.md](steps/07-mobile-two-device-e2e.md) | 必须 | pending |
| 08 | CI/nightly/release gate 与维护机制 | Step 04-07 | 自动化 gate、报告、flake 处理、最终文档收口 | [steps/08-ci-nightly-release-maintenance.md](steps/08-ci-nightly-release-maintenance.md) | 必须 | pending |

## 10. 执行台账

状态取值：`pending`、`in_progress`、`review`、`blocked`、`committed`、`done`。

| Step | 状态 | 分支 | 开始时间 | 完成时间 | Commit | Review 证据 | 验证证据 | 下一步 |
|---|---|---|---|---|---|---|---|---|
| 01 | done | `feature/test-awiki-me` | 2026-06-14 12:52 CST | 2026-06-14 13:02 CST | 本步骤提交，短 hash 以 `git log -1` 为准 | Review 完成：覆盖地图基于 `docs/testing.md`、`tests/e2e_test/README.md`、`tests/integration_test/README.md`、root integration shims、desktop/mobile runners、unit/widget 测试和 source search；确认 Agent 和 E2EE 保留为 skipped，不进入本轮 gate。 | `find docs/e2e/awiki-me-e2e-regression-plan -type f -name '*.md' -print` 通过；`git diff --check -- docs/e2e/awiki-me-e2e-regression-plan` 通过；敏感信息/绝对路径扫描通过，无真实 secret。 | 启动 Step 02 |
| 02 | pending | 待执行时记录 | 待记录 | 待记录 | 待记录 | 待记录 | 待记录 | 等 Step 01 完成 |
| 03 | pending | 待执行时记录 | 待记录 | 待记录 | 待记录 | 待记录 | 待记录 | 等 Step 01 完成 |
| 04 | pending | 待执行时记录 | 待记录 | 待记录 | 待记录 | 待记录 | 待记录 | 等 Step 02/03 完成 |
| 05 | pending | 待执行时记录 | 待记录 | 待记录 | 待记录 | 待记录 | 待记录 | 等 Step 03/04 完成 |
| 06 | pending | 待执行时记录 | 待记录 | 待记录 | 待记录 | 待记录 | 待记录 | 等 Step 03/05 完成 |
| 07 | pending | 待执行时记录 | 待记录 | 待记录 | 待记录 | 待记录 | 待记录 | 等 Step 03 完成 |
| 08 | pending | 待执行时记录 | 待记录 | 待记录 | 待记录 | 待记录 | 待记录 | 等 Step 04-07 完成 |

## 11. Codex Goal 执行协议

- 将本 Plan 作为后续执行进度的唯一事实来源。
- 启动或恢复前，读取本 Plan、当前小 Plan、执行台账、Plan 变更记录和当前 `git status --short --branch`。
- 同一时间只执行一个步骤，除非本 Plan 明确标记步骤彼此独立且可并行。
- 恢复时，从第一个状态不是 `done` 的步骤继续。
- 每个步骤依次执行：标记 `in_progress`、实现、验证、Review、修复或记录 Review 发现、提交、记录证据、标记 `done`。
- 上一个依赖步骤的完成工作未提交前，不要开始下一个依赖步骤。
- 改变范围、顺序、验收标准、公开契约、数据模型或验证策略前，先更新本 Plan 的变更记录。
- 当前用户要求是先出方案；只有用户明确要求执行后，才修改测试实现、runner、CI 或跨仓代码。

## 11.1 Codex Goal 提示词

```text
请以 `test-awiki-me/docs/e2e/awiki-me-e2e-regression-plan/plan.md` 为唯一规划入口，执行 AWiki Me E2E 自动化与回归测试体系完善任务。

开始前先读取：
- `test-awiki-me/docs/e2e/awiki-me-e2e-regression-plan/plan.md`
- 当前第一个未 done 的 Step 文档
- 主 Plan 的执行台账、Codex Goal 执行协议、验证策略、Blocked 处理和 Plan 变更记录
- 当前 `git status --short --branch`

请从第一个状态不是 `done` 的步骤开始，一次只执行一个步骤。每步都要按对应小 Plan 实现、验证、Review、修复或记录 Review 发现，然后创建一个聚焦 commit，并回填主 Plan 执行台账和 Step 执行状态。需要改变范围、顺序、验收标准、公开契约、数据模型或验证策略时，先更新 Plan 变更记录。

所有步骤完成后，执行最终全局 Review 和整体验证，记录实际命令、通过/失败/跳过数量、失败或跳过原因、剩余风险和最终工作区状态。

核心注意点：PR gate 只放确定性测试和 dry-run；真实后端 + OTP + App/CLI peer E2E 放 manual/nightly/release；macOS/Linux 共享 scenario，仅 platform adapter 分叉；Linux headless 使用 `xvfb-run`；不提交 `.env`、OTP、JWT、私钥、CLI workspace、`.e2e/` 报告或本地设备状态；App/CLI 不绕过 SDK/CLI 高层能力直接拼 message-service payload。
```

## 12. 验证策略

| 层级 | 命令 / 检查 | 预期证据 |
|---|---|---|
| Docs | `cd test-awiki-me && find docs/e2e/awiki-me-e2e-regression-plan -type f -name '*.md' -print` | 文档存在，路径相对 workspace，未包含本机绝对路径或敏感值。 |
| Analyze | `cd test-awiki-me && dart analyze` | 无新增 analyzer error。 |
| Unit | `cd test-awiki-me && flutter test tests/unit_test` | 单元、widget、provider、harness parser 回归通过。 |
| Desktop dry-run | `cd test-awiki-me && dart run tests/e2e_test/harness/desktop_e2e_runner.dart --platform=linux --dry-run --skip-cli-build --skip-flutter-smoke` | 不依赖真实后端，输出计划和脱敏 report。 |
| Mobile dry-run | `cd test-awiki-me && dart run tests/e2e_test/harness/mobile_e2e_runner.dart --config tests/e2e_test/configs/mobile.example.yaml --dry-run` | iOS/Android 设备计划可生成，不写真实状态。 |
| macOS smoke | `cd test-awiki-me && flutter test integration_test/app_smoke_test.dart -d macos`；`flutter test integration_test/im_core_open_smoke_test.dart -d macos` | macOS runner 和 native SDK smoke 通过。 |
| Linux smoke | `cd test-awiki-me && AWIKI_SQLITE3_SOURCE_DIR=/tmp/awiki-sqlite3 xvfb-run -a flutter test integration_test/app_smoke_test.dart -d linux`；`AWIKI_SQLITE3_SOURCE_DIR=/tmp/awiki-sqlite3 xvfb-run -a flutter test integration_test/im_core_open_smoke_test.dart -d linux` | Linux headless App/native smoke 通过。 |
| Desktop real E2E | `cd test-awiki-me && dart run tool/desktop_cli_peer_e2e_runner.dart --platform linux --service-base-url "$AWIKI_SERVICE_BASE_URL" --did-domain "$AWIKI_DID_DOMAIN"` | App/CLI 双向消息和账号准备通过；跳过必须说明缺少的 env、服务或账号条件。 |
| Group / Attachment real E2E | 后续实现后运行 `group-message` 和 `attachment-message` scenarios | 群组和附件基础场景通过；未实现或环境缺失时记录 skipped/blocker。 |
| Skipped scenarios | 检查场景矩阵和执行报告 | `AGENT-SKIP-001`、`E2EE-SKIP-001` 明确标记 skipped，不进入实现和 gate。 |
| Mobile real E2E | `cd test-awiki-me && dart run tests/e2e_test/harness/mobile_e2e_runner.dart --config tests/e2e_test/configs/mobile.local.yaml` | 两设备登录、发送、接收通过；失败有设备和 report 证据。 |
| Cross-repo system | `cd awiki-system-test && make local-test-message-v2` 或对应 focused suite | 当协议、群组、附件、message-service 行为受影响时，提供服务侧系统测试证据。 |

如果某个命令不能运行，后续执行者必须记录原因、影响和替代证据，不得省略。

## 13. Review 策略

- 每步骤 Review：实现完成后、commit 前进行，重点检查正确性、回归风险、公开契约、测试确定性、日志脱敏、安全/隐私、跨平台兼容、文档漂移。
- 全局 Review：所有步骤完成后执行，覆盖全部 changed files、测试证据、执行台账、scenario matrix、gate 配置、敏感信息扫描和最终工作区状态。
- 契约 Review：检查 App/CLI 是否仍通过 `awiki-cli-rs2` SDK/CLI 高层能力，不直接拼 message-service RPC、WebSocket frame、SQLite 或群组/附件内部存储对象。
- 安全 Review：检查 OTP、JWT、私钥、DID secret、CLI workspace、App local state、remote logs、`.e2e/` report 是否被提交或输出。
- Flake Review：任何真实 E2E 失败都要区分产品 bug、环境问题、账号问题、设备问题和测试不稳定问题，不能简单扩大 timeout 掩盖问题。

## 14. 文档更新

- 主文档：`test-awiki-me/docs/e2e/awiki-me-e2e-regression-plan/plan.md`。
- 小 Plan：`test-awiki-me/docs/e2e/awiki-me-e2e-regression-plan/steps/*.md`。
- 后续实现若改变测试入口或 gate，应同步更新 `test-awiki-me/docs/testing.md` 和 `test-awiki-me/tests/e2e_test/README.md`。
- 只有跨仓架构、规则或系统测试入口变化时，才更新 `awiki-harness/`。

## 15. Commit 计划

- 每个完成、验证、Review 通过的步骤创建一个聚焦 commit。
- Commit 前记录 `git status --short --branch` 和纳入文件。
- Commit 后记录 commit hash 和工作区状态。
- 跨仓变更按仓库独立 commit；如果必须同步才能编译或运行，在执行台账中记录兼容原因和顺序。
- 不把所有步骤积累到一个最终大 commit。

## 16. Blocked 处理

| Blocker | Step | 证据 | 已尝试方案 | 影响范围 | 下一步决策 |
|---|---|---|---|---|---|
| 缺少可用非生产账号池或 OTP env | 03/05/07 | runner 报错、账号准备失败 | 使用 dry-run、复用已有 CLI workspace、请求账号池 | 真实 E2E | 不把真实 E2E 放入 required gate，等待账号条件 |
| Linux runner/native SDK 环境缺失 | 04/05 | `flutter devices`、native smoke 失败 | 安装 Linux desktop deps、预置 SQLite source、构建 native SDK | Linux gate | macOS 继续，Linux 标 optional 或 blocked |
| message-service v2 不可达或误连 legacy `molt-message` | 05/06 | `/im/rpc` 不存在、端口/日志证据 | 分离 `AWIKI_USER_SERVICE_URL` 和 `AWIKI_MESSAGE_SERVICE_URL` | 真实 E2E | 修正服务配置后重跑 |
| App selectors 不稳定 | 04/05/07 | integration/maestro 定位失败 | 补稳定 semantics 或改用 App service boundary | 当前场景 | 先保持 service-level smoke，再逐步提升 UI 断言 |
| 移动设备池不可用 | 07 | simulator/emulator/maestro 失败 | dry-run、手动 release run、self-hosted runner | Mobile E2E | 不阻塞 desktop gate |

只有依赖允许且风险已记录时，才继续另一个 pending 步骤。没有安全假设、回退方案或独立下一步时，再询问用户。

## 17. Plan 变更记录

| 日期 | 变更 | 原因 | 影响步骤 | 是否需要 Review |
|---|---|---|---|---|
| 2026-06-14 | 创建 AWiki Me E2E 自动化与回归测试体系完善方案 | 用户要求先出方案文档，暂不实现 | 全部 | 是 |

## 18. 风险与回滚

| 风险 | 缓解措施 | 回滚 / 回退方案 |
|---|---|---|
| E2E 过多进入 PR gate，导致开发节奏被环境波动拖慢 | 严格 gate 分层，PR 只跑确定性测试和 dry-run | 将真实 E2E 移回 nightly/manual，保留 smoke gate |
| 测试数据污染开发者账号或 CLI workspace | 所有真实 run 使用 `.e2e/<runId>`、独立 HOME、独立 App state | 删除对应 runId state，重建账号或 workspace |
| 报告泄漏 OTP/JWT/private key | redaction scan、Review gate、只提交 example config | 删除泄漏 artifact，轮换测试凭证，修复 redactor 后重跑 |
| UI E2E 脆弱导致误报 | 先用 service boundary 验证闭环，UI 只覆盖关键可见路径 | 回退不稳定 UI assertion，保留 App service smoke |
| App/CLI 绕过 SDK 边界导致假通过 | Review 强制检查依赖方向和测试调用边界 | 回滚绕过实现，改回 SDK/CLI 高层接口 |
| 真实后端状态和本地分支不一致 | 记录服务 URL、版本、runId、remote evidence | 改用本地 system-test 环境或等待部署一致 |

## 19. 最终全局 Review 与整体验证

- 触发条件：Step 01-08 全部完成、Review、验证并提交后执行。
- Review 范围：`test-awiki-me` 测试框架、integration shims、E2E harness、desktop/mobile configs、CI/nightly/release gate、`awiki-cli-rs2` 相关 SDK/CLI/Daemon 改动、服务侧/system-test 证据、全部文档和执行台账。
- 重点关注：跨步骤一致性、回归风险、兼容性、安全/隐私、群组/附件场景边界、文档漂移、未提交变更、每个步骤 Review 发现是否已解决或记录。
- 整体验证命令/检查：按第 12 节执行；无法运行项必须记录原因、影响和替代证据。
- Review 发现：待执行后记录。
- 已修复问题：待执行后记录。
- 剩余风险：待执行后记录。
- 最终证据：待执行后记录。
- 最终 `git status`：待执行后记录。
- 如果本阶段修改文件：记录 Review、验证和最终集成 commit。
