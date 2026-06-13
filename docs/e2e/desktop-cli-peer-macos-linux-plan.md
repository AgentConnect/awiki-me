# Desktop CLI Peer macOS / Linux E2E 方案

状态：draft  
创建时间：2026-06-13  
适用范围：`test-awiki-me` 当前分支合并 `feature/release-0526/agent-im-hutong` 后，复用已有测试框架，补齐 Linux Desktop 运行目标。  
执行边界：本文是方案文档；当前生成本文档时不执行 merge、不修改测试代码、不运行测试。

## 1. 目标

把 `feature/release-0526/agent-im-hutong` 中已经建立的测试框架合入当前分支，并在该框架上形成一个同时支持 macOS 和 Linux Desktop 的最小端到端测试方案。

本阶段只规划一个最基础的 Desktop E2E smoke：

- Desktop App 作为客户端 A。
- 现有 `awiki-cli-rs2` CLI 作为 peer 客户端 B。
- App A 与 CLI B 使用非生产测试账号和同一套测试服务。
- App A -> CLI B 发送一条带唯一 `runId` 的消息。
- CLI B 通过 `msg inbox` 或 `msg history` 确认收到。
- CLI B -> App A 发送一条带唯一 `runId` 的消息。
- App A 通过 UI 或 SDK-backed conversation 确认收到。

## 2. 非目标

第一阶段不扩展大量测试用例，也不把完整业务流程都压到 Desktop E2E 中。

明确不做：

- 不重写 `feature/release-0526/agent-im-hutong` 已有测试框架。
- 不新增大批 integration / E2E 用例。
- 不测试系统通知弹窗、系统原生文件选择器、窗口拖拽、系统菜单、多显示器行为。
- 不把 realtime WebSocket 稳定性作为第一阶段阻塞项。
- 不在这个 Desktop smoke 里重新断言完整 E2EE 内部细节；端到端加密覆盖继续复用已有系统测试 / E2EE 测试框架。
- 不把真实后端、真实 OTP、真实 CLI peer 的 full E2E 直接放进普通 PR required gate。

## 3. 当前假设

- `feature/release-0526/agent-im-hutong` 已经包含较完善的单元测试、系统测试、端到端加密测试和基础 E2E runner / 文档。
- macOS Desktop 路径已有原生 SDK 支持，可作为 Desktop E2E 的第一套运行环境。
- Linux Desktop 当前缺口主要是 runner、headless 显示环境、Linux native SDK build / bundle / loader、CI 依赖和运行命令。
- `user-service/.env` 或 CI secrets 中有非生产测试账号 / OTP 配置，但方案和代码都不得提交实际值。
- CLI peer 应使用独立 workspace，例如 `.e2e/desktop-cli-peer/<runId>/cli-peer`，不能污染默认 `~/.awiki-cli/`。

执行者不要假设分支一定未合并。开始执行时必须先检查：

```bash
cd test-awiki-me
git status --short --branch
git merge-base --is-ancestor feature/release-0526/agent-im-hutong HEAD
```

如果目标分支已经是当前分支祖先，记录 merge no-op 证据即可；如果不是，再执行合并。

## 4. 复用策略

合并 `feature/release-0526/agent-im-hutong` 后，应优先复用该分支已经存在的结构：

| 既有能力 | 复用方式 |
|---|---|
| 单元测试 | 保持 `flutter test` 和现有 focused tests，不为 Linux E2E 重复写业务单测 |
| 系统测试 | 继续作为协议、服务、E2EE 细节的权威验证层 |
| 端到端加密测试 | 继续覆盖 E2EE 内部行为，Desktop smoke 只验证用户路径消息闭环 |
| Desktop integration smoke | 复用 App bootstrap / native smoke / E2E selector 约定 |
| E2E runner 配置 | 复用账号、服务地址、run id、report、secret redaction、cleanup |
| CLI peer 编排 | 复用 CLI binary、`AWIKI_CLI_WORKSPACE_HOME_DIR`、`id recover/register`、`msg send/inbox/history` |

Linux 不是新框架，只是同一个 Desktop smoke 的第二个 platform target。

## 5. Linux 需要补齐的缺口

### 5.1 Flutter Linux runner

如果合并后仍没有 Linux runner，需要新增：

```bash
cd test-awiki-me
flutter create --platforms=linux .
```

Review 要求：

- 只保留 `linux/` runner 和必要 `.metadata` 变化。
- 不修改 Android / iOS / macOS / web runner。
- 不修改签名、bundle id、entitlements、Pod / Gradle / Xcode metadata。

### 5.2 Ubuntu headless 依赖

Linux 本地或 CI runner 需要 Desktop build deps 和虚拟显示环境。参考 Flutter 官方 Linux setup 与 integration test 文档。

```bash
sudo apt update
sudo apt install -y \
  clang cmake ninja-build pkg-config libgtk-3-dev liblzma-dev \
  xvfb dbus-x11
flutter config --enable-linux-desktop
flutter devices
```

Linux headless 运行时使用：

```bash
xvfb-run -a flutter test integration_test/desktop_cli_peer_smoke_test.dart -d linux
```

### 5.3 Linux native SDK

`awiki_im_core` 必须支持 Linux：

- `awiki-cli-rs2/packages/awiki_im_core/pubspec.yaml` 声明 Linux plugin。
- `awiki-cli-rs2/packages/awiki_im_core/lib/src/native_library_loader.dart` 支持 `Platform.isLinux`。
- `awiki-cli-rs2/crates/im-core-dart` 能构建 `libawiki_im_core.so`。
- Flutter Linux app bundle 能找到并加载该 `.so`。
- Linux 下 `AwikiImCore.open` smoke 通过。

建议构建命令：

```bash
cd awiki-cli-rs2
cargo build \
  -p im-core-dart \
  --release \
  --target x86_64-unknown-linux-gnu \
  --no-default-features \
  --features blocking,sqlite,http
```

建议 smoke：

```bash
cd test-awiki-me
xvfb-run -a flutter test integration_test/im_core_open_smoke_test.dart -d linux
```

### 5.4 CLI peer 隔离

CLI peer 必须使用独立 workspace：

```bash
export AWIKI_CLI_WORKSPACE_HOME_DIR=".e2e/desktop-cli-peer/<runId>/cli-peer"
```

CLI peer 准备流程应复用已有 runner：

```bash
awiki-cli init
awiki-cli id recover --handle <cli-handle> --phone <test-phone> --otp <test-otp> --format json
# 如 recover 明确表示 handle 不存在，再尝试 register
awiki-cli id register --handle <cli-handle> --phone <test-phone> --otp <test-otp> --format json
awiki-cli id status --format json
```

日志和 report 中不得输出 OTP、JWT、私钥、`.env` 行或 identity 文件内容。

## 6. macOS / Linux 统一测试入口

测试用例建议统一命名：

```text
integration_test/desktop_cli_peer_smoke_test.dart
```

macOS 运行：

```bash
cd test-awiki-me
flutter test integration_test/desktop_cli_peer_smoke_test.dart -d macos
```

Linux headless 运行：

```bash
cd test-awiki-me
xvfb-run -a flutter test integration_test/desktop_cli_peer_smoke_test.dart -d linux
```

runner 内部可以抽象 platform target：

| Platform | Flutter device | Display wrapper | Native SDK |
|---|---|---|---|
| macOS | `macos` | 无 | 复用现有 macOS native SDK |
| Linux | `linux` | `xvfb-run -a` | 新增 Linux `.so` build / bundle / loader |

同一个 Dart test 应避免写死平台。平台差异放到 runner / config 层。

## 7. 最小 E2E smoke 设计

### 7.1 输入

通过已有 E2E runner 或新增最小 desktop runner 传入：

```text
AWIKI_E2E=true
AWIKI_SERVICE_BASE_URL
AWIKI_DID_DOMAIN
AWIKI_ANP_SERVICE_URL
AWIKI_ANP_SERVICE_DID
DEV_OTP_PHONE
DEV_OTP_CODE
AWIKI_E2E_APP_HANDLE
AWIKI_E2E_CLI_HANDLE
AWIKI_E2E_RUN_ID
AWIKI_CLI_BIN
```

真实值来自本地环境或 CI secrets，不写入 repo。

### 7.2 流程

1. runner 创建 `runId`，初始化 report 目录。
2. runner 准备 CLI peer workspace。
3. runner 构建或定位 `awiki-cli`。
4. runner 为 CLI peer 执行 `id recover` 或 `id register`。
5. Flutter Desktop App 启动。
6. App 端通过 UI 或已有测试 bootstrap 完成身份准备。
7. App A 发送消息：

   ```text
   e2e app to cli <runId>
   ```

8. CLI B 轮询：

   ```bash
   awiki-cli msg history --with <app-handle> --limit 20 --format json
   ```

   或：

   ```bash
   awiki-cli msg inbox --limit 20 --format json
   ```

9. CLI B 发送消息：

   ```bash
   awiki-cli msg send --to <app-handle> --text "e2e cli to app <runId>" --format json
   ```

10. App A 通过 UI 或 SDK-backed conversation 等待并确认消息出现。
11. runner 写入脱敏结果和耗时。
12. runner 清理或保留本地 `.e2e/` 报告，报告不得提交。

### 7.3 断言

最小断言只需要：

- App 启动成功。
- App 身份准备成功。
- CLI peer 身份准备成功。
- App -> CLI 消息包含当前 `runId`，并被 CLI 确认。
- CLI -> App 消息包含当前 `runId`，并被 App 确认。
- 所有失败输出脱敏。

## 8. 实施步骤

### Step 1：合并并复核既有测试框架

执行：

```bash
cd test-awiki-me
git status --short --branch
git merge feature/release-0526/agent-im-hutong
```

如果 merge 是 no-op，记录证据即可。

复核：

- 单元测试入口。
- 系统测试入口。
- E2EE 测试入口。
- macOS Desktop smoke。
- E2E runner / config / report / redaction。

### Step 2：补 Linux Desktop runner

如果缺少 `linux/`，新增 Linux runner，并只保留 Linux 相关 diff。

验证：

```bash
cd test-awiki-me
flutter devices
xvfb-run -a flutter test integration_test/app_smoke_test.dart -d linux
```

### Step 3：补 Linux native SDK

在 `awiki-cli-rs2` 补 Linux native build / bundle / loader。

验证：

```bash
cd awiki-cli-rs2
cargo test -p im-core-dart --locked
cargo build -p im-core-dart --release --target x86_64-unknown-linux-gnu --no-default-features --features blocking,sqlite,http
```

再验证 App Linux native smoke：

```bash
cd test-awiki-me
xvfb-run -a flutter test integration_test/im_core_open_smoke_test.dart -d linux
```

### Step 4：把 Desktop smoke 改成 macOS / Linux 双目标

复用已有 E2E runner，只新增或调整一个测试用例：

```text
integration_test/desktop_cli_peer_smoke_test.dart
```

验证：

```bash
cd test-awiki-me
flutter test integration_test/desktop_cli_peer_smoke_test.dart -d macos
xvfb-run -a flutter test integration_test/desktop_cli_peer_smoke_test.dart -d linux
```

### Step 5：更新 gate 和文档

PR quick gate 保持轻量：

```bash
flutter pub get
dart analyze
flutter test
```

Desktop smoke 可作为 manual / nightly / release gate：

```bash
flutter test integration_test/desktop_cli_peer_smoke_test.dart -d macos
xvfb-run -a flutter test integration_test/desktop_cli_peer_smoke_test.dart -d linux
```

真实后端 + OTP + CLI peer 的 full E2E 不应第一时间进入 PR required gate。

## 9. 验收标准

- [ ] 当前分支已合并 `feature/release-0526/agent-im-hutong`，或确认该分支已经是当前分支祖先。
- [ ] 合并后的单元测试、系统测试、E2EE 测试框架没有被重写。
- [ ] macOS Desktop 测试路径继续可用。
- [ ] Linux Desktop runner 可用。
- [ ] Linux 下 `awiki_im_core` native SDK 可 build、bundle、load。
- [ ] 同一个 `desktop_cli_peer_smoke_test.dart` 能按 macOS 和 Linux 两套命令运行。
- [ ] 只新增或调整一个最基础 Desktop E2E smoke，不扩展大量新用例。
- [ ] CLI peer 使用独立 workspace。
- [ ] `.env`、OTP、JWT、私钥、CLI workspace、本地 App state、`.e2e/` 报告不进入 git。
- [ ] 日志和报告脱敏。
- [ ] PR quick gate 和 Desktop full E2E gate 分层清楚。

## 10. 风险和阻塞点

| 风险 / 阻塞点 | 影响 | 处理方式 |
|---|---|---|
| `feature/release-0526/agent-im-hutong` 与当前分支已经相同 | merge no-op | 记录证据后直接执行 Linux 补齐步骤 |
| Linux 无 `linux/` runner | 不能 `-d linux` | 生成 Linux runner，只保留 Linux diff |
| `awiki_im_core` 不支持 Linux native loader | App Linux 真实 SDK 无法启动 | 补 Linux `.so` build / bundle / loader |
| 测试 OTP 不能支持两个身份 | App + CLI peer 双身份无法稳定准备 | 使用账号池或固定 App / CLI 两个测试账号 |
| 后端服务不稳定 | full E2E flake | full E2E 放 manual / nightly / release，不进普通 PR required gate |
| 日志泄露 secret | 安全风险 | runner 统一 redaction，report 不包含凭据和 identity 文件 |

## 11. 后续可扩展但本阶段不做

- 多业务流程 E2E：注册 handle、进入 Inbox、设置页、退出登录等完整用户路径。
- realtime WebSocket 稳定性测试。
- 系统通知和系统菜单测试。
- 文件选择器 / 附件 E2E。
- 多设备 UI-to-UI Desktop E2E。
- Linux CI required gate。
- 更细的 E2EE UI 层断言。

## 12. Codex 执行提示词

```text
请按 `test-awiki-me/docs/e2e/desktop-cli-peer-macos-linux-plan.md` 执行实现。

开始前先读取：
- `test-awiki-me/AGENTS.md`
- `test-awiki-me/docs/e2e/desktop-cli-peer-macos-linux-plan.md`
- 当前分支的 `git status --short --branch`
- `feature/release-0526/agent-im-hutong` 上已有测试框架、E2E runner、docs/testing.md 和 CI 配置
- `awiki-cli-rs2` 中 `awiki_im_core`、`im-core-dart`、CLI peer 相关文档和代码

执行要求：
1. 先检查 `feature/release-0526/agent-im-hutong` 是否已经是当前分支祖先；如果不是，合并该分支；如果是 no-op，记录证据。
2. 不要重写已有测试框架，复用该分支已有的单元测试、系统测试、E2EE 测试、Desktop runner、CLI peer 编排和 secret redaction。
3. 只补齐 Linux Desktop 运行目标：Linux runner、Ubuntu/Xvfb 环境、`awiki_im_core` Linux native build / bundle / loader。
4. 只新增或调整一个最基础 Desktop E2E smoke：App + CLI peer 双向消息闭环，测试用例同时支持 macOS 和 Linux。
5. macOS 命令为 `flutter test integration_test/desktop_cli_peer_smoke_test.dart -d macos`；Linux headless 命令为 `xvfb-run -a flutter test integration_test/desktop_cli_peer_smoke_test.dart -d linux`。
6. 不要把真实后端 + OTP + CLI peer full E2E 放进普通 PR required gate；先放 manual / nightly / release gate。
7. 不提交 `.env`、OTP、JWT、私钥、CLI workspace、本地 App state、`.e2e/` 报告；所有日志和报告必须脱敏。
8. 每个步骤完成后运行对应验证，做 Review，修复或记录发现，再创建聚焦 commit。
```

## 13. 参考资料

- Flutter Linux setup：<https://docs.flutter.dev/platform-integration/linux/setup>
- Flutter desktop support：<https://docs.flutter.dev/platform-integration/desktop>
- Flutter integration tests：<https://docs.flutter.dev/testing/integration-tests>
