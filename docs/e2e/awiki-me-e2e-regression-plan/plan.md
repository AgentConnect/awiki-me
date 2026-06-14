# Plan：AWiki Me E2E 自动化与回归测试体系完善方案

状态：in_progress  
DOC：`test-awiki-me/docs/e2e/awiki-me-e2e-regression-plan/`  
Harness：`awiki-harness/`  
创建时间：2026-06-14  
恢复指针：Step 08 已完成；下一次执行最终全局 Review 与整体验证，记录第 19 节最终证据。

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

### 7.1 标签契约

| 标签 | 含义 | 允许的依赖 | 使用规则 |
|---|---|---|---|
| `smoke` | 验证 App、runner、SDK 或 harness 的最小启动面。 | 本地 Flutter/Dart/native SDK；不能依赖真实 OTP 或远端账号。 | 可以进入 PR optional 或 self-hosted gate；失败通常阻断后续 E2E。 |
| `feature` | 新功能对应的首版真实或半真实场景。 | 允许依赖 feature branch、manual config 或临时账号池。 | 初始不进入 required gate；稳定后按晋级规则提升为 `regression`。 |
| `regression` | 已稳定的核心能力回归保护。 | 依 gate 而定；PR required 只能无后端，nightly/release 可依真实后端。 | 新功能完成后至少选择一个核心路径升级为 regression。 |
| `pr-required` | 每个 PR 必跑的确定性测试。 | 无真实后端、无 OTP、无设备池、无远端 SSH。 | 只能包含 unit/widget、runner parser、dry-run 和可重复的本地检查。 |
| `pr-optional` | PR 可选或 self-hosted runner 上跑的确定性桌面 smoke。 | 允许 Linux/macOS desktop runner、native SDK、`xvfb-run`。 | 不能因为远端服务或账号不可用而失败。 |
| `nightly` | 每夜或定时运行的真实集成闭环。 | 可依非生产后端、账号池、OTP、App/CLI peer、移动设备池。 | 失败必须产出脱敏 report 和环境证据。 |
| `release` | 发布前必须通过或显式豁免的核心 E2E。 | 可依真实非生产环境和 release 设备池。 | 只放 P0/P1 用户路径；跳过或失败必须记录豁免原因。 |
| `manual` | 需要人工准备环境、账号或设备的运行。 | 可依本地服务、临时账号、人工设备。 | 不作为自动 gate 成功条件，但结果可作为排障或发布辅助证据。 |
| `skipped` | 本轮保留记录但明确不实现、不运行。 | 不要求环境、不要求验证证据。 | 只能用于显式延期场景；不能进入 PR、nightly 或 release gate。 |

### 7.2 Gate 契约

| Gate | 运行条件 | 可包含标签 | 不允许包含 | 通过证据 |
|---|---|---|---|---|
| PR required | 普通开发 PR，默认 CI。 | `pr-required`、部分 `smoke`、dry-run。 | 真实后端、OTP、远端账号、移动设备池、真实 App/CLI peer E2E。 | `dart analyze`、unit/widget、harness dry-run、docs/secret scan 通过。 |
| PR optional desktop | 有 Linux/macOS desktop runner 的 PR job 或本地开发机。 | `pr-optional`、`smoke`。 | 账号注册/恢复、真实消息发送、真实群组/附件、移动设备。 | Flutter desktop smoke、native SDK open smoke 通过；Linux 使用 `xvfb-run`。 |
| Nightly desktop | 定时任务或手动触发，具备非生产后端和测试账号池。 | `nightly`、稳定后的 `feature`、`regression`。 | `skipped`、未脱敏报告、绕过 SDK/CLI 的测试数据。 | App/CLI 双向 direct message、history/inbox、群组/附件基础路径和脱敏 report。 |
| Nightly mobile | 具备 iOS/Android 设备池、Maestro 和测试账号池。 | `nightly`、mobile `regression`。 | 桌面专属 runner、无设备证据的伪通过。 | 两设备互通 flow、设备日志、脱敏 report。 |
| Release | 发布候选版本冻结后。 | P0/P1 `regression`、必要 `smoke`。 | 未稳定 `feature`、`manual`、`skipped`。 | release 环境 report、失败/跳过豁免、最终 Review 记录。 |
| Manual | 开发者或 QA 手动触发。 | `manual`、`feature`、排障用 `nightly`。 | 被声称为自动 gate 的结果。 | 命令、环境、账号池来源、脱敏日志和人工结论。 |

### 7.3 Case 字段契约

每个 E2E case 在实现或维护时必须能追踪以下字段：

| 字段 | 要求 |
|---|---|
| Case ID | 全局唯一，使用领域前缀，例如 `APP-*`、`AUTH-*`、`MSG-*`、`GROUP-*`、`ATTACH-*`、`MOBILE-*`、`*-SKIP-*`。 |
| Owner domain | 归属能力域，例如 App shell、Auth、Direct Message、Group、Attachment、Profile/Settings、Mobile、Deferred。 |
| Platform | 标明 `macOS`、`Linux`、`iOS`、`Android` 或组合；macOS/Linux 桌面默认共享 scenario。 |
| Peer topology | 标明 no-peer、App + CLI peer、App + mobile peer、two mobile devices、system-only 或 deferred。 |
| Backend dependency | 标明 no-backend、dry-run、real non-production backend、local system-test backend。 |
| Data / secret requirement | 只允许记录 env 名、账号池角色和 fixture 名；禁止记录 OTP 值、JWT、私钥或真实 local config。 |
| Gate | 标明 PR required、PR optional desktop、nightly desktop、nightly mobile、release、manual 或 skipped。 |
| Pass evidence | 标明测试命令、runId、history/inbox evidence、UI/service assertion、report 和 redaction scan。 |
| Skip / blocker rule | 标明缺少 CLI/SDK 高层能力、账号池、设备池、Linux runner 或后端时的处理方式。 |

### 7.4 晋级、降级和隔离规则

- `feature` case 连续在目标 nightly 环境中稳定通过至少三次，并且 Review 确认可维护、可脱敏、失败可诊断后，才能升级为 `regression`。
- `regression` case 如果连续失败且证据指向测试不稳定或环境不确定，应先降级为 quarantine/manual，并在 Plan 变更记录中说明原因；不能通过扩大 timeout 掩盖问题。
- `pr-required` 只能接收确定性、无真实后端、无真实账号、无设备池的检查；任何需要 OTP、远端服务、真实 App/CLI 互通的 case 必须留在 nightly/manual/release。
- `skipped` case 只能在用户显式扩大本轮范围后才允许转为 `feature`；本轮 `AGENT-SKIP-001` 和 `E2EE-SKIP-001` 保持 skipped。
- 如果 CLI/SDK 暂缺群组或附件高层命令，对应 case 标记为 blocker 或补最小高层能力；不得直接操作 SQLite、WebSocket frame、message-service wire payload 或内部存储对象伪造通过。

## 8. 场景矩阵

| Case ID | Owner domain | 场景 | Tags | 平台 | Peer topology | Backend / data 依赖 | Gate | 当前基础 | 验收证据 / blocker 规则 |
|---|---|---|---|---|---|---|---|---|---|
| `APP-SMOKE-001` | App shell | App shell 启动 | `smoke`, `pr-optional`, `regression` | macOS/Linux | no-peer | no-backend；fake bootstrap | PR optional desktop | `app_smoke_test.dart` | Shell/onboarding/authenticated shell 可启动；Linux 用 `xvfb-run`；不得接真实后端。 |
| `SDK-SMOKE-001` | Native SDK | Native SDK open | `smoke`, `pr-optional`, `regression` | macOS/Linux | no-peer | no-backend；临时目录；Linux 需 `AWIKI_SQLITE3_SOURCE_DIR` | PR optional desktop | `im_core_open_smoke_test.dart` | `AwikiImCore.open` 成功并清理临时状态；native library 失败时阻断 L3+。 |
| `AUTH-E2E-001` | Auth | App 注册/恢复测试账号 | `feature`, `nightly`, `manual` | macOS/Linux | App + CLI peer 前置 | real non-production backend；OTP env 名；账号池角色 | Nightly desktop / Manual | `desktop_cli_peer_smoke_test.dart` 内已有准备逻辑 | App session、DID/Handle、CLI peer 身份准备成功；缺账号池或 OTP 时记录 skipped/blocker。 |
| `MSG-E2E-001` | Direct Message | App -> CLI direct message | `regression`, `nightly`, `release` | macOS/Linux | App + CLI peer | real non-production backend；runId | Nightly desktop / Release | `desktop_cli_peer_smoke_test.dart` | App 正常发送，CLI `history/inbox` 能按 runId 查到；报告脱敏。 |
| `MSG-E2E-002` | Direct Message | CLI -> App direct message | `regression`, `nightly`, `release` | macOS/Linux | App + CLI peer | real non-production backend；runId | Nightly desktop / Release | `desktop_cli_peer_smoke_test.dart` | CLI 正常发送，App 通过 service/UI boundary 读取到；不得直接查 SQLite。 |
| `MSG-REG-001` | Conversation | 会话 history / inbox / 去重 / 刷新 | `feature`, `regression`, `nightly` | macOS/Linux | App + CLI peer | real non-production backend；多条 runId 消息 | Nightly desktop | 待补 | history、inbox、refresh 后无重复，既有会话不被新消息破坏；UI 不稳定时先用 App service boundary。 |
| `GROUP-E2E-001` | Group | 创建群组并添加成员 | `feature`, `nightly`, `release` | macOS/Linux | App + CLI peer 或第二账号 | real non-production backend；两人群账号池 | Nightly desktop / Release | 待补 | App 创建最小两人群，成员和群资料可见；CLI/SDK 无高层群组能力时记录 blocker。 |
| `GROUP-E2E-002` | Group | 群组消息互通 | `feature`, `nightly`, `release` | macOS/Linux | App + CLI peer 或第二账号 | real non-production backend；群 runId | Nightly desktop / Release | 待补 | App 和 peer 在同一群 history 中互见文本消息；不得绕过群组服务契约。 |
| `GROUP-REG-001` | Group | 群组基础回归 | `feature`, `regression`, `nightly` | macOS/Linux/mobile | App + peer | real non-production backend；最小群资料 | Nightly desktop/mobile | unit/widget 有部分基础 | 群名/基础资料/成员列表不被消息流破坏；首版不覆盖复杂群管理。 |
| `ATTACH-E2E-001` | Attachment | App -> peer 小附件发送 | `feature`, `nightly`, `release` | macOS/Linux | App + CLI peer | real non-production backend；小型 fixture；hash/metadata | Nightly desktop / Release | 待补 | peer 可见附件 metadata，文件名、大小、hash 或内容摘要匹配；CLI/SDK 无附件命令时记录 blocker。 |
| `ATTACH-E2E-002` | Attachment | peer -> App 小附件接收 | `feature`, `nightly`, `release` | macOS/Linux | App + CLI peer | real non-production backend；小型 fixture；download 状态 | Nightly desktop / Release | 待补 | App 可见附件并完成基础下载/状态断言；首版不做大文件、批量或断点续传。 |
| `ATTACH-REG-001` | Attachment | 附件错误与回归 | `feature`, `regression`, `nightly` | macOS/Linux | App + CLI peer | 可控失败 fixture；real backend 或 local system-test backend | Nightly desktop | 待补 | 附件缺失/失败不破坏会话，重复发送不产生错误状态；不依赖真实网络抖动。 |
| `PROFILE-REG-001` | Profile/Settings | profile/settings 回归 | `smoke`, `regression`, `pr-optional`, `nightly` | macOS/Linux/mobile | no-peer 或 authenticated App | no-backend fake session；nightly 可复用真实 session | PR optional desktop / Nightly | unit/widget 已有基础 | 设置页、profile、session 状态在消息/账号流后仍可访问；避免截图式脆弱断言。 |
| `MOBILE-E2E-001` | Mobile | 两设备 direct message 互通 | `feature`, `regression`, `nightly`, `release` | iOS/Android | two mobile devices | real non-production backend；设备池；账号池 | Nightly mobile / Release | `mobile_e2e_runner.dart`、Maestro flows | 设备 A/B 双向发送接收通过；缺设备池时只允许 dry-run 或 manual skipped。 |
| `AGENT-SKIP-001` | Deferred | Agent 作为 IM App 处理者 | `skipped` | macOS/Linux | Agent/Daemon + App | 本轮不要求 | Skipped | 既有 `agent_im_delegated_message` 框架 | 保留记录但不实现、不运行、不加入任何 gate、不要求验证证据。 |
| `E2EE-SKIP-001` | Deferred | 端到端加密 E2E | `skipped` | CLI/System/App 辅助 | deferred | 本轮不要求 | Skipped | 既有系统测试方向 | 保留记录但不实现、不运行、不加入任何 gate、不要求验证证据。 |

### 8.1 Step 03 环境、账号和数据契约

| 领域 | 契约 | 当前入口 |
|---|---|---|
| Shared service env | 真实 E2E 通过 env 或 ignored local config 注入 `AWIKI_SERVICE_BASE_URL` / `AWIKI_BASE_URL`、`AWIKI_USER_SERVICE_URL`、`AWIKI_MESSAGE_SERVICE_URL`、`AWIKI_MESSAGE_SERVICE_WS_URL`、`AWIKI_DID_DOMAIN`、`AWIKI_ANP_SERVICE_URL`、`AWIKI_ANP_SERVICE_DID`；只记录 env 名，不记录值。 | `tool/desktop_cli_peer_e2e_runner.dart`、`tests/e2e_test/configs/mobile.example.yaml`、`tests/e2e_test/configs/agent_im_delegated.example.yaml` |
| Desktop runner env | 通用 desktop harness 使用 `AWIKI_DESKTOP_E2E_*`，并允许 `AWIKI_MACOS_E2E_*` / `AWIKI_LINUX_E2E_*` 覆盖 `FLUTTER`、`CLI_REPO`、`BASE_URL`、`DID_DOMAIN`。 | `tests/e2e_test/harness/desktop_e2e_runner.dart` |
| Desktop App + CLI peer env | 真实 App/CLI peer 使用 `DEV_OTP_PHONE`、`DEV_OTP_CODE`、`AWIKI_E2E_APP_HANDLE`、`AWIKI_E2E_CLI_HANDLE`、`AWIKI_CLI_BIN` 和 service env；App handle 与 CLI handle 必须不同。 | `tool/desktop_cli_peer_e2e_runner.dart` |
| Mobile local config | 移动真实 E2E 使用 ignored `tests/e2e_test/configs/mobile.local.yaml`，包含 platform、service URLs、两个设备、两个账号、OTP timeout 和 message timeout。 | `tests/e2e_test/configs/mobile.example.yaml` |
| Linux headless | Linux desktop smoke 和真实 desktop E2E 必须使用 `xvfb-run`；runner 还要求 `clang`、`cmake`、`ninja`、`pkg-config` 等工具可用；`AWIKI_SQLITE3_SOURCE_DIR` 可作为 native SDK 构建稳定性前提。 | `tests/e2e_test/harness/desktop_e2e_runner.dart`、`docs/testing.md` |
| macOS desktop | macOS 需要 Xcode command line tools 和 `flutter test -d macos`；与 Linux 共享 scenario，只在 platform adapter 和命令包装层分叉。 | `tests/e2e_test/harness/desktop_e2e_runner.dart` |
| 数据隔离 | 每次真实 run 必须使用 runId 隔离报告、CLI workspace、CLI HOME、App state 和移动设备状态；`.e2e/`、`*.local.yaml`、`*.local.env` 已在 `.gitignore` 中排除。 | `.gitignore`、`tool/desktop_cli_peer_e2e_runner.dart`、`tests/e2e_test/harness/mobile_e2e_runner.dart` |
| Secret handling | 报告允许记录 runId、脱敏路径、env 名、service host 和 handle；禁止提交 OTP 值、JWT、private key、CLI workspace、App local state、真实 local config 或 `.e2e/` report。 | `.gitignore`、`DesktopSecretRedactor`、`SecretRedactor` |

### 8.2 账号池和状态隔离规则

- Desktop App + CLI peer 至少需要两个不同 handle：App 账号和 CLI peer 账号；手机号/OTP 来源只能通过本地 env 注入，不能写入文档、config 或 report。
- Mobile E2E 至少需要两个不同账号：device A 和 device B；`mobile.example.yaml` 只保留占位示例，真实 phone/handle 写入 ignored `mobile.local.yaml` 或 CI secret 注入。
- 账号准备优先复用稳定非生产账号；只有账号缺失、handle 不存在或明确需要重置时才执行 register，避免耗尽 OTP 或污染共享账号。
- 所有消息文本、群组名和附件 fixture 名必须包含 runId 或可追踪前缀，便于 history/inbox 去重和报告定位。
- 真实 run 的本地状态必须按场景隔离：desktop App + CLI peer 使用 `.e2e/desktop-cli-peer/<runId>/reports`、`cli-peer`、`cli-home`、`app`；desktop harness 使用 `.e2e/<platform>/reports/<runId>` 和 `.e2e/<platform>/cli-workspaces/<runId>`；mobile 使用 `.e2e/reports/<runId>` 并根据配置重置设备 App data。
- User Service 和 Message Service URL 必须可分离配置；当两者使用同一域名时，也要在 report 中记录逻辑字段，避免误连 legacy message 服务时无法定位。
- 如果缺少账号池、OTP env、Linux runner、移动设备池或服务 URL，只能 dry-run、manual skipped 或记录 blocker；不能提交真实 secret，也不能用静态测试数据伪造 real E2E pass。

### 8.3 Step 04 Desktop deterministic smoke 基线

| Smoke | 覆盖 | 后端依赖 | Linux 证据 | macOS 证据 |
|---|---|---|---|---|
| `APP-SMOKE-001` | fake bootstrap、onboarding shell、authenticated shell、profile/settings 基础页面。 | 无真实后端、无 OTP。 | `xvfb-run -a flutter test integration_test/app_smoke_test.dart -d linux` 通过。 | 当前 host 非 macOS，保留 runner 命令由 macOS runner 验证。 |
| `SDK-SMOKE-001` | `AwikiImCore.open` native backend、isolated SDK paths、native library 加载。 | 无真实后端、无 OTP。 | `xvfb-run -a flutter test integration_test/im_core_open_smoke_test.dart -d linux` 通过。 | 当前 host 非 macOS，保留 runner 命令由 macOS runner 验证。 |

Step 04 只扩展 deterministic App smoke，不引入真实账号、真实消息、CLI peer 或 mobile 设备；root `integration_test/` 继续只作为 Flutter tooling shim，真实实现仍在 `tests/integration_test/`。

### 8.4 Step 07 Mobile 双设备 E2E dry-run 与报告基线

| 能力 | 覆盖 | 后端 / 设备依赖 | 当前证据 | 真实运行条件 |
|---|---|---|---|---|
| `MOBILE-E2E-001` dry-run | `mobile-two-device` 场景、iOS/Android 平台计划、账号 handle、设备配置摘要、A_TO_B / B_TO_A 消息计划、report redaction。 | 无真实后端、无真实设备；dry-run caseStatus 为 `skipped`。 | `dart run tests/e2e_test/harness/mobile_e2e_runner.dart --config tests/e2e_test/configs/mobile.example.yaml --dry-run` 通过，`timings.json` 记录 `scenario`、`caseIds`、`runId`、`platform`、`dryRun`、`skippedReason`、脱敏路径和计划消息。 | `tests/e2e_test/configs/mobile.local.yaml`、两台 iOS simulator 或 Android emulator/device、Maestro、非生产账号池和可达后端。 |
| Mobile command/report redaction | dry-run 命令日志、report service URL、device ID、路径和账号摘要。 | 不需要真实设备；使用 runner 单测验证。 | `flutter test tests/unit_test/e2e_harness/mobile_e2e_runner_test.dart` 覆盖手机号、OTP、token/JWT query、device id 不进入 report/log。 | real run 仍需对实际 Maestro logs、screenshots 和 `.e2e/reports/<runId>/` 做发布前敏感扫描。 |

Step 07 不把 dry-run success 解释为真实两设备通过；在真实 iOS/Android 设备池、Maestro、非生产账号和后端可用前，`MOBILE-E2E-001` 真实 case 仍只进入 nightly/release/manual，不进入 PR required。

## 9. 任务拆分

| Step | 标题 | 依赖 | 产出 | 小 Plan 文档 | Commit gate | 状态 |
|---|---|---|---|---|---|---|
| 01 | E2E 基线盘点与覆盖地图 | 无 | 当前测试入口、功能覆盖和缺口清单 | [steps/01-baseline-inventory.md](steps/01-baseline-inventory.md) | 必须 | done |
| 02 | 场景矩阵与标签/gate 契约 | Step 01 | `feature/regression/smoke/nightly/release` 标记和准入标准 | [steps/02-scenario-matrix-tags.md](steps/02-scenario-matrix-tags.md) | 必须 | done |
| 03 | 测试环境、账号和数据隔离契约 | Step 01 | macOS/Linux/mobile/backend/env/account/report 契约 | [steps/03-environment-data-contract.md](steps/03-environment-data-contract.md) | 必须 | done |
| 04 | Desktop 确定性 smoke 与回归基线 | Step 02, Step 03 | macOS/Linux no-backend smoke gate 和基础回归 | [steps/04-desktop-deterministic-smoke.md](steps/04-desktop-deterministic-smoke.md) | 必须 | done |
| 05 | Desktop App + CLI peer 真实 E2E | Step 03, Step 04 | App/CLI 双向消息和账号闭环场景 | [steps/05-desktop-app-cli-peer-e2e.md](steps/05-desktop-app-cli-peer-e2e.md) | 必须 | done |
| 06 | 群组与附件基础回归 E2E | Step 03, Step 05 | 群组消息、附件发送/接收、基础错误回归方案 | [steps/06-group-attachment-basic-regression.md](steps/06-group-attachment-basic-regression.md) | 必须 | done |
| 07 | Mobile 双设备 E2E | Step 03 | iOS/Android 双设备消息互通和设备池策略 | [steps/07-mobile-two-device-e2e.md](steps/07-mobile-two-device-e2e.md) | 必须 | done |
| 08 | CI/nightly/release gate 与维护机制 | Step 04-07 | 自动化 gate、报告、flake 处理、最终文档收口 | [steps/08-ci-nightly-release-maintenance.md](steps/08-ci-nightly-release-maintenance.md) | 必须 | done |

## 10. 执行台账

状态取值：`pending`、`in_progress`、`review`、`blocked`、`committed`、`done`。

| Step | 状态 | 分支 | 开始时间 | 完成时间 | Commit | Review 证据 | 验证证据 | 下一步 |
|---|---|---|---|---|---|---|---|---|
| 01 | done | `feature/test-awiki-me` | 2026-06-14 12:52 CST | 2026-06-14 13:02 CST | 本步骤提交，短 hash 以 `git log -1` 为准 | Review 完成：覆盖地图基于 `docs/testing.md`、`tests/e2e_test/README.md`、`tests/integration_test/README.md`、root integration shims、desktop/mobile runners、unit/widget 测试和 source search；确认 Agent 和 E2EE 保留为 skipped，不进入本轮 gate。 | `find docs/e2e/awiki-me-e2e-regression-plan -type f -name '*.md' -print` 通过；`git diff --check -- docs/e2e/awiki-me-e2e-regression-plan` 通过；敏感信息/绝对路径扫描通过，无真实 secret。 | 启动 Step 02 |
| 02 | done | `feature/test-awiki-me` | 2026-06-14 12:58 CST | 2026-06-14 13:02 CST | `cacfde6` | Review 完成：确认标签、gate、case 字段、晋级/降级规则覆盖新功能验证和既有功能回归；真实后端/OTP/App+CLI 互通未进入 PR required；Agent 和 E2EE 保持 skipped，不实现、不运行、不进任何 gate。 | `awk ... uniq -d` 检查矩阵 Case ID 无重复；`find docs/e2e/awiki-me-e2e-regression-plan -type f -name '*.md' -print | sort` 通过；`git diff --check -- docs/e2e/awiki-me-e2e-regression-plan` 通过；敏感信息/绝对路径扫描仅命中 Step 05 的 env 变量名示例，无真实 secret。 | 启动 Step 03 |
| 03 | done | `feature/test-awiki-me` | 2026-06-14 13:06 CST | 2026-06-14 13:09 CST | `a2defaa` | Review 完成：确认 shared service env、desktop/macOS/Linux 前提、mobile local config、账号池、runId 隔离和 secret/report 规则与现有 runner 一致；真实账号、OTP 和 local config 均不提交。 | `dart run tests/e2e_test/harness/mobile_e2e_runner.dart --config tests/e2e_test/configs/mobile.example.yaml --dry-run` 通过；`dart run tests/e2e_test/harness/desktop_e2e_runner.dart --platform=linux --dry-run --skip-cli-build --skip-flutter-smoke` 通过；`git diff --check -- docs/e2e/awiki-me-e2e-regression-plan` 通过；敏感信息/绝对路径扫描仅命中 Step 05 env 变量名示例，无真实 secret；`.e2e/` 为 ignored 运行产物。 | 启动 Step 04 |
| 04 | done | `feature/test-awiki-me` | 2026-06-14 13:24 CST | 2026-06-14 13:28 CST | 本步骤提交，短 hash 以 `git log -1` 为准 | Review 完成：新增 profile/settings smoke 只使用 fake bootstrap、fake profile provider 和 fake homepage loader；root `integration_test/` 仍为 shim；未接入真实账号、OTP、User Service、Message Service、CLI peer 或 mobile 设备。 | `dart analyze` 通过；`flutter test tests/unit_test/profile_page_test.dart tests/unit_test/settings_page_test.dart tests/unit_test/conversation_workspace_test.dart` 通过，41 tests；`xvfb-run -a flutter test integration_test/app_smoke_test.dart -d linux` 通过，3 tests；`xvfb-run -a flutter test integration_test/im_core_open_smoke_test.dart -d linux` 通过，1 test；当前 host 为 Linux，macOS smoke 未运行；`git diff --check` 通过；敏感扫描仅命中 env 变量名示例。 | 启动 Step 05 |
| 05 | done | `feature/test-awiki-me` | 2026-06-14 13:35 CST | 2026-06-14 13:47 CST | 本步骤提交后回填短 hash，以 `git log -1` 为准 | Review 完成：新增断言只通过 App `MessagingService` / `ConversationService` 和 CLI 高层命令，不直接访问 raw RPC、WebSocket、SQLite 或测试 fixture；real E2E 未在当前 host 运行。 | `dart analyze` 通过；`flutter test tests/unit_test/e2e_harness/desktop_cli_peer_e2e_runner_test.dart` 通过，11 tests；`xvfb-run -a flutter test integration_test/desktop_cli_peer_smoke_test.dart -d linux` 在 `AWIKI_E2E` 未开启时安全 skip；`git diff --check` 通过；敏感扫描无真实 secret。 | 启动 Step 06 |
| 06 | done | `feature/test-awiki-me` | 2026-06-14 13:51 CST | 2026-06-14 14:03 CST | 本步骤提交后回填短 hash，以 `git log -1` 为准 | Review 完成：App 使用 `GroupApplicationService` / `MessagingService`，CLI 使用 `group messages`、`msg send --group`、`msg send --file`、`msg attachment download` 高层命令；未直接访问 raw RPC、WebSocket、SQLite、附件内部存储或 `ModMessage` fixture。 | `dart analyze` 通过；`flutter test tests/unit_test/e2e_harness/desktop_cli_peer_e2e_runner_test.dart` 通过，11 tests；`xvfb-run -a flutter test integration_test/desktop_cli_peer_smoke_test.dart -d linux` 在 `AWIKI_E2E` 未开启时安全 skip；`git diff --check` 通过；敏感扫描无真实 secret；real group/attachment E2E 当前 host 未运行。 | 启动 Step 07 |
| 07 | done | `feature/test-awiki-me` | 2026-06-14 14:13 CST | 2026-06-14 14:18 CST | `83c1438` | Review 完成：mobile runner 真实 flow 仍走 Maestro/App UI，不绕过 App/SDK/服务；dry-run report 只作为计划证据，caseStatus 保持 `skipped`；命令日志和 report 对手机号、OTP、token/JWT query、device id、绝对路径做脱敏。 | `dart analyze` 通过；`flutter test tests/unit_test/e2e_harness/mobile_e2e_runner_test.dart` 通过，15 tests；`dart run tests/e2e_test/harness/mobile_e2e_runner.dart --config tests/e2e_test/configs/mobile.example.yaml --dry-run` 通过，runId `20260614061538-0ef4ka`，report 记录 `mobile-two-device` / `MOBILE-E2E-001` 且 caseStatus 为 `skipped`；`git diff --check` 通过；敏感扫描仅命中 env 名、示例占位手机号、测试用假 secret 和既有 redaction 测试数据，无真实 secret；真实 iOS/Android 两设备未运行，当前 Linux host 未配置设备池、Maestro real run 和 `mobile.local.yaml`。 | 启动 Step 08 |
| 08 | done | `feature/test-awiki-me` | 2026-06-14 14:22 CST | 2026-06-14 14:30 CST | `a9298f2` | Review 完成：CI required 只包含 deterministic analyze/unit/dry-run/Linux smoke，不加入真实 OTP、后端、SSH 或移动设备；nightly/release/manual runbook 明确 secret/local config 前提、report 字段和 skipped 规则；`AGENT-SKIP-001` 与 `E2EE-SKIP-001` 未加入任何 gate。 | `dart analyze` 通过；`flutter test tests/unit_test` 通过，431 tests；harness focused tests 通过，26 tests；mobile dry-run 通过，runId `20260614062415-8ycc6f`；desktop dry-run 通过，runId `20260614T062415431Z`；串行 Linux app smoke 通过，3 tests；串行 Linux native smoke 通过，1 test；`git diff --check` 通过；敏感扫描仅命中 env 名、测试假值和既有 redaction fixture，无真实 secret；真实 nightly/release E2E 当前 host 未运行。 | 执行最终全局 Review 与整体验证 |

## 11. Codex Goal 执行协议

- 将本 Plan 作为后续执行进度的唯一事实来源。
- 启动或恢复前，读取本 Plan、当前小 Plan、执行台账、Plan 变更记录和当前 `git status --short --branch`。
- 同一时间只执行一个步骤，除非本 Plan 明确标记步骤彼此独立且可并行。
- 恢复时，从第一个状态不是 `done` 的步骤继续。
- 每个步骤依次执行：标记 `in_progress`、实现、验证、Review、修复或记录 Review 发现、提交、记录证据、标记 `done`。
- 上一个依赖步骤的完成工作未提交前，不要开始下一个依赖步骤。
- 改变范围、顺序、验收标准、公开契约、数据模型或验证策略前，先更新本 Plan 的变更记录。
- 当前 Goal 已进入执行阶段；每个步骤只能修改其小 Plan 允许的文件和必要实现，超出范围前必须先更新 Plan 变更记录。

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
