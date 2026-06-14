# Step 05：Desktop App + CLI peer 真实 E2E

主 Plan：[../plan.md](../plan.md)
Step index：05
状态：done

## 1. 执行状态

| 字段 | 值 |
|---|---|
| Status | done |
| Branch | `feature/test-awiki-me` |
| Started | 2026-06-14 13:35 CST |
| Completed | 2026-06-14 13:47 CST |
| Commit | `5c1c268` |
| Review evidence | Review 完成：新增断言只通过 App `MessagingService` / `ConversationService` 和 CLI `msg history` / `msg inbox` / `msg send` 高层命令，不直接访问 message-service raw RPC、WebSocket、SQLite 或测试 fixture；`runId + nonce` 避免调试重跑误命中历史。 |
| Verification evidence | `dart analyze` 通过；`flutter test tests/unit_test/e2e_harness/desktop_cli_peer_e2e_runner_test.dart` 通过，11 tests；`xvfb-run -a flutter test integration_test/desktop_cli_peer_smoke_test.dart -d linux` 在 `AWIKI_E2E` 未开启时安全 skip；`git diff --check` 通过；敏感信息扫描仅命中 env 变量名、测试用假 secret 字符串和会被 redactor 脱敏的 runner 字段，无真实 secret。 |
| Next action | 启动 Step 06：群组与附件基础回归 E2E |

状态取值：`pending`、`in_progress`、`review`、`blocked`、`committed`、`done`。

## 2. 目标

- 结果：建立 AWiki Me 桌面端最核心的真实 E2E 回归：App 和 CLI peer 使用真实账号、真实服务、真实 SDK/native，完成双向 direct message。
- 用户 / 系统可见行为：新增功能不会破坏登录/恢复、会话、发送、接收、history/inbox 等核心消息路径。
- 非目标：不在第一版要求两台真实桌面 App，不验证所有协议细节，不把真实 E2E 放入普通 PR required gate。
- 完成标准：`desktop_cli_peer_smoke_test.dart` 或后续 scenario 能在 macOS/Linux 以 `AWIKI_E2E=true` 运行；至少验证 App->CLI 和 CLI->App 两条带唯一 runId 的消息。

## 3. 设计方法

- 设计边界：App 端走真实 `AppBootstrap.create()`、onboarding/messaging service 或稳定 UI；CLI 端走 `awiki-cli-rs2` CLI 命令。
- 核心决策：第一阶段使用 App + CLI peer 代替两台真实桌面设备，降低环境复杂度，同时覆盖端到端链路。
- 契约 / API / 数据流：App 不直接调用 message-service raw RPC；CLI 不绕过 `im-core`；测试不使用 `ModMessage` fixture 作为真实互通证据。
- 兼容性：macOS/Linux 使用同一 case；Linux 通过 `xvfb-run` 提供显示环境。
- 迁移策略：先增强现有 `desktop_cli_peer_smoke_test.dart` 的稳定性和报告，再拆分更多 regression scenario。
- 风险控制：真实 run 只在 manual/nightly/release；失败日志全部脱敏。

## 4. 实现方法

1. 准备 CLI peer：
   - 使用独立 `AWIKI_CLI_WORKSPACE_HOME_DIR` 和 `HOME`。
   - 通过 `id recover` 优先恢复稳定账号，缺失时再 `id register`。
   - `config.yaml` 指向同一套 User Service、Message Service、DID domain。
2. 准备 App identity：
   - 通过 App onboarding service 或 UI 完成 recover/register。
   - App state root 独立于开发者真实 state。
3. 验证 App -> CLI：
   - App 发送文本：包含唯一 `runId`。
   - CLI 轮询 `msg history` 或 `msg inbox`，直到看到该文本。
4. 验证 CLI -> App：
   - CLI `msg send --to <appHandle> --text <runIdText>`。
   - App 通过 `MessagingService.loadHistory` 或稳定 UI 看到该文本。
5. 增加回归断言：
   - 消息不重复。
   - history 排序合理。
   - 失败时报告最近 CLI stdout/stderr 的脱敏摘要。
6. 输出报告：
   - timings。
   - env summary。
   - App handle/CLI handle 的脱敏显示。
   - pass/fail/skipped 和失败原因。

### 4.1 本步骤实现记录

- 扩展 `integration_test/desktop_cli_peer_smoke_test.dart`，真实运行时每次使用 `runId + nonce` 生成双向 direct message 文本，避免同一 `runId` 调试重跑时误命中旧历史。
- App -> CLI 路径新增 App 侧 history 确认和 CLI `msg inbox` 确认，保留 CLI `msg history --with <appHandle>` 作为 peer 侧 history 证据。
- CLI -> App 路径新增 App history 去重检查：同一轮 App->CLI 和 CLI->App 文本在连续两次 `MessagingService.loadHistory` 刷新中都必须各出现一次。
- 新增 App `ConversationService.listConversations` 刷新断言，验证 CLI->App 后会话列表预览能看到最新 run 文本。
- 扩展 `tool/desktop_cli_peer_e2e_runner.dart` 的 `timings.json`，记录 `scenario`、case IDs、`dryRun`、`prepareOnly`、service URL 分离、App/CLI handles 和脱敏 state 字段。
- 扩展 `tests/unit_test/e2e_harness/desktop_cli_peer_e2e_runner_test.dart`，覆盖 Linux dry-run 的 `AWIKI_E2E` dart-define、App/CLI state dart-defines、服务 URL 分离、case IDs 和 report 脱敏。

## 5. 路径

| 仓库 / 模块 / 文件 | 计划变更 | 备注 |
|---|---|---|
| `test-awiki-me/integration_test/desktop_cli_peer_smoke_test.dart` | 后续增强真实 App+CLI peer smoke | 默认 `AWIKI_E2E` 未开启时 skip |
| `test-awiki-me/tool/desktop_cli_peer_e2e_runner.dart` | 后续统一准备 CLI/App state/report | 手动/nightly 入口 |
| `test-awiki-me/tests/e2e_test/harness/` | 如拆分 scenario，放共用 harness | 跨 macOS/Linux |
| `awiki-cli-rs2/target/release/awiki-cli` | 运行时依赖 | 不提交产物 |
| `test-awiki-me/.e2e/desktop-cli-peer/` | 运行时状态和报告 | 不提交 |

## 6. 依赖

- 前置步骤：Step 03、Step 04。
- 外部文档或决策：非生产测试账号、User Service URL、Message Service URL、DID domain、CLI binary。
- 环境前提：macOS 或 Linux Desktop runner；Linux 需要 Xvfb；后端可达。

## 7. 验收标准

- [x] 未设置 `AWIKI_E2E=true` 时测试安全 skip，不误失败。
- [x] 真实运行时 App->CLI 消息被 CLI 确认的路径已实现；当前 host 未提供真实后端/OTP/CLI binary，未运行 real E2E。
- [x] 真实运行时 CLI->App 消息被 App 确认的路径已实现；当前 host 未提供真实后端/OTP/CLI binary，未运行 real E2E。
- [x] 每条消息包含唯一 runId 和 nonce，避免误命中历史数据。
- [x] 失败报告脱敏，不泄漏 OTP/JWT/private key/local state。
- [x] Review 发现已经修复或明确记录。
- [x] 本步骤在进入下一步之前已经创建聚焦 commit。

## 8. 验证方式

| 检查项 | 命令 / 方法 | 预期证据 |
|---|---|---|
| Skip check | `cd test-awiki-me && xvfb-run -a flutter test integration_test/desktop_cli_peer_smoke_test.dart -d linux` | 未设置 `AWIKI_E2E=true` 时安全 skip。 |
| Linux real E2E | `cd test-awiki-me && AWIKI_E2E=true DEV_OTP_PHONE="$DEV_OTP_PHONE" DEV_OTP_CODE="$DEV_OTP_CODE" AWIKI_CLI_BIN="$AWIKI_CLI_BIN" AWIKI_USER_SERVICE_URL="$AWIKI_USER_SERVICE_URL" AWIKI_MESSAGE_SERVICE_URL="$AWIKI_MESSAGE_SERVICE_URL" xvfb-run -a flutter test integration_test/desktop_cli_peer_smoke_test.dart -d linux` | App/CLI 双向消息通过，输出脱敏证据。 |
| Runner real E2E | `cd test-awiki-me && dart run tool/desktop_cli_peer_e2e_runner.dart --platform linux --service-base-url "$AWIKI_SERVICE_BASE_URL" --did-domain "$AWIKI_DID_DOMAIN"` | runner 准备账号、workspace、report，并触发 smoke。 |
| macOS real E2E | `cd test-awiki-me && AWIKI_E2E=true flutter test integration_test/desktop_cli_peer_smoke_test.dart -d macos` | macOS 双向消息通过或记录 host 不支持。 |
| Unit | `cd test-awiki-me && flutter test tests/unit_test/e2e_harness` | runner parser/redaction tests 通过。 |

## 9. Review 环节

- Review 时机：真实 E2E 实现或增强完成后、commit 前。
- Review 重点：是否是真实闭环，是否绕过 App/CLI/SDK 边界，是否有确定性等待，是否处理账号已存在/未注册，是否脱敏，是否污染本机 state。
- Review 结论必须在 commit 前记录。

| Review 项 | 结果 | 备注 |
|---|---|---|
| 发现问题 | 初版只用 `runId` 作为消息文本，调试重跑时可能误命中历史旧消息；报告缺少 case IDs 和 state 字段，nightly 证据不好回溯。 | 已修复为 `runId + nonce`，并扩展 `timings.json`。 |
| 已修复问题 | 已修复 | 新增 CLI inbox、App history 去重、App conversation refresh 断言；新增 runner report 字段和单测。 |
| 剩余风险 | real E2E 未在当前 host 运行 | 当前环境未注入真实后端、OTP 和可用 `AWIKI_CLI_BIN`；真实通过仍需 manual/nightly/release 环境验证。macOS real run 未在当前 Linux host 运行。 |
| 新增或缺失测试 | 已新增非真实 gate 覆盖 | runner dry-run 单测覆盖 report/dart-defines/redaction；Linux safe-skip 覆盖默认跳过。真实 App/CLI 双向消息只完成实现路径，未获得 real backend 证据。 |
| 已更新或缺失文档 | 已更新 | 主 Plan 和本 Step 已记录实现、验证、Review 状态。 |

## 10. Commit 要求

- Commit 时机：实现、验证、Review 都完成后。
- Commit 范围：只包含 Desktop App+CLI peer E2E 和直接相关 harness/docs。
- Commit 前状态：记录 `git status --short --branch`。
- 纳入文件：记录本步骤 commit 包含的文件。
- Commit 后证据：记录 commit hash 和 commit 后 `git status`。
- 建议消息：`test: extend desktop app cli peer e2e`
- Commit 前状态：`git status --short --branch` 显示本步骤相关测试/runner/docs 修改，另有无关未跟踪旧草稿目录 `docs/e2e/desktop-cli-peer-macos-linux-execution/`。
- 纳入文件：`docs/e2e/awiki-me-e2e-regression-plan/plan.md`、本文件、`integration_test/desktop_cli_peer_smoke_test.dart`、`tool/desktop_cli_peer_e2e_runner.dart`、`tests/unit_test/e2e_harness/desktop_cli_peer_e2e_runner_test.dart`。
- Commit 后证据：提交后回填 commit hash 和 post-commit status。

## 11. Blocked 处理

| Blocker | 证据 | 已尝试方案 | 影响范围 | 下一步决策 |
|---|---|---|---|---|
| 后端不可达 | HTTP/CLI/App 错误 | dry-run、service health、检查 URL 分离 | 真实 E2E | 标 blocked，不进入 PR required |
| 账号恢复/注册失败 | 脱敏 CLI/App 错误 | 检查 env、账号池、OTP 限制 | 当前步骤 | 请求账号或改用稳定账号 |
| CLI 缺少命令能力 | CLI help/test 证据 | 回到 `awiki-cli-rs2` 补最小命令或使用现有命令组合 | 当前步骤 | 更新 Plan 影响范围 |

## 12. Plan 变更记录

| 日期 | 变更 | 原因 | 主 Plan 变更记录链接 |
|---|---|---|---|
| 待记录 | 待记录 | 待记录 | [../plan.md#17-plan-变更记录](../plan.md#17-plan-变更记录) |

## 13. 风险、回滚与后续文档

- 风险：真实后端或 OTP 波动导致 nightly 不稳定。
- 回滚 / 回退：保留 skip/dry-run，真实 case 回退为 manual，直到账号和服务稳定。
- 后续文档：Step 08 将本场景纳入 nightly/release gate。
