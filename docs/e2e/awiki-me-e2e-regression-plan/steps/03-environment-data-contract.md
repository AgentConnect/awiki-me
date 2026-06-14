# Step 03：测试环境、账号和数据隔离契约

主 Plan：[../plan.md](../plan.md)
Step index：03
状态：done

## 1. 执行状态

| 字段 | 值 |
|---|---|
| Status | done |
| Branch | `feature/test-awiki-me` |
| Started | 2026-06-14 13:06 CST |
| Completed | 2026-06-14 13:09 CST |
| Commit | `a2defaa` |
| Review evidence | Review 完成：环境契约与 `desktop_e2e_runner.dart`、`mobile_e2e_runner.dart`、`desktop_cli_peer_e2e_runner.dart`、example config 和 `.gitignore` 一致；未引入真实 secret。 |
| Verification evidence | `dart run tests/e2e_test/harness/mobile_e2e_runner.dart --config tests/e2e_test/configs/mobile.example.yaml --dry-run` 通过；`dart run tests/e2e_test/harness/desktop_e2e_runner.dart --platform=linux --dry-run --skip-cli-build --skip-flutter-smoke` 通过；`git diff --check -- docs/e2e/awiki-me-e2e-regression-plan` 通过；敏感信息/绝对路径扫描仅命中 Step 05 env 变量名示例，无真实 secret；`.e2e/` 为 ignored 运行产物。 |
| Next action | 启动 Step 04：Desktop 确定性 smoke 与回归基线 |

状态取值：`pending`、`in_progress`、`review`、`blocked`、`committed`、`done`。

## 2. 目标

- 结果：建立真实 E2E 可重复运行所需的环境、账号、服务 URL、CLI workspace、App state、report 和 secret handling 契约。
- 用户 / 系统可见行为：后续真实 E2E 可以在 Linux、macOS、mobile 环境复用配置，不污染开发者账号和本机状态。
- 非目标：不提交真实账号、OTP、JWT、私钥、本地 `.env` 或 local config。
- 完成标准：所有真实 E2E 依赖都通过 env 或 ignored local config 注入；报告路径、workspace、HOME、App state root 均按 runId 隔离。

## 3. 设计方法

- 设计边界：配置契约和隔离规则归 `test-awiki-me` E2E harness；服务真实行为归 `user-service`、`message-service`、`awiki-system-test`。
- 核心决策：example config 只提交占位和 env 名；真实 config 使用 ignored `.local.yaml` 或 CI secret 注入。
- 契约 / API / 数据流：App 和 CLI peer 必须使用同一套 `AWIKI_USER_SERVICE_URL`、`AWIKI_MESSAGE_SERVICE_URL`、`AWIKI_DID_DOMAIN` 或对应 config。
- 兼容性：Linux headless 通过 `xvfb-run`；macOS 直接用 `flutter test -d macos`；mobile 使用 Maestro 和两设备配置。
- 迁移策略：先复用现有 `mobile.example.yaml`、`tool/desktop_cli_peer_e2e_runner.dart`，后续为群组和附件补 example config。
- 风险控制：强制 redaction scan，禁止报告输出 OTP 值、JWT、私钥和本机绝对路径。

## 4. 实现方法

1. 定义桌面通用 env：
   - `AWIKI_SERVICE_BASE_URL`
   - `AWIKI_USER_SERVICE_URL`
   - `AWIKI_MESSAGE_SERVICE_URL`
   - `AWIKI_MESSAGE_SERVICE_WS_URL`
   - `AWIKI_DID_DOMAIN`
   - `AWIKI_CLI_BIN`
   - `DEV_OTP_PHONE`
   - `DEV_OTP_CODE`
2. 定义 Linux 专属前提：
   - Flutter Linux desktop enabled。
   - `xvfb-run`、GTK、CMake、Ninja、pkg-config 等依赖。
   - `AWIKI_SQLITE3_SOURCE_DIR` 可选预置，避免 Linux native build 依赖下载波动。
3. 定义 macOS 专属前提：
   - Xcode command line tools。
   - `flutter test -d macos` 可运行。
4. 定义 mobile 专属前提：
   - iOS/Android 两设备或两模拟器。
   - Maestro 可用。
   - `mobile.local.yaml` 不提交。
5. 定义账号池：
   - App 用户和 peer 用户分开。
   - 每个真实 run 使用唯一 runId 写入消息文本。
   - 默认复用稳定非生产账号，只有必要时才重注册。
6. 定义本地状态：
   - CLI workspace：`.e2e/<scenario>/<runId>/cli-peer`。
   - CLI HOME：`.e2e/<scenario>/<runId>/cli-home`。
   - App state：`.e2e/<scenario>/<runId>/app`。
   - Reports：`.e2e/<scenario>/<runId>/reports`。

### 4.1 Shared service env 契约

| Env / 字段 | 用途 | 来源 | 提交规则 |
|---|---|---|---|
| `AWIKI_SERVICE_BASE_URL` / `AWIKI_BASE_URL` | App、CLI 和 harness 的默认服务域名。 | CI secret、本地 shell 或 runner 参数。 | 只记录 env 名；真实值不写入文档。 |
| `AWIKI_USER_SERVICE_URL` | User Service endpoint，可与 message service 分离。 | CI secret、本地 shell、`mobile.local.yaml`。 | 可在 example 中用公开非生产默认域；真实 local config 不提交。 |
| `AWIKI_MESSAGE_SERVICE_URL` | Message Service v2 endpoint。 | CI secret、本地 shell、`mobile.local.yaml`。 | 必须可独立覆盖，避免误连 legacy 服务。 |
| `AWIKI_MESSAGE_SERVICE_WS_URL` | WebSocket endpoint，Agent/未来场景可能需要。 | ignored local config 或 CI secret。 | 只记录字段名和默认形态。 |
| `AWIKI_DID_DOMAIN` | DID-WBA domain。 | env、runner 参数或 config。 | 不含 secret，可记录域名；真实环境仍由 env/config 控制。 |
| `AWIKI_ANP_SERVICE_URL` / `AWIKI_ANP_SERVICE_DID` | ANP service override。 | env、runner 参数或 config。 | 可选字段；缺省时由 base URL / DID domain 推导。 |
| `PUB_HOSTED_URL` | Flutter pub mirror。 | 本地 shell 或 CI。 | 推荐 Tsinghua mirror；不含 secret。 |

### 4.2 Desktop 契约

| 分类 | macOS | Linux |
|---|---|---|
| Flutter device | `macos` | `linux` |
| Runner wrapper | 直接运行 `flutter test -d macos` | 使用 `xvfb-run -a flutter test -d linux` |
| Tooling 前提 | Xcode command line tools、Flutter desktop enabled、Cargo/CLI repo | `clang`、`cmake`、`ninja`、`pkg-config`、GTK desktop deps、`xvfb-run`、Flutter Linux desktop enabled、Cargo/CLI repo |
| Native SDK 前提 | 可加载本地 native library | 可选预置 `AWIKI_SQLITE3_SOURCE_DIR`，降低 native build 下载波动 |
| Env 前缀 | `AWIKI_MACOS_E2E_*` 覆盖通用 desktop env | `AWIKI_LINUX_E2E_*` 覆盖通用 desktop env |

通用 desktop harness 已支持：

- `AWIKI_DESKTOP_E2E_FLUTTER`：Flutter 可执行文件路径。
- `AWIKI_DESKTOP_E2E_CLI_REPO`：`awiki-cli-rs2` 仓库路径，默认 `../awiki-cli-rs2`。
- `AWIKI_DESKTOP_E2E_BASE_URL`：服务 base URL。
- `AWIKI_DESKTOP_E2E_DID_DOMAIN`：DID domain。
- `AWIKI_MACOS_E2E_*` / `AWIKI_LINUX_E2E_*`：按平台覆盖同名 suffix。

Desktop App + CLI peer runner 使用：

- `DEV_OTP_PHONE`、`DEV_OTP_CODE`：本地非生产 OTP 凭证，只从 env 读，不写文档真实值。
- `AWIKI_E2E_APP_HANDLE`、`AWIKI_E2E_CLI_HANDLE`：两个不同 handle。
- `AWIKI_CLI_BIN`：已有 CLI binary；未设置时 runner 可构建 `awiki-cli`。
- `AWIKI_CLI_WORKSPACE_HOME_DIR`、`AWIKI_CLI_HOME_DIR`、`AWIKI_E2E_APP_STATE_ROOT`：由 runner 按 runId 注入给 Flutter test。

### 4.3 Mobile 契约

| 字段 | 要求 |
|---|---|
| `platform` | `ios` 或 `android`；桌面不走 mobile runner。 |
| `service.*` | `baseUrl`、`userServiceUrl`、`messageServiceUrl`、`didDomain` 必填；`anpServiceUrl` / `anpServiceDid` 可选。 |
| `device.resetBeforeRun` | nightly/release 默认为 true；本地排障复用登录态时才允许 false。 |
| `device.ios` | 两个独立 simulator 名称或 UDID；A/B 不能相同。 |
| `device.android` | 两个独立 AVD 名称或 device serial；不能使用同一个 AVD 的只读多开状态。 |
| `accounts.a` / `accounts.b` | 两个不同 handle 的非生产账号；真实手机号写入 ignored local config 或 CI secret。 |
| `otp` / `message` | OTP 和消息等待 timeout 必须显式可调，避免通过无限等待掩盖失败。 |

`tests/e2e_test/configs/mobile.example.yaml` 只作为字段样例；真实运行复制为 `tests/e2e_test/configs/mobile.local.yaml` 或由 CI 生成。`.gitignore` 已排除 `tests/e2e_test/configs/*.local.yaml`、`*.local.yml`、`*.local.env`。

### 4.4 账号池和 runId 规则

| 角色 | 最小数量 | 用途 | 隔离要求 |
|---|---|---|---|
| Desktop App user | 1 | App 侧注册/恢复、发送/接收 direct/group/attachment。 | 与 CLI peer handle 不同；App state 放在 runId 目录。 |
| CLI peer user | 1 | 对端 direct/group/attachment 发送接收。 | CLI workspace 和 HOME 放在 runId 目录；优先复用稳定非生产账号。 |
| Mobile user A/B | 2 | 两设备互发消息。 | 两个不同 handle；设备数据 nightly 默认 reset。 |

- runId 是真实 E2E 的主关联键，必须进入消息文本、群组名或附件 fixture 标识。
- 账号准备优先 recover/refresh；只有缺失或明确需要时才 register。
- 缺少账号池或 OTP 时，真实 E2E 必须 skipped/blocker，不能用 fixture 声称通过。

### 4.5 本地状态和报告目录

| Runner | Reports | CLI workspace / HOME | App / device state |
|---|---|---|---|
| Desktop harness | `.e2e/<platform>/reports/<runId>` | `.e2e/<platform>/cli-workspaces/<runId>` | 仅 deterministic smoke，不保存真实 App state。 |
| Desktop App + CLI peer | `.e2e/desktop-cli-peer/<runId>/reports` | `.e2e/desktop-cli-peer/<runId>/cli-peer`、`.e2e/desktop-cli-peer/<runId>/cli-home` | `.e2e/desktop-cli-peer/<runId>/app` |
| Agent IM legacy scenario | `.e2e/agent-im/...` | `.e2e/agent-im/cli-peer` | 本轮 skipped，不作为基础 E2E gate。 |
| Mobile runner | `.e2e/reports/<runId>` | 不使用 CLI workspace | iOS/Android 设备按 config reset 或复用。 |

`.e2e/` 和 local config 已在 `.gitignore` 中排除；任何 report、workspace、device dump、token cache、private key 或 App local state 都不得提交。

### 4.6 Secret 和报告脱敏契约

- 允许记录：runId、case id、platform、scenario、service host、DID domain、handle、fixture 名、timing、pass/fail/skipped、脱敏后的 report 路径。
- 禁止记录或提交：OTP 值、JWT、private key、seed、DID secret、raw authorization header、CLI workspace、App local state、真实 local config、`.env`。
- 报告中的绝对本机路径只可作为本地未提交 artifact；提交文档必须使用 workspace-relative path。
- Redaction scan 必须覆盖 docs、example config、scenario report 和 command logs；命中 env 变量名不算泄漏，命中真实值必须阻断提交并轮换凭证。
- 远端日志只允许按 runId 过滤后收集，并在报告中记录脱敏摘要；不得提交原始远端日志。

## 5. 路径

| 仓库 / 模块 / 文件 | 计划变更 | 备注 |
|---|---|---|
| `test-awiki-me/tests/e2e_test/configs/` | 后续补齐 example config 或字段说明 | 只提交 example |
| `test-awiki-me/tests/e2e_test/harness/` | 后续实现 env/config parser、redaction、report | 不提交 real state |
| `test-awiki-me/tool/desktop_cli_peer_e2e_runner.dart` | 后续复用或扩展桌面 App+CLI peer runner | 保持 secret redaction |
| `test-awiki-me/.e2e/` | 运行时生成 | 不提交 |
| `user-service/.env` | 只读取本地非生产 env key | 不记录真实值 |

## 6. 依赖

- 前置步骤：Step 01、Step 02。
- 外部文档或决策：账号池、服务 URL、nightly runner。
- 环境前提：后续真实运行需要 macOS/Linux/mobile 目标环境。

## 7. 验收标准

- [x] 所有真实 E2E 配置都有 env/local config 注入方式。
- [x] example config 不包含真实 OTP、JWT、私钥、账号 secret。
- [x] App 用户、CLI peer 用户、mobile A/B 用户的状态隔离清楚。
- [x] User Service 和 Message Service URL 可分离，避免误连 legacy 服务。
- [x] Review 发现已经修复或明确记录。
- [x] 本步骤在进入下一步之前已经创建聚焦 commit。

## 8. 验证方式

| 检查项 | 命令 / 方法 | 预期证据 |
|---|---|---|
| Config dry-run | `cd test-awiki-me && dart run tests/e2e_test/harness/mobile_e2e_runner.dart --config tests/e2e_test/configs/mobile.example.yaml --dry-run` | mobile example config 可解析，不写真实状态。 |
| Desktop dry-run | `cd test-awiki-me && dart run tests/e2e_test/harness/desktop_e2e_runner.dart --platform=linux --dry-run --skip-cli-build --skip-flutter-smoke` | desktop dry-run 不依赖后端，report 脱敏。 |
| Diff | `cd test-awiki-me && git diff --check` | 无空白错误。 |
| Secret | 扫描本步骤新增 docs/config | 没有真实 secret 或本机绝对路径。 |

## 9. Review 环节

- Review 时机：环境和数据契约完成后、commit 前。
- Review 重点：secret handling、状态隔离、Linux/macOS/mobile 差异、服务 URL 分离、账号复用和 OTP 耗尽风险。
- Review 结论必须在 commit 前记录。

| Review 项 | 结果 | 备注 |
|---|---|---|
| 发现问题 | 无阻断问题 | 契约与现有 runner/config/.gitignore 对齐，未发现需要修改实现的缺口。 |
| 已修复问题 | 已补齐文档缺口 | 补充 shared service env、desktop/macOS/Linux 前提、mobile local config、账号池、runId 目录和 secret/report 脱敏规则。 |
| 剩余风险 | 真实账号池和设备池仍需外部环境提供 | Step 05/07 执行真实 E2E 时需要账号、OTP、后端和设备池；本步骤只定义契约和 dry-run 验证。 |
| 新增或缺失测试 | 未新增测试 | 本步骤为文档/契约步骤；执行了 desktop/mobile dry-run。 |
| 已更新或缺失文档 | 已更新主 Plan 和当前 Step | 后续若改变 runner 参数，应同步 `docs/testing.md` 和 `tests/e2e_test/README.md`。 |

## 10. Commit 要求

- Commit 时机：契约、example config 或文档更新完成并验证后。
- Commit 范围：只包含环境/账号/数据隔离相关文件。
- Commit 前状态：记录 `git status --short --branch`。
- 纳入文件：记录本步骤 commit 包含的文件。
- Commit 后证据：记录 commit hash 和 commit 后 `git status`。
- 建议消息：`test: define e2e environment contract`
- Commit 前状态：`git status --short --branch --ignored=matching .e2e docs/e2e/awiki-me-e2e-regression-plan` 显示两个计划文档修改，`.e2e/` 为 ignored 运行产物。
- 纳入文件：`docs/e2e/awiki-me-e2e-regression-plan/plan.md`、`docs/e2e/awiki-me-e2e-regression-plan/steps/03-environment-data-contract.md`。
- Commit 后状态：本步骤提交后用 `git status --short --branch` 复核；预期仅保留无关未跟踪旧草稿目录，`.e2e/` 仍被忽略。

## 11. Blocked 处理

| Blocker | 证据 | 已尝试方案 | 影响范围 | 下一步决策 |
|---|---|---|---|---|
| 没有稳定测试账号池 | 待记录 | 只保留 env 契约和 dry-run | 真实 E2E | 等用户提供账号或服务侧账号策略 |
| Linux 依赖不可安装 | 待记录 | 保留 macOS gate，Linux 标 optional | Linux gate | 后续 self-hosted runner 配置解决 |

## 12. Plan 变更记录

| 日期 | 变更 | 原因 | 主 Plan 变更记录链接 |
|---|---|---|---|
| 待记录 | 待记录 | 待记录 | [../plan.md#17-plan-变更记录](../plan.md#17-plan-变更记录) |

## 13. 风险、回滚与后续文档

- 风险：真实账号或服务 URL 泄漏。
- 回滚 / 回退：删除错误提交的 config/report，轮换测试凭证，修复 redaction。
- 后续文档：Step 04-07 按本契约实现具体平台场景。
