# Plan：Desktop CLI Peer macOS / Linux E2E 执行方案

状态：draft  
DOC：`test-awiki-me/docs/e2e/linux-desktop-cli-peer-e2e/`  
Harness：`awiki-harness/`  
创建时间：2026-06-13  
恢复指针：执行开始前从 Step 01 开始；本轮只产出方案文档，不修改 App runner、SDK 或服务代码。
总方案摘要：[../desktop-cli-peer-macos-linux-plan.md](../desktop-cli-peer-macos-linux-plan.md)

## 1. 目标

- 任务目标：在 `feature/release-0526/agent-im-hutong` 已有单元测试、系统测试、端到端加密测试和 Desktop 测试框架基础上，补齐 Linux Desktop 运行能力，并落地一个 macOS / Linux 共用的最小 App + CLI peer E2E smoke。
- 预期行为：后续实现完成后，macOS 可以直接运行同一个 Desktop smoke；Ubuntu headless 可以通过 `xvfb-run` 启动 Flutter Linux Desktop integration test。两种平台都使用 Desktop App 作为客户端 A、现有 `awiki-cli-rs2` CLI 作为 peer 客户端 B，验证 App A 与 CLI B 双向消息互通。
- 非目标：本方案不在当前文档任务里创建 `test-awiki-me/linux/` runner，不修改 `awiki-cli-rs2/packages/awiki_im_core`，不启动真实服务，不写入或提交 `.env` 值、账号凭据、本地状态、`.e2e/` 报告。
- 完成标准：本文档给出 feasibility verdict、当前阻塞、跨仓实现步骤、账号与服务编排、macOS / Linux 测试命令、验收标准、风险和后续 Codex Goal 执行协议；每个实施步骤都有独立小 Plan。

## 2. 可行性结论

可以做，但不是只加 `xvfb-run` 就完成。macOS 路径复用已有 Desktop / native SDK 能力；Linux 路径需要补齐 runner、headless 显示和 native SDK 打包加载。

`xvfb-run -a flutter test integration_test -d linux` 只解决 headless Ubuntu 没有 X Server 的显示问题。完整 E2E 还需要同时满足：

- `test-awiki-me` 有 `linux/` Flutter Desktop runner；
- `awiki-cli-rs2/packages/awiki_im_core` 声明并打包 Linux native SDK，`AwikiImCore.open` 在 Linux 能加载 `libawiki_im_core.so`；
- `user-service/.env` 中的非生产测试 OTP 配置可以让 App 端和 CLI peer 端获得两个可发送 / 可接收消息的身份，或提供稳定账号池；
- App integration test 有足够稳定的 E2E selectors、测试配置注入和消息等待机制；
- CLI peer 使用独立 `AWIKI_CLI_WORKSPACE_HOME_DIR`，避免污染开发者默认 CLI workspace；
- 后端服务地址、DID domain、ANP endpoint、message-service 路由与 App / CLI 使用同一套非生产环境。

满足这些条件后，App + CLI peer 是可行的端到端拓扑。它可以验证真实 Flutter UI、真实 Dart SDK、Rust native SDK、身份注册 / 恢复、User Service、Message Service、CLI peer 和消息存取链路。它不等价于“两台真实桌面设备”的 UI E2E，但足够覆盖首个 Desktop macOS / Linux 端到端闭环。

## 3. 当前事实

| 事实 | 证据 | 影响 |
|---|---|---|
| `test-awiki-me` 当前没有 Linux runner | `test-awiki-me/linux/` 不存在 | `flutter test integration_test -d linux` 不能作为 gate；必须先加 runner |
| `integration_test/app_smoke_test.dart` 使用 fake bootstrap | `test-awiki-me/integration_test/app_smoke_test.dart` | 只能证明 Flutter shell / tab / onboarding smoke，不验证真实 native SDK、网络、secure storage 或服务 |
| `integration_test/im_core_open_smoke_test.dart` 当前 macOS-only skip | `test-awiki-me/integration_test/im_core_open_smoke_test.dart` | Linux native open smoke 要等 SDK Linux 支持 |
| `awiki_im_core` plugin 只声明 Android / iOS / macOS | `awiki-cli-rs2/packages/awiki_im_core/pubspec.yaml` | Flutter 不会把 Linux 作为该 FFI plugin 支持平台 |
| SDK native loader 没有 Linux 分支 | `awiki-cli-rs2/packages/awiki_im_core/lib/src/native_library_loader.dart` | Linux 会抛 `UnsupportedError` |
| Rust facade 可以产出 `cdylib` | `awiki-cli-rs2/crates/im-core-dart/Cargo.toml` | Linux `.so` 技术上可构建，需补打包和加载策略 |
| SDK native build script 只覆盖 Apple / Android | `awiki-cli-rs2/scripts/flutter/build-sdk-native.sh` | 需要新增 Linux build 分支或单独脚本 |
| App 已有服务地址 dart-define 配置 | `test-awiki-me/lib/src/application/config/awiki_environment_config.dart`、`test-awiki-me/lib/src/data/im_core/awiki_im_core_config.dart` | 可以复用 `AWIKI_BASE_URL` / `AWIKI_SERVICE_BASE_URL` / `AWIKI_*_URL` 等配置注入 |
| App 已有一批 E2E semantics | `test-awiki-me/lib/src/app/e2e_semantics.dart`、onboarding / chat / shell widgets | 后续可以扩展到 Linux integration test；现有 selector 可能还不够完整 |
| CLI 支持隔离 workspace | `awiki-cli-rs2/onboarding.md`、`AWIKI_CLI_WORKSPACE_HOME_DIR` | CLI peer 可在 `.e2e/` 下独立运行，不污染默认账号 |
| CLI 支持注册 / 恢复 / 发消息 / 查 inbox/history | `awiki-cli-rs2/docs/architecture/awiki-command-v2.md` | 可以作为对端客户端参与 E2E |
| `user-service/.env` 有测试 OTP key | `user-service/.env` 本地存在 `DEV_OTP_PHONE` / `DEV_OTP_CODE` 等 key | 可以作为非生产测试账号输入；文档和脚本不得记录实际值 |

## 4. 方案拓扑

```text
Desktop host
  |
  +-- macOS: flutter test -d macos
  +-- Linux headless: xvfb-run -a flutter test -d linux
  |     |
  |     +-- flutter test integration_test/desktop_cli_peer_smoke_test.dart
  |           |
  |           +-- Flutter Desktop App（客户端 A）
  |           |     |
  |           |     +-- test-awiki-me/macos 或 test-awiki-me/linux runner
  |           |     +-- awiki_im_core Dart package
  |           |     +-- awiki_im_core macOS native 或 Linux .so
  |           |     +-- User Service / Message Service / ANP endpoint
  |           |
  |           +-- integration test / Dart runner 调用 CLI 子进程
  |
  +-- awiki-cli-rs2 awiki-cli（客户端 B）
        |
        +-- AWIKI_CLI_WORKSPACE_HOME_DIR=.e2e/desktop-cli-peer/<run-id>/cli-peer
        +-- CLI config 指向同一套非生产服务
        +-- id register / id recover
        +-- msg send / msg inbox / msg history
```

第一版建议走 HTTP / pull 语义验证：

- App A 通过 UI 或测试专用启动步骤完成登录 / 注册 / 恢复；
- CLI B 在隔离 workspace 中完成注册 / 恢复；
- App A 发送一条带唯一 run id 的消息给 CLI B；
- CLI B 轮询 `msg inbox` 或 `msg history --with <app-handle>`，直到看到该消息；
- CLI B 发送一条带唯一 run id 的消息给 App A；
- App A 通过刷新 / inbox / conversation UI 等确定性路径看到该消息；
- realtime / WebSocket listener 可以作为第二阶段增强，不作为首个 Desktop App+CLI peer smoke 必需条件。

## 5. Harness 上下文

| 来源 | 作用 |
|---|---|
| `awiki-harness/AGENTS.md` | 多仓库任务读取顺序、权威来源和完成标准 |
| `awiki-harness/README.md` | Harness 控制面定位和文档边界 |
| `awiki-harness/context/00-context-map.md` | 任务路由到 Client Architecture、Message Flow、System Test |
| `awiki-harness/context/02-repo-map.md` | `test-awiki-me`、`awiki-cli-rs2`、`user-service`、`awiki-system-test` 职责 |
| `awiki-harness/context/03-cross-repo-architecture.md` | App / CLI / Dart SDK / Rust `im-core` 依赖方向 |
| `awiki-harness/context/20-rules-index.md` | 文档、架构、AI coding、验证规则入口 |
| `awiki-harness/context/30-tools-env.md` | Flutter、Rust CLI、system-test 常用命令 |
| `awiki-harness/context/40-verification.md` | L0-L3 验证分级和证据要求 |
| `awiki-harness/context/50-task-workflow.md` | 非平凡任务的 context-pack、analysis、plan、verification 流程 |
| `awiki-harness/context/nodes/client-architecture.node.md` | App / CLI / SDK 边界，App 不直接拼 service wire payload |
| `awiki-harness/context/nodes/message-flow.node.md` | 消息服务边界，App / CLI 应通过 `im-core` 高层能力 |
| `awiki-harness/context/nodes/system-test.node.md` | 跨服务 E2E 和本地环境清理要求 |

## 6. 影响分析

| 领域 / 仓库 / 模块 | 影响 | 权威文档或代码 |
|---|---|---|
| `test-awiki-me` Linux runner | 新增 `linux/` runner，先跑 fake bootstrap smoke，再跑真实 SDK / E2E | `test-awiki-me/AGENTS.md`、`test-awiki-me/docs/testing.md` |
| `test-awiki-me` integration tests | 新增 Linux native smoke；只新增或调整一个 `desktop_cli_peer_smoke_test.dart`，同时支持 macOS / Linux | `test-awiki-me/integration_test/`、`test-awiki-me/tool/e2e_runner.dart` |
| `awiki-cli-rs2/packages/awiki_im_core` | 声明 Linux plugin，补 loader，打包 `libawiki_im_core.so` | `awiki-cli-rs2/docs/flutter-sdk/awiki-im-core-flutter-sdk.md` |
| `awiki-cli-rs2/crates/im-core-dart` | Linux native build target 和 feature 组合 | `awiki-cli-rs2/crates/im-core-dart/Cargo.toml` |
| `awiki-cli-rs2/crates/awiki-cli` | 作为 peer 客户端，隔离 workspace，执行注册 / 恢复 / 消息命令 | `awiki-cli-rs2/docs/architecture/awiki-command-v2.md`、`awiki-cli-rs2/onboarding.md` |
| `user-service` | 提供非生产测试 OTP 和服务配置；原则上不需要代码改动 | `user-service/README.md`、`user-service/.env` |
| `awiki-system-test` | 可选：如果要统一启动本地服务或 nightly E2E 编排，后续可接入 | `awiki-harness/context/nodes/system-test.node.md` |

## 7. 总体设计方法

- 设计边界：`xvfb-run` 只作为显示层；Linux runner、SDK Linux native、账号服务、CLI peer 和 E2E harness 分层验收。
- 关键决策：第一版用一个 Flutter Desktop App + 一个 CLI peer 代替两台真实桌面设备，先验证 macOS / Linux 共用的端到端消息闭环；两台 App UI 或真实多设备保留为后续。
- SDK 策略：因为项目目标包含 Flutter 3.24+，短期按当前 plugin_ffi / CMake 打包思路支持 Linux `.so`；当 Flutter baseline 提升到 3.38+ 后，再评估迁移到 `package_ffi` native assets build hooks。
- 消息策略：第一版使用 pull / polling 断言 inbox/history，不把 realtime listener 当作首个阻塞条件。
- 账号策略：使用 `user-service/.env` 中的非生产 `DEV_OTP_PHONE` / `DEV_OTP_CODE` 等 key；运行脚本只读取本地环境变量，不输出、不提交实际值。
- 状态隔离：App 测试状态和 CLI peer workspace 都写入 `.e2e/` 或系统临时目录；`.e2e/` 不提交。
- 安全策略：文档、脚本、报告不得包含 OTP 值、JWT、私钥、DID 私钥文件、CLI workspace、SQLite state 或 message content 之外的敏感调试输出。

## 8. 任务拆分

| Step | 标题 | 依赖 | 产出 | 小 Plan 文档 | Commit gate | 状态 |
|---|---|---|---|---|---|---|
| 01 | Linux runner 与 desktop smoke | 无 | `test-awiki-me/linux/` runner；fake bootstrap Linux smoke 可跑 | [steps/01-linux-runner-smoke.md](steps/01-linux-runner-smoke.md) | 必须 | pending |
| 02 | `awiki_im_core` Linux native SDK | Step 01 可并行前置分析；SDK 改动独立 | Linux `.so` 构建、plugin 声明、loader、native open smoke | [steps/02-linux-native-sdk.md](steps/02-linux-native-sdk.md) | 必须 | pending |
| 03 | CLI peer 账号与服务编排 | Step 02 的 SDK 配置结论；服务账号策略 | 隔离 CLI workspace、测试账号读取、runner 配置样例 | [steps/03-cli-peer-account-service-orchestration.md](steps/03-cli-peer-account-service-orchestration.md) | 必须 | pending |
| 04 | App + CLI peer Desktop E2E smoke | Step 01-03 | `desktop_cli_peer_smoke_test.dart` 和 Desktop runner；macOS / Linux 双向消息验收 | [steps/04-app-cli-peer-e2e.md](steps/04-app-cli-peer-e2e.md) | 必须 | pending |
| 05 | CI / nightly gate 与文档收口 | Step 01-04 | quick gate / nightly gate 分层、docs 更新、最终验证证据 | [steps/05-ci-nightly-gates.md](steps/05-ci-nightly-gates.md) | 必须 | pending |

## 9. 执行台账

状态取值：`pending`、`in_progress`、`review`、`blocked`、`committed`、`done`。

| Step | 状态 | 分支 | 开始时间 | 完成时间 | Commit | Review 证据 | 验证证据 | 下一步 |
|---|---|---|---|---|---|---|---|---|
| 01 | done | `feature/test-awiki-me` | 2026-06-13 19:48:55 CST | 2026-06-13 20:22:21 CST | `6bfc504` | Review：diff 限于 Linux runner、Linux smoke 测试收敛和依赖文档；无无关 Android / iOS / macOS / web runner 变更；`linux/flutter/ephemeral` 被 `.gitignore` 排除 | `flutter doctor` Linux toolchain 通过；`flutter devices` 看到 Linux desktop；`flutter test` 通过；`xvfb-run -a flutter test integration_test/app_smoke_test.dart -d linux` 通过；`dart analyze` 通过；`git diff --check` 通过 | 启动 Step 02 |
| 02 | pending | `feature/test-awiki-me` / `awiki-cli-rs2` 当前工作分支 | - | - | - | - | - | 等 Step 01 commit 后启动 SDK 分析 |
| 03 | pending | `feature/test-awiki-me` | - | - | - | - | - | 等账号策略确认 |
| 04 | pending | `feature/test-awiki-me` | - | - | - | - | - | 等 Step 01-03 |
| 05 | pending | `feature/test-awiki-me` | - | - | - | - | - | 等 Step 04 |

## 10. Codex Goal 执行协议

- 将本 Plan 作为执行进度的唯一事实来源。
- 启动或恢复前，读取本 Plan、当前小 Plan、执行台账和当前 `git status --short --branch`。
- 同一时间只执行一个步骤，除非本 Plan 明确标记多个步骤彼此独立且可以并行。
- 恢复时，从第一个状态不是 `done` 的步骤继续。
- 每个步骤依次执行：标记 `in_progress`、实现、验证、Review、修复或记录 Review 发现、提交、记录证据、标记 `done`。
- 上一个依赖步骤的完成工作未提交前，不要开始下一个依赖步骤。
- 改变范围、顺序、验收标准、公开契约、数据模型或验证策略前，先更新本 Plan。
- 当前用户要求是先确认方案；只有用户明确要求执行 Plan 后，才修改 runner、SDK、测试或 CI 代码。

## 10.1 Codex Goal 提示词

```text
请以 `test-awiki-me/docs/e2e/linux-desktop-cli-peer-e2e/plan.md` 为唯一规划入口，按文档执行 Desktop CLI Peer macOS / Linux E2E 完整实现；同时阅读 `test-awiki-me/docs/e2e/desktop-cli-peer-macos-linux-plan.md` 作为总方案摘要。

开始前先读取：
- `test-awiki-me/docs/e2e/linux-desktop-cli-peer-e2e/plan.md`
- 当前第一个未 done 的 Step 文档
- 主 Plan 的执行台账、Codex Goal 执行协议、验证策略、Blocked 处理和 Plan 变更记录
- 当前 `git status --short --branch`

请从第一个状态不是 `done` 的步骤开始，一次只执行一个步骤。每步都要按对应小 Plan 实现、验证、Review、修复或记录 Review 发现，然后创建一个聚焦 commit，并回填主 Plan 执行台账和 Step 执行状态。需要改变范围、顺序、验收标准、公开契约、数据模型或验证策略时，先更新 Plan 变更记录。

所有步骤完成后，执行最终全局 Review 和整体验证，记录实际命令、通过/失败/跳过数量、失败或跳过原因、剩余风险和最终工作区状态。

核心注意点：不要提交 `.env` 值、OTP、JWT、私钥、CLI workspace、`.e2e/` 报告或本地状态；先用 Xvfb + fake bootstrap smoke 验证 Linux runner，再接 Linux native SDK，再做一个 macOS / Linux 共用的真实 App+CLI peer smoke；不要扩展大量 E2E 用例；App 和 CLI 必须通过 SDK/CLI 高层能力走同一非生产服务，不要在 App 内重写 message-service wire payload。
```

## 11. 小 Plan 摘要

### Step 01：Linux runner 与 desktop smoke

- 小 Plan：[steps/01-linux-runner-smoke.md](steps/01-linux-runner-smoke.md)
- 目标：让 `test-awiki-me` 支持 Linux Desktop runner，并让 `integration_test/app_smoke_test.dart` 在 `xvfb-run` 下通过。
- 设计方法：只引入 Linux runner，不触碰 Android / iOS / macOS / web runner。
- 实现方法：使用 Flutter 工具生成 Linux runner，检查 diff，保留必要 Linux 文件；跑 fake bootstrap smoke。
- 路径：`test-awiki-me/linux/`、`test-awiki-me/.metadata`、`test-awiki-me/docs/testing.md`。
- 验证方式：`xvfb-run -a flutter test integration_test/app_smoke_test.dart -d linux`。
- Review 环节：检查 runner diff 是否只限 Linux，确认没有平台签名或其他 runner 元数据漂移。
- Commit 要求：一个 focused commit。
- 风险：`flutter create --platforms=linux .` 可能更新 `.metadata` 或插件文件，需要逐项检查。

### Step 02：`awiki_im_core` Linux native SDK

- 小 Plan：[steps/02-linux-native-sdk.md](steps/02-linux-native-sdk.md)
- 目标：让 Flutter Linux App 能加载 Rust `im-core-dart` 产物。
- 设计方法：延续现有 Android / Apple native artifact 脚本风格，新增 Linux `.so` build 和 plugin bundling。
- 实现方法：补 Linux platform declaration、loader、CMake / bundled library、build script、docs 和 native smoke。
- 路径：`awiki-cli-rs2/packages/awiki_im_core/`、`awiki-cli-rs2/crates/im-core-dart/`、`test-awiki-me/integration_test/im_core_open_smoke_test.dart`。
- 验证方式：`cargo build -p im-core-dart --release --target x86_64-unknown-linux-gnu --no-default-features --features blocking,sqlite,http`，再跑 Linux native smoke。
- Review 环节：检查 ABI、library name、bundle path、loader fallback、安全输出和已有 Android / iOS / macOS 不回归。
- Commit 要求：SDK 仓一个 focused commit；App smoke 调整如有需要另起 commit。
- 风险：Linux CMake bundling 与 `DynamicLibrary.open('libawiki_im_core.so')` 的搜索路径要以实际 `flutter test -d linux` 验证为准。

### Step 03：CLI peer 账号与服务编排

- 小 Plan：[steps/03-cli-peer-account-service-orchestration.md](steps/03-cli-peer-account-service-orchestration.md)
- 目标：提供可重复的 CLI peer 账号准备、服务配置和本地状态隔离。
- 设计方法：从 `user-service/.env` 读取 key，不把值写入 repo；CLI 使用独立 `AWIKI_CLI_WORKSPACE_HOME_DIR`。
- 实现方法：新增 Dart runner / 配置样例，构建 CLI，初始化 workspace，注册或恢复 CLI peer handle。
- 路径：`test-awiki-me/tool/`、`test-awiki-me/docs/testing.md`、`awiki_e2e.example.yaml` 或新的示例配置。
- 验证方式：CLI `id current`、`id status`、`msg inbox --limit 1 --format json` 返回可解析 JSON。
- Review 环节：检查 secret handling、workspace 清理、账号冲突处理和服务地址一致性。
- Commit 要求：一个 focused commit。
- 风险：`DEV_OTP_PHONE` / `DEV_OTP_CODE` 是否允许两个 handle 是完整双端 E2E 的关键未知点。

### Step 04：App + CLI peer Desktop E2E smoke

- 小 Plan：[steps/04-app-cli-peer-e2e.md](steps/04-app-cli-peer-e2e.md)
- 目标：在同一个 Desktop integration test 中完成 App A 与 CLI B 双向消息验证，测试可在 macOS 和 Linux 上运行。
- 设计方法：真实 `AppBootstrap.create()` + CLI subprocess；第一版使用 polling，不依赖 realtime listener。
- 实现方法：新增或调整 `integration_test/desktop_cli_peer_smoke_test.dart`，补必要 E2E semantics，runner 传入服务配置和 CLI peer 信息。
- 路径：`test-awiki-me/integration_test/`、`test-awiki-me/lib/src/presentation/`、`test-awiki-me/tool/`。
- 验证方式：macOS 运行 `flutter test integration_test/desktop_cli_peer_smoke_test.dart -d macos`；Linux headless 运行 `xvfb-run -a flutter test integration_test/desktop_cli_peer_smoke_test.dart -d linux`，并检查 App->CLI、CLI->App 两条唯一消息都被确认。
- Review 环节：检查测试确定性、超时、日志脱敏、selectors 稳定性和失败证据。
- Commit 要求：一个 focused commit。
- 风险：App 侧登录 UI、收件箱刷新和消息列表 selector 可能需要小范围增强。

### Step 05：CI / nightly gate 与文档收口

- 小 Plan：[steps/05-ci-nightly-gates.md](steps/05-ci-nightly-gates.md)
- 目标：把 Linux Desktop smoke 和真实 E2E 放到合适 gate，避免 PR 被后端账号或服务波动拖垮。
- 设计方法：PR quick gate 跑 no-backend / fake smoke；真实 App+CLI peer E2E 放 nightly、manual 或 release gate。
- 实现方法：更新 CI workflow、docs、运行手册和跳过条件。
- 路径：`test-awiki-me/.github/workflows/`、`test-awiki-me/docs/testing.md`、本 Plan。
- 验证方式：PR gate 命令和 nightly 命令都可 dry-run 或实际通过；失败时保留脱敏证据。
- Review 环节：检查 gate 分层、runner 依赖、secret 配置和文档一致性。
- Commit 要求：一个 focused commit。
- 风险：真实后端依赖不适合默认 PR gate，必须保持可跳过和可诊断。

## 12. 测试命令设计

### Ubuntu 依赖

Flutter 官方 Linux setup 需要 Linux desktop toolchain，例如 `clang`、`cmake`、`ninja-build`、`pkg-config`、GTK 开发库等；Linux CI 跑 desktop integration test 时需要 X Server，可用 `xvfb-run` 启动虚拟显示。

```bash
sudo apt update
sudo apt install -y \
  clang cmake ninja-build pkg-config libgtk-3-dev liblzma-dev \
  libstdc++-12-dev libsecret-1-dev xvfb dbus-x11
flutter config --enable-linux-desktop
flutter doctor
flutter devices
```

### 分层验证

```bash
cd test-awiki-me
PUB_HOSTED_URL=https://mirrors.tuna.tsinghua.edu.cn/dart-pub flutter pub get
dart analyze
flutter test
```

Linux runner smoke：

```bash
cd test-awiki-me
xvfb-run -a flutter test integration_test/app_smoke_test.dart -d linux
```

SDK Linux native build：

```bash
cd awiki-cli-rs2
cargo build \
  -p im-core-dart \
  --release \
  --target x86_64-unknown-linux-gnu \
  --no-default-features \
  --features blocking,sqlite,http
```

SDK Linux native smoke：

```bash
cd test-awiki-me
xvfb-run -a flutter test integration_test/im_core_open_smoke_test.dart -d linux
```

真实 App + CLI peer E2E，后续 runner 形态建议：

```bash
cd test-awiki-me
# Required in the shell before running: DEV_OTP_PHONE and DEV_OTP_CODE.
AWIKI_CLI_BIN="../awiki-cli-rs2/target/release/awiki-cli" \
dart run tool/desktop_cli_peer_e2e_runner.dart \
  --service-base-url "$AWIKI_SERVICE_BASE_URL" \
  --did-domain "$AWIKI_DID_DOMAIN" \
  --platform linux
```

runner 内部再调用：

```bash
xvfb-run -a flutter test integration_test/desktop_cli_peer_smoke_test.dart -d linux \
  --dart-define=AWIKI_E2E=true \
  --dart-define=AWIKI_SERVICE_BASE_URL=<non-production-base-url> \
  --dart-define=AWIKI_DID_DOMAIN=<test-did-domain>
```

注意：OTP、JWT、私钥和 CLI workspace 路径不应打印到日志；服务地址和 DID domain 可以作为非敏感测试配置记录。

## 13. 账号与服务策略

- 从 `user-service/.env` 读取测试 key：`DEV_OTP_PHONE`、`DEV_OTP_CODE`、`HANDLE_DOMAIN`、`DID_HOSTNAME`、`USER_SERVICE_HOST`、`USER_SERVICE_PORT`、`MOLT_MESSAGE_URL` 或当前测试环境等价配置。
- 文档和 repo 中只记录 key 名，不记录值。
- 首选每次运行生成唯一 handle，例如 `e2eapp<runid>` 和 `e2ecli<runid>`；如果服务不允许同一测试手机号注册多个 handle，则改用预置账号池或一个 App 测试账号 + 一个 CLI 测试账号。
- 对已存在 handle，runner 应先尝试 `id recover`，对新 handle 才尝试 `id register`；具体顺序以 User Service 当前账号策略验证后固化。
- App 端与 CLI 端必须使用不同本地状态目录，避免同一 DID / key 文件被两个客户端同时读写。
- CLI 端通过 `AWIKI_CLI_WORKSPACE_HOME_DIR=.e2e/desktop-cli-peer/<run-id>/cli-peer` 隔离。
- App 端测试状态需要使用临时目录或 `.e2e/linux-app/<run-id>`；如果现有 App path layout 只能走平台 application support directory，后续 Step 04 需要增加测试专用路径注入，不能污染开发者真实 App 状态。

## 14. 验收标准

- [ ] `flutter devices` 能看到 `Linux (desktop)`。
- [ ] `xvfb-run -a flutter test integration_test/app_smoke_test.dart -d linux` 通过。
- [ ] Linux native SDK 构建产物存在并被 Flutter Linux bundle 打包。
- [ ] `AwikiImCore.open` Linux smoke 通过，不再因 Linux loader 抛 `UnsupportedError`。
- [ ] CLI peer 能在隔离 workspace 中注册或恢复测试身份，并能执行 `msg inbox`。
- [ ] App A 能使用真实 SDK 登录 / 注册 / 恢复到测试身份。
- [ ] App A -> CLI B 消息能被 CLI `msg inbox` 或 `msg history` 观察到。
- [ ] CLI B -> App A 消息能在 App UI 或 App SDK-backed conversation 中观察到。
- [ ] E2E 日志和报告不包含 OTP、JWT、私钥、DID 私钥内容或 `.env` 值。
- [ ] PR quick gate 与 nightly/manual gate 分层清楚，真实后端 E2E 不阻塞普通 PR。

## 15. Review 策略

- 每步骤 Review：重点检查 diff 是否只触及本步骤范围、跨仓契约是否一致、测试是否覆盖本步骤风险、是否泄露 secret、是否改动无关平台 runner。
- 全局 Review：完成所有步骤后，统一检查 App runner、SDK loader / bundling、CLI runner、CI gate、docs、执行台账和未提交变更。
- 契约 / 安全 / 隐私 Review：重点检查账号凭据、JWT、DID 私钥、本地状态目录、CLI workspace、message content 日志、SDK native library 产物路径。
- 文档 Review：`test-awiki-me/docs/testing.md`、`awiki-cli-rs2/docs/flutter-sdk/awiki-im-core-flutter-sdk.md`、本 Plan 和 step 状态必须一致。

## 16. 验证策略

| 层级 | 命令 / 检查 | 预期证据 |
|---|---|---|
| L0 Docs | `git diff --check`；检查 Plan 链接和路径 | 文档无 trailing whitespace，无本机绝对路径，无敏感值 |
| L1 App | `cd test-awiki-me && dart analyze && flutter test` | App 单元 / widget 现有套件通过 |
| L1 Linux smoke | `cd test-awiki-me && xvfb-run -a flutter test integration_test/app_smoke_test.dart -d linux` | Linux runner + Flutter Desktop shell 可启动 |
| L1 SDK | `cd awiki-cli-rs2 && cargo test -p im-core-dart --locked`、`scripts/flutter/codegen-check.sh` | Rust-Dart facade 和 generated bridge 不回归 |
| L1 SDK native | `cd awiki-cli-rs2 && scripts/flutter/build-sdk-native.sh --linux-only` | Linux `.so` 生成并复制 / 打包到 plugin 预期位置 |
| L2 Cross-repo | `cd test-awiki-me && xvfb-run -a flutter test integration_test/im_core_open_smoke_test.dart -d linux` | App 能打开 Linux native SDK |
| L3 E2E | `cd test-awiki-me && dart run tool/desktop_cli_peer_e2e_runner.dart --platform macos ...` 或 `--platform linux ...` | App+CLI peer 双向消息闭环通过，报告脱敏 |

## 17. 文档更新

- Harness 文档：本方案不要求立即更新 Harness；如果后续 Desktop App+CLI peer smoke 成为 AWiki 标准系统测试入口，再更新 `awiki-harness/context/30-tools-env.md` 和 `awiki-harness/context/40-verification.md`。
- 子仓库文档：更新 `test-awiki-me/docs/testing.md`，并在 SDK 实现步骤更新 `awiki-cli-rs2/docs/flutter-sdk/awiki-im-core-flutter-sdk.md`。
- 本次生成的任务文档：`test-awiki-me/docs/e2e/linux-desktop-cli-peer-e2e/plan.md` 与 `steps/*.md`。

## 18. Commit 计划

- 每个完成、验证、Review 通过的步骤创建一个聚焦 commit。
- Commit 前记录 `git status --short --branch` 和纳入文件。
- Commit 后记录 commit hash 和工作区状态。
- 跨仓步骤优先拆成每仓独立 commit；只有必须保持构建原子性时才合并。
- 不要把所有实现步骤积累到一个最终大 commit。

## 19. Blocked 处理

| Blocker | Step | 证据 | 已尝试方案 | 影响范围 | 下一步决策 |
|---|---|---|---|---|---|
| `DEV_OTP_PHONE` / `DEV_OTP_CODE` 只能恢复一个固定账号，不能准备两个身份 | 03 / 04 | CLI / App 注册或恢复第二个 handle 失败 | 尝试唯一 handle、已存在 handle recover、账号池 | 整体 E2E | 请求提供第二个测试账号或新增服务端测试账号池 |
| Linux `.so` 能构建但 Flutter bundle 找不到 | 02 | `DynamicLibrary.open` 失败 | 检查 CMake bundled libraries、bundle `lib/`、loader fallback | SDK / E2E | 修正 Linux plugin bundling 或 loader |
| App 真实 bootstrap 污染本地状态 | 04 | 状态写入默认 app support dir | 增加测试专用 path 注入或 runner 清理 | App E2E | 不进入 nightly gate 前必须解决 |
| 后端服务不稳定或 message route 不一致 | 04 / 05 | CLI send / inbox 超时或返回服务错误 | 检查 service base URL、DID domain、message-service v2/legacy 选择 | E2E gate | 将真实 E2E 保持 manual/nightly，记录服务证据 |

## 20. Plan 变更记录

| 日期 | 变更 | 原因 | 影响步骤 | 是否需要 Review |
|---|---|---|---|---|
| 2026-06-13 | 创建初始方案 | 用户要求先确认 Linux Desktop runner、Linux native SDK、CLI peer E2E 可行性并写入 docs | Step 01-05 | 是 |
| 2026-06-13 | 收敛为 macOS / Linux 共用最小 Desktop smoke | 用户要求最终测试用例可对应 Linux 和 Mac，且先只补一个最基本测试用例 | Step 03-05 | 是 |

## 21. 风险与回滚

| 风险 | 缓解措施 | 回滚 / 回退方案 |
|---|---|---|
| Linux runner 生成时改动无关平台文件 | 使用 `flutter create --platforms=linux .` 后逐文件 review；只保留必要 Linux runner 变化 | 回滚无关 Android / iOS / macOS / web 变化 |
| Linux native SDK 打包方式与 Flutter 版本不匹配 | 以项目 Flutter 3.24+ 为短期约束，先用 plugin_ffi/CMake；记录未来 native assets 迁移点 | 保持 Linux SDK gate 非必需，回退到 macOS-only native smoke |
| 测试账号复用策略不支持双身份 | 预置账号池或增加服务端测试账号 fixture | 只保留 App smoke 和 CLI 单端验证，不声明完整 E2E |
| 真实后端 E2E flake | 使用唯一 run id、poll timeout、结构化 report、失败证据脱敏 | 将真实 E2E 放 nightly/manual，不进 PR required gate |
| Secret 泄露 | `.env` 只本地读取；日志脱敏；`.e2e/` 忽略；Review 加 secret grep | 立即删除泄露文件、rotate 测试凭据、修正日志 |

## 22. 最终全局 Review 与整体验证

- 触发条件：Step 01-05 全部完成、Review、验证并提交后执行。
- Review 范围：`test-awiki-me`、`awiki-cli-rs2`、必要 CI 配置、测试文档、SDK 文档、执行台账、`.gitignore`、未提交变更。
- 重点关注：Linux runner 是否影响其他平台，SDK Linux loader 是否影响 Android / iOS / macOS，E2E 是否只通过高层 SDK / CLI 能力，secret 是否安全，真实 E2E 是否放在正确 gate。
- 整体验证命令 / 检查：`dart analyze`、`flutter test`、Linux app smoke、Linux SDK open smoke、CLI peer E2E、`cargo test -p im-core-dart --locked`、`cargo test -p awiki-cli --locked` 中与变更相关的 focused tests、`git diff --check`。
- Review 发现：执行时填写。
- 已修复问题：执行时填写。
- 剩余风险：执行时填写。
- 最终证据：执行时填写。
- 最终 `git status`：执行时填写。
- 如果本阶段修改文件：记录 Review、验证和最终集成 commit。

## 23. 参考资料

- Flutter Linux setup：<https://docs.flutter.dev/platform-integration/linux/setup>
- Flutter desktop support：<https://docs.flutter.dev/platform-integration/desktop>
- Flutter integration test Linux / Xvfb：<https://docs.flutter.dev/testing/integration-tests>
- Flutter legacy FFI plugin：<https://docs.flutter.dev/platform-integration/legacy-ffi-plugin>
- Flutter pubspec plugin options：<https://docs.flutter.dev/tools/pubspec>
