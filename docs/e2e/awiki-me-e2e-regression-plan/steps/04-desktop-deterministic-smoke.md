# Step 04：Desktop 确定性 smoke 与回归基线

主 Plan：[../plan.md](../plan.md)
Step index：04
状态：done

## 1. 执行状态

| 字段 | 值 |
|---|---|
| Status | done |
| Branch | `feature/test-awiki-me` |
| Started | 2026-06-14 13:24 CST |
| Completed | 2026-06-14 13:28 CST |
| Commit | `4edb631` |
| Review evidence | Review 完成：新增 profile/settings smoke 只使用 fake bootstrap、fake profile provider 和 fake homepage loader；未接真实后端、OTP、CLI peer 或 mobile 设备；root `integration_test/` 仍为 shim。 |
| Verification evidence | `dart analyze` 通过；`flutter test tests/unit_test/profile_page_test.dart tests/unit_test/settings_page_test.dart tests/unit_test/conversation_workspace_test.dart` 通过，41 tests；`xvfb-run -a flutter test integration_test/app_smoke_test.dart -d linux` 通过，3 tests；`xvfb-run -a flutter test integration_test/im_core_open_smoke_test.dart -d linux` 通过，1 test；当前 host 为 Linux，macOS smoke 未运行；`git diff --check` 通过；敏感扫描仅命中 env 变量名示例。 |
| Next action | 启动 Step 05：Desktop App + CLI peer 真实 E2E |

状态取值：`pending`、`in_progress`、`review`、`blocked`、`committed`、`done`。

## 2. 目标

- 结果：让 macOS/Linux Desktop 的确定性 smoke 成为稳定回归基线，验证 App shell、native SDK、profile/settings 基础页面等不依赖真实后端的关键路径。
- 用户 / 系统可见行为：新增功能 PR 可以快速发现 App 启动、runner、native SDK 打包、基础 UI 结构被破坏的问题。
- 非目标：不在本步骤运行真实账号、真实消息、真实 CLI peer 或 mobile 设备。
- 完成标准：macOS/Linux 对应 smoke 命令和 gate 条件明确；测试失败时能定位是 runner、native SDK、App bootstrap 还是 fixture 问题。

## 3. 设计方法

- 设计边界：`tests/integration_test/` 只做 Flutter engine/platform/native/plugin smoke，不承担真实多客户端 E2E。
- 核心决策：PR optional 或 self-hosted required 可以跑 desktop smoke；普通 hosted runner 没有 Linux/macos 条件时只保留 dry-run。
- 契约 / API / 数据流：App smoke 使用 fake bootstrap；native smoke 只验证 `AwikiImCore.open`；profile/settings smoke 只验证基础页面和 session 状态。
- 兼容性：根级 `integration_test/*.dart` 只做 shim，真实实现继续在 `tests/integration_test/`。
- 迁移策略：先稳定已有 `app_smoke_test.dart`、`im_core_open_smoke_test.dart`，再补 profile/settings smoke。
- 风险控制：避免把真实后端逻辑塞进 deterministic smoke。

## 4. 实现方法

1. 固化 macOS smoke：
   - `flutter test integration_test/app_smoke_test.dart -d macos`
   - `flutter test integration_test/im_core_open_smoke_test.dart -d macos`
2. 固化 Linux smoke：
   - 使用 `xvfb-run -a flutter test ... -d linux`。
   - 按需要设置 `AWIKI_SQLITE3_SOURCE_DIR`。
3. 审核 deterministic smoke 的测试内容：
   - App shell、onboarding shell、basic navigation。
   - native SDK open。
   - profile/settings 基础页面 smoke。
4. 如当前功能需要，补一个最小 profile/settings smoke，但必须保持无后端依赖。

### 4.1 本步骤实现记录

- 扩展 `tests/integration_test/app/app_smoke_test.dart`，在已有 fake bootstrap 和 authenticated shell smoke 基础上，新增 `profile/settings` 基础回归断言。
- `profile/settings` smoke 使用 fake session、fake gateway、fake profile provider 和 fake homepage loader；不访问真实 User Service、Message Service、HTTP homepage、OTP 或 CLI peer。
- 更新 `tests/integration_test/support/fake_app_bootstrap.dart`，让 integration fake bootstrap 默认注入 `homepageMarkdownLoaderProvider` 和初始 `profileProvider`，避免 deterministic smoke 被真实网络或后台 refresh 影响。
- root `integration_test/app_smoke_test.dart` 仍只是 shim，没有迁移实现逻辑。

## 5. 路径

| 仓库 / 模块 / 文件 | 计划变更 | 备注 |
|---|---|---|
| `test-awiki-me/tests/integration_test/app/` | 后续维护 App shell smoke | 无真实后端 |
| `test-awiki-me/tests/integration_test/native/` | 后续维护 native SDK smoke | macOS/Linux |
| `test-awiki-me/integration_test/` | 保留 Flutter root shim | 不放实现逻辑 |
| `test-awiki-me/docs/testing.md` | 后续同步 smoke gate 命令 | 文档 |

## 6. 依赖

- 前置步骤：Step 02、Step 03。
- 外部文档或决策：Linux runner/native SDK 环境是否在 CI 可用。
- 环境前提：macOS 需要 macOS runner；Linux 需要 desktop deps 和 Xvfb。

## 7. 验收标准

- [x] desktop smoke 明确不依赖真实后端或 OTP。
- [x] macOS/Linux 命令和跳过条件清楚。
- [x] native SDK smoke 失败能定位到 native library 或 SDK open 问题。
- [x] profile/settings smoke 不依赖真实后端或真实账号。
- [x] Review 发现已经修复或明确记录。
- [x] 本步骤在进入下一步之前已经创建聚焦 commit。

## 8. 验证方式

| 检查项 | 命令 / 方法 | 预期证据 |
|---|---|---|
| Unit | `cd test-awiki-me && flutter test tests/unit_test` | 单元和 widget 回归通过。 |
| macOS smoke | `cd test-awiki-me && flutter test integration_test/app_smoke_test.dart -d macos` | macOS App smoke 通过或记录 host 不支持。 |
| Linux App smoke | `cd test-awiki-me && AWIKI_SQLITE3_SOURCE_DIR=/tmp/awiki-sqlite3 xvfb-run -a flutter test integration_test/app_smoke_test.dart -d linux` | Linux headless App smoke 通过。 |
| Linux native smoke | `cd test-awiki-me && AWIKI_SQLITE3_SOURCE_DIR=/tmp/awiki-sqlite3 xvfb-run -a flutter test integration_test/im_core_open_smoke_test.dart -d linux` | Linux native open 通过。 |
| Diff | `cd test-awiki-me && git diff --check` | 无空白错误。 |

## 9. Review 环节

- Review 时机：desktop smoke 调整完成后、commit 前。
- Review 重点：测试是否确定性、是否误连真实后端、是否污染平台 runner、是否破坏 root shim 约束、Linux/macOS 差异是否只在 platform adapter。
- Review 结论必须在 commit 前记录。

| Review 项 | 结果 | 备注 |
|---|---|---|
| 发现问题 | 初版新增断言等待 profile 异步刷新，且 `pumpAndSettle` 在 integration smoke 中可能被后台动画/任务拖住 | 已改为 fake profile 初值和有限 `pump`，避免真实网络和无限 settle。 |
| 已修复问题 | 已修复 | `tests/integration_test/support/fake_app_bootstrap.dart` 注入 `homepageMarkdownLoaderProvider` 和初始 `profileProvider`；新增用例改用 `_pumpSmokeFrame`。 |
| 剩余风险 | macOS smoke 未在当前 host 运行 | `flutter devices` 仅发现 Linux desktop；macOS smoke 需由 macOS runner 验证。Flutter desktop smoke 不应并行跑同一 build 目录，否则可能竞争 `build/linux`。 |
| 新增或缺失测试 | 已新增 deterministic App smoke | profile/settings 基础回归进入 `integration_test/app_smoke_test.dart`。 |
| 已更新或缺失文档 | 已更新 | `docs/testing.md`、`tests/integration_test/README.md`、主 Plan 和本 Step。 |

## 10. Commit 要求

- Commit 时机：实现、验证、Review 都完成后。
- Commit 范围：只包含 desktop deterministic smoke 相关测试和文档。
- Commit 前状态：记录 `git status --short --branch`。
- 纳入文件：记录本步骤 commit 包含的文件。
- Commit 后证据：记录 commit hash 和 commit 后 `git status`。
- 建议消息：`test: stabilize desktop smoke gates`
- Commit 前状态：`git status --short --branch` 显示本步骤相关测试/文档修改，另有无关未跟踪旧草稿目录；`.e2e/` 为 ignored 运行产物。
- 纳入文件：`docs/e2e/awiki-me-e2e-regression-plan/plan.md`、本文件、`docs/testing.md`、`tests/integration_test/README.md`、`tests/integration_test/app/app_smoke_test.dart`、`tests/integration_test/support/fake_app_bootstrap.dart`。
- Commit 后状态：本步骤提交后用 `git status --short --branch` 复核；预期仅保留无关未跟踪旧草稿目录。

## 11. Blocked 处理

| Blocker | 证据 | 已尝试方案 | 影响范围 | 下一步决策 |
|---|---|---|---|---|
| 当前 host 不是 macOS | 命令无法运行 | 记录未运行原因，保留 Linux 或 dry-run 证据 | macOS smoke | 交给 macOS runner/nightly 验证 |
| Linux native library 缺失 | native smoke 失败 | 先运行 SDK build 脚本或标记 Step 03/环境 blocker | Linux smoke | 修复环境后重跑 |

## 12. Plan 变更记录

| 日期 | 变更 | 原因 | 主 Plan 变更记录链接 |
|---|---|---|---|
| 待记录 | 待记录 | 待记录 | [../plan.md#17-plan-变更记录](../plan.md#17-plan-变更记录) |

## 13. 风险、回滚与后续文档

- 风险：把 smoke 扩得太宽导致 PR gate 不稳定。
- 回滚 / 回退：回退新增不稳定 smoke，只保留 app/native 最小 smoke。
- 后续文档：Step 05 在真实 App+CLI peer E2E 中覆盖后端消息闭环。
