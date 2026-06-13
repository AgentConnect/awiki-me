# Step 04：App + CLI peer Desktop E2E smoke

主 Plan：[../plan.md](../plan.md)  
Step index：04  
状态：draft

## 1. 执行状态

| 字段 | 值 |
|---|---|
| Status | pending |
| Branch | `feature/test-awiki-me` |
| Started | - |
| Completed | - |
| Commit | - |
| Review evidence | - |
| Verification evidence | - |
| Next action | 在 Step 01-03 完成后，实现真实 App + CLI peer 双向消息 Desktop smoke |

状态取值：`pending`、`in_progress`、`review`、`blocked`、`committed`、`done`。

## 2. 目标

- 结果：新增或调整一个 Desktop integration test，验证 Flutter App A 与 CLI peer B 的真实双向消息闭环，并同时支持 macOS 和 Linux。
- 用户 / 系统可见行为：macOS 可直接启动 App；Linux headless 通过 `xvfb-run` 启动 App。App 登录真实测试账号，App 发给 CLI 的消息可被 CLI 读到，CLI 发给 App 的消息可被 App 看到。
- 非目标：不测试系统原生文件选择器、系统通知弹窗、真实窗口拖拽、系统菜单、多显示器行为；第一版不要求 realtime listener 必然在线。
- 完成标准：一次 E2E run 生成唯一 run id，macOS / Linux 使用同一个 `desktop_cli_peer_smoke_test.dart`，双向消息都被确认，失败时有脱敏证据。

## 3. 设计方法

- 设计边界：App 侧使用真实 `AppBootstrap.create()`、真实 Dart SDK 和平台 native SDK；CLI 侧使用 public command surface。
- 核心决策：首版用 polling / inbox / history 验证，不依赖 WebSocket realtime；等消息闭环稳定后再扩展 realtime gate。
- 契约 / API / 数据流：App 不直接拼 message-service wire payload；所有消息能力通过 App application services / SDK adapter。CLI 不直接读写内部 DB。
- 兼容性：保留 `integration_test/app_smoke_test.dart` 作为 fast smoke；真实 Desktop smoke 单独文件，避免后端 flake 影响 fast smoke。
- 迁移策略：无用户数据迁移；E2E state 用独立目录，每次可清理。
- 风险控制：所有 selector 使用 `AWIKI_E2E=true` 下的 semantics identifier 或稳定 widget key；消息内容包含 run id，避免误读历史消息。

## 4. 实现方法

1. 设计测试输入：

   - `AWIKI_E2E=true`；
   - `AWIKI_SERVICE_BASE_URL` / `AWIKI_BASE_URL`；
   - `AWIKI_DID_DOMAIN`；
   - `AWIKI_E2E_APP_HANDLE`；
   - `AWIKI_E2E_CLI_HANDLE`；
   - `AWIKI_E2E_RUN_ID`；
   - `AWIKI_E2E_PLATFORM=macos|linux` 或等价 runner 配置；
   - CLI peer workspace / binary path 由 Step 03 runner 管理。

2. App A 登录 / 注册 / 恢复策略：

   - 首选驱动 onboarding UI：输入 `DEV_OTP_PHONE`、发送 OTP、输入 `DEV_OTP_CODE`、输入 / 确认 handle、完成登录；
   - 如果 OTP 或账号状态导致 UI 登录不稳定，再增加测试专用身份预置入口，但必须仍通过 SDK / App service 建立真实 session，不能绕过业务服务直接塞 UI fake session；
   - App 测试状态必须隔离，必要时给 `AwikiImCorePathLayout` 增加测试 path override。

3. CLI B 准备：

   - 由 Step 03 runner 在启动 Flutter test 前完成；
   - runner 把 CLI peer handle、run id、服务地址通过 `--dart-define` 或临时脱敏 config 传给 Flutter test。

4. App A -> CLI B：

   - App 打开会话或通过 UI 新建对话，收件人是 `AWIKI_E2E_CLI_HANDLE`；
   - App 发送 `e2e app to cli <run-id>`；
   - runner 或 integration test 子进程轮询：

     ```bash
     awiki-cli msg history --with "$AWIKI_E2E_APP_HANDLE" --limit 20 --format json
     ```

   - 直到 JSON 中出现唯一消息内容或超时。

5. CLI B -> App A：

   ```bash
   awiki-cli msg send --to "$AWIKI_E2E_APP_HANDLE" --text "e2e cli to app <run-id>" --format json
   ```

   - App UI 执行刷新 / 打开 inbox / 打开会话；
   - integration test 等待消息文本或 `e2eMessageIdentifier` 对应 semantics；
   - 如果 UI 当前没有稳定刷新入口，需要补一个用户可见刷新动作或测试等待机制。

6. 失败证据：

   - 保存脱敏 command exit code、stdout/stderr 摘要、App failure screenshot 或 Flutter test failure；
   - 不保存 OTP、JWT、私钥、完整 CLI identity files。

## 5. 路径

本节所有路径都相对 AWiki workspace 根目录。

| 仓库 / 模块 / 文件 | 计划变更 | 备注 |
|---|---|---|
| `test-awiki-me/integration_test/desktop_cli_peer_smoke_test.dart` | 新增或调整真实 App+CLI peer Desktop smoke | 后端依赖测试，不进 quick PR gate；同一文件支持 macOS / Linux |
| `test-awiki-me/lib/src/app/e2e_semantics.dart` | 可能扩展 message identifier helper | 只做测试选择器，不改变生产 UI 语义 |
| `test-awiki-me/lib/src/presentation/onboarding/` | 可能补稳定 selector | 已有 phone / otp / handle selectors |
| `test-awiki-me/lib/src/presentation/chat/` | 可能补收件人、消息、刷新 selector | 保持用户可见行为不变 |
| `test-awiki-me/tool/desktop_cli_peer_e2e_runner.dart` | 调用 Flutter test、管理 CLI subprocess | 来自 Step 03，负责 macOS / Linux platform 差异 |
| `test-awiki-me/test/tool/` | 扩展 E2E command dry-run tests | 不依赖真实服务 |

## 6. 依赖

- 前置步骤：Step 01 Linux runner、Step 02 Linux native SDK、Step 03 CLI peer 编排。macOS 运行可先复用已有 Desktop/native 能力；Linux 运行依赖 Step 01-02。
- 外部文档或决策：测试账号策略、服务地址、message-service legacy/v2 路由选择。
- 环境前提：Ubuntu deps、Xvfb、可访问非生产后端、CLI binary、两个可用测试身份。

## 7. 验收标准

- [ ] E2E test 使用真实 `AppBootstrap.create()`，不是 fake bootstrap。
- [ ] 同一个 `integration_test/desktop_cli_peer_smoke_test.dart` 支持 `-d macos` 和 `-d linux`。
- [ ] App A 登录 / 注册 / 恢复真实测试账号成功。
- [ ] CLI B 在隔离 workspace 中 ready。
- [ ] App A -> CLI B 消息被 CLI `msg history` 或 `msg inbox` 观察到。
- [ ] CLI B -> App A 消息被 App UI 或 SDK-backed conversation 观察到。
- [ ] 消息内容包含唯一 run id，断言不会误读历史消息。
- [ ] 超时、失败、重试策略明确，日志脱敏。
- [ ] `integration_test/app_smoke_test.dart` 仍然可作为 fast smoke 单独运行。
- [ ] Review 发现已经修复或明确记录。
- [ ] 本步骤在进入下一步之前已经创建聚焦 commit。

## 8. 验证方式

| 检查项 | 命令 / 方法 | 预期证据 |
|---|---|---|
| App quick tests | `cd test-awiki-me && flutter test` | unit / widget 不回归 |
| Runner dry-run | `cd test-awiki-me && dart run tool/desktop_cli_peer_e2e_runner.dart --platform linux --dry-run ...` | 打印将执行命令，不泄露 secret |
| Linux smoke | `cd test-awiki-me && xvfb-run -a flutter test integration_test/app_smoke_test.dart -d linux` | fast desktop smoke 通过 |
| Linux native smoke | `cd test-awiki-me && xvfb-run -a flutter test integration_test/im_core_open_smoke_test.dart -d linux` | SDK open smoke 通过 |
| macOS Desktop smoke | `cd test-awiki-me && flutter test integration_test/desktop_cli_peer_smoke_test.dart -d macos` | App->CLI 与 CLI->App 都通过，或在非 macOS host 明确记录未运行 |
| Linux Desktop smoke | `cd test-awiki-me && xvfb-run -a flutter test integration_test/desktop_cli_peer_smoke_test.dart -d linux` | App->CLI 与 CLI->App 都通过 |
| Full runner E2E | `cd test-awiki-me && dart run tool/desktop_cli_peer_e2e_runner.dart --platform linux ...` | runner 编排 App+CLI peer 双向消息通过 |
| Diff hygiene | `cd test-awiki-me && git diff --check` | 无 whitespace / patch 格式问题 |

如果 Desktop smoke 因后端或账号环境无法运行，必须记录：服务地址、失败命令类别、退出码、脱敏错误、已通过的 lower-level checks，以及为什么不能判定完整 E2E 已完成。

## 9. Review 环节

- Review 时机：Desktop smoke 或明确 blocked evidence 完成后，commit 前。
- Review 重点：测试是否真实走 SDK、selector 是否稳定、polling 是否有上限、失败证据是否脱敏、是否意外依赖历史消息、是否污染本地状态。

| Review 项 | 结果 | 备注 |
|---|---|---|
| 发现问题 | 执行时填写 | - |
| 已修复问题 | 执行时填写 | - |
| 剩余风险 | 执行时填写 | 例如后端 flake 或账号池不足 |
| 新增或缺失测试 | 执行时填写 | Desktop App+CLI peer smoke 是本步骤核心 |
| 已更新或缺失文档 | 执行时填写 | Step 05 汇总 gate 文档 |

## 10. Commit 要求

- Commit 时机：E2E test、runner integration、验证、Review 都完成后。
- Commit 范围：`test-awiki-me/integration_test/`、必要 App selectors、runner updates、tests。
- Commit 前状态：记录 `git status --short --branch`。
- 纳入文件：记录本步骤 commit 包含的文件。
- Commit 后证据：记录 commit hash 和 commit 后 `git status --short --branch`。
- 遗留未提交变更：必须记录原因以及为什么安全。
- 建议消息：`test: add desktop app cli peer smoke`

## 11. Blocked 处理

| Blocker | 证据 | 已尝试方案 | 影响范围 | 下一步决策 |
|---|---|---|---|---|
| App 侧无法稳定登录测试账号 | onboarding 卡住或账号错误 | UI OTP、recover、测试 path isolation | 当前步骤 | 补测试账号池或测试专用真实 SDK bootstrap |
| App 收不到 CLI 消息 | CLI send 成功但 App UI 无消息 | 检查 App refresh、SDK history、service route | 当前步骤 / 消息链路 | 先用 SDK-backed assertion 缩小问题，再决定是否补 UI selector |
| CLI 收不到 App 消息 | App send 成功但 CLI history 无消息 | 检查 target handle、DID domain、message-service route | 当前步骤 / 服务配置 | 统一 App / CLI config，记录服务证据 |
| E2E 过慢或 flake | 多次 timeout | 增加 run id、poll interval、诊断输出 | CI gate | 保持 nightly/manual，不进入 PR required gate |

## 12. Plan 变更记录

| 日期 | 变更 | 原因 | 主 Plan 变更记录链接 |
|---|---|---|---|
| 2026-06-13 | 创建 Step 04 | 初始方案拆分 | [../plan.md#20-plan-变更记录](../plan.md#20-plan-变更记录) |

## 13. 风险、回滚与后续文档

- 风险：真实后端、账号状态、消息服务路线都会影响稳定性；这类测试不适合作为普通 PR quick required gate。
- 回滚 / 回退：保留 Step 01 app smoke 和 Step 02 native smoke，移除 Desktop App+CLI peer smoke 或标记 skip，避免阻塞基础 CI。
- 后续文档：Step 05 写明 local、nightly、manual 的运行方式和跳过条件。
