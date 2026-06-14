# Step 03：测试环境、账号和数据隔离契约

主 Plan：[../plan.md](../plan.md)  
Step index：03  
状态：draft

## 1. 执行状态

| 字段 | 值 |
|---|---|
| Status | pending |
| Branch | 待执行时记录 |
| Started | 待记录 |
| Completed | 待记录 |
| Commit | 待记录 |
| Review evidence | 待记录 |
| Verification evidence | 待记录 |
| Next action | 定义 macOS/Linux/mobile/backend/account/report 契约 |

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

## 5. 路径

| 仓库 / 模块 / 文件 | 计划变更 | 备注 |
|---|---|---|
| `test-awiki-me/tests/e2e_test/configs/` | 后续补齐 example config 或字段说明 | 只提交 example |
| `test-awiki-me/tests/e2e_test/harness/` | 后续实现 env/config parser、redaction、report | 不提交 real state |
| `test-awiki-me/tool/desktop_cli_peer_e2e_runner.dart` | 后续复用或扩展桌面 App+CLI peer runner | 保持 secret redaction |
| `test-awiki-me/.e2e/` | 运行时生成 | 不提交 |
| `user-service/.env` | 只读取本地非生产 env key | 不记录真实值 |

## 6. 依赖

- 前置步骤：Step 01；Step 02 可并行提供场景标签。
- 外部文档或决策：账号池、服务 URL、nightly runner。
- 环境前提：后续真实运行需要 macOS/Linux/mobile 目标环境。

## 7. 验收标准

- [ ] 所有真实 E2E 配置都有 env/local config 注入方式。
- [ ] example config 不包含真实 OTP、JWT、私钥、账号 secret。
- [ ] App 用户、CLI peer 用户、mobile A/B 用户的状态隔离清楚。
- [ ] User Service 和 Message Service URL 可分离，避免误连 legacy 服务。
- [ ] Review 发现已经修复或明确记录。
- [ ] 本步骤在进入下一步之前已经创建聚焦 commit。

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
| 发现问题 | 待记录 |  |
| 已修复问题 | 待记录 |  |
| 剩余风险 | 待记录 |  |
| 新增或缺失测试 | 待记录 |  |
| 已更新或缺失文档 | 待记录 |  |

## 10. Commit 要求

- Commit 时机：契约、example config 或文档更新完成并验证后。
- Commit 范围：只包含环境/账号/数据隔离相关文件。
- Commit 前状态：记录 `git status --short --branch`。
- 纳入文件：记录本步骤 commit 包含的文件。
- Commit 后证据：记录 commit hash 和 commit 后 `git status`。
- 建议消息：`test: define e2e environment contract`

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
