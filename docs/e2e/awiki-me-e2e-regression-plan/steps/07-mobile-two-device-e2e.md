# Step 07：Mobile 双设备 E2E

主 Plan：[../plan.md](../plan.md)  
Step index：07  
状态：done

## 1. 执行状态

| 字段 | 值 |
|---|---|
| Status | done |
| Branch | `feature/test-awiki-me` |
| Started | 2026-06-14 14:13 CST |
| Completed | 2026-06-14 14:18 CST |
| Commit | 本步骤提交后回填短 hash，以 `git log -1` 为准 |
| Review evidence | Review 完成：确认 mobile runner 的真实路径仍通过 Maestro flows 和 App UI 完成登录/发收消息，不直接访问 service raw RPC、SQLite 或内部消息数据；dry-run report 明确 `caseStatus: skipped`，不把计划通过伪装为真实两设备通过；命令日志和 report 已脱敏手机号、OTP、token/JWT query、device id 和绝对路径。 |
| Verification evidence | `dart analyze` 通过；`flutter test tests/unit_test/e2e_harness/mobile_e2e_runner_test.dart` 通过，15 tests；`dart run tests/e2e_test/harness/mobile_e2e_runner.dart --config tests/e2e_test/configs/mobile.example.yaml --dry-run` 通过，runId `20260614061538-0ef4ka`，`timings.json` 记录 `scenario: mobile-two-device`、`caseIds: [MOBILE-E2E-001]`、`caseStatus: skipped`、平台/账号/设备/消息计划和脱敏 report 路径；`git diff --check` 通过；敏感扫描仅命中 env 名、示例占位手机号、测试用假 secret 和既有 redaction 测试数据，无真实 secret。 |
| Next action | 启动 Step 08：CI/nightly/release gate 与维护机制 |

状态取值：`pending`、`in_progress`、`review`、`blocked`、`committed`、`done`。

## 2. 目标

- 结果：让移动端真实两设备 E2E 覆盖登录、发送、接收和基础聊天回归。
- 用户 / 系统可见行为：后续移动端新功能不会破坏基本账号和消息互通。
- 非目标：不把移动真实设备 E2E 放入普通 PR required gate，不要求覆盖所有平台 UI 细节。
- 完成标准：`mobile_e2e_runner.dart` 能用 `mobile.local.yaml` 驱动两台 iOS 或 Android 设备完成双向消息 smoke，并输出脱敏报告。

## 3. 设计方法

- 设计边界：移动 E2E 使用 Maestro flows 和 mobile runner；复杂协议验证仍由 SDK/system tests 覆盖。
- 核心决策：先覆盖 A 登录发送给 B、B 接收，再反向发送；后续再加 profile/settings/notification。
- 契约 / API / 数据流：两个设备使用不同账号和 handle，同一套非生产服务。
- 兼容性：iOS 和 Android 使用同一 runner/config schema，平台字段决定设备准备方式。
- 迁移策略：复用现有 `login.yaml`、`open_chat_and_send.yaml`、`open_chat_and_wait.yaml`，先稳定 P0。
- 风险控制：设备池不稳定时不阻塞 PR，只在 nightly/release 或 manual run。

## 4. 实现方法

1. 准备 `mobile.local.yaml`：
   - iOS: 两个 simulator name 或 UDID。
   - Android: 两个 AVD name 或 device serial。
   - 两个非生产账号和 handle。
2. 扩展 runner：
   - 安装/启动 App。
   - reset app data 可配置。
   - 注入 service URLs。
   - 调用 Maestro flows。
3. 执行 flow：
   - Device A 登录。
   - Device B 登录。
   - A 打开 chat 并发送 runId 消息。
   - B 等待并断言收到。
   - B 反向发送，A 等待并断言收到。
4. 输出报告：
   - 设备信息。
   - runId。
   - flow pass/fail/skipped。
   - screenshot/log 路径脱敏。

### 4.1 本步骤实现记录

- 扩展 `tests/e2e_test/harness/mobile_e2e_runner.dart` 的 `timings.json`，统一记录 `scenario: mobile-two-device`、`MOBILE-E2E-001`、`runId`、`dryRun`、`skipBuild`、平台、App ID、service URL 摘要、账号 handle、设备配置摘要和 A_TO_B / B_TO_A 消息计划。
- dry-run 时 `status` 仍表示 runner 执行成功，但 `caseStatus` 明确为 `skipped`，`skippedReason` 记录设备准备、安装和 Maestro flows 被跳过，避免把无设备 dry-run 当作真实 E2E 通过。
- real run 时继续复用现有 build、设备准备、安装、登录、Maestro `open_chat_and_send` / `open_chat_and_wait` 双向消息流程；本步骤不绕过 App UI、SDK 或服务契约。
- 增加 report 和命令日志脱敏：service URL 去除 query string，设备 ID 以稳定摘要脱敏，report 路径归一为 `<repo>`，命令参数隐藏手机号、OTP、token、JWT、private 和 secret 值。
- 扩展 `tests/unit_test/e2e_harness/mobile_e2e_runner_test.dart`，覆盖 dry-run report 字段、`caseStatus: skipped`、手机号/OTP/token/JWT/device id 不进入 report/log、Maestro selector 仍能匹配 App source。
- 更新 `docs/testing.md` 和 `tests/e2e_test/README.md`，说明 mobile dry-run report 只证明 runner plan，真实 case 仍需 iOS/Android 两设备环境。

## 5. 路径

| 仓库 / 模块 / 文件 | 计划变更 | 备注 |
|---|---|---|
| `test-awiki-me/tests/e2e_test/harness/mobile_e2e_runner.dart` | 已扩展 dry-run/real run 共享 report、case status 和脱敏命令日志 | real run 仍依赖设备池 |
| `test-awiki-me/tests/e2e_test/mobile/maestro/` | 后续维护 Maestro flows | 平台共享 |
| `test-awiki-me/tests/e2e_test/configs/mobile.example.yaml` | 后续补字段说明 | 只提交 example |
| `test-awiki-me/tests/e2e_test/configs/mobile.local.yaml` | 本地运行配置 | 不提交 |
| `test-awiki-me/.e2e/reports/` | 运行时报告和状态 | 不提交 |
| `test-awiki-me/docs/testing.md` | 已补 mobile dry-run report 语义和脱敏规则 | 文档入口 |
| `test-awiki-me/tests/e2e_test/README.md` | 已补 `MOBILE-E2E-001` dry-run report 说明 | harness 入口 |

## 6. 依赖

- 前置步骤：Step 03。
- 外部文档或决策：设备池、账号池、nightly runner 类型。
- 环境前提：iOS simulator/Xcode 或 Android emulator/SDK，Maestro 可用，后端可达。

## 7. 验收标准

- [x] dry-run 不需要设备和真实后端。
- [x] real run 使用两套账号和两个独立设备/模拟器的 runner 路径已保留；当前 host 未配置真实 iOS/Android 设备池和 `mobile.local.yaml`，未运行 real E2E。
- [x] A->B 和 B->A 均有唯一 runId 消息断言计划，dry-run report 记录对应 message ID；真实断言仍由 Maestro flow 执行。
- [x] device logs、screenshots、reports 不泄漏 OTP/JWT/private key 的规则已补；本步骤验证了 report/log 层脱敏，真实 Maestro screenshots/logs 仍需 nightly/release 扫描。
- [x] 设备不可用时 dry-run 明确 `caseStatus: skipped` 和 skipped reason，不影响 PR required gate。
- [x] Review 发现已经修复或明确记录。
- [x] 本步骤在进入下一步之前已经创建聚焦 commit。

## 8. 验证方式

| 检查项 | 命令 / 方法 | 预期证据 |
|---|---|---|
| Mobile dry-run | `cd test-awiki-me && dart run tests/e2e_test/harness/mobile_e2e_runner.dart --config tests/e2e_test/configs/mobile.example.yaml --dry-run` | 通过；runId `20260614061538-0ef4ka`，设备和 flow 计划可生成，report caseStatus 为 `skipped`。 |
| iOS real | `cd test-awiki-me && dart run tests/e2e_test/harness/mobile_e2e_runner.dart --config tests/e2e_test/configs/mobile.local.yaml` | iOS 两设备 run 通过或记录 host 不支持。 |
| Android real | `cd test-awiki-me && dart run tests/e2e_test/harness/mobile_e2e_runner.dart --config tests/e2e_test/configs/mobile.local.yaml` | Android 两设备 run 通过或记录 host 不支持。 |
| Unit | `cd test-awiki-me && flutter test tests/unit_test/e2e_harness/mobile_e2e_runner_test.dart` | 通过，15 tests；覆盖 runner parser、dry-run report、command redaction、Maestro selector。 |
| Analyze | `cd test-awiki-me && dart analyze` | 通过，无 analyzer issue。 |
| Secret | 扫描 docs、runner、unit tests、tool 和 E2E test 相关路径 | 扫描仅命中 env 名、示例占位手机号、测试用假 secret 和既有 redaction 测试数据，无真实 secret。 |

## 9. Review 环节

- Review 时机：mobile runner/flow/config 调整完成后、commit 前。
- Review 重点：设备隔离、账号隔离、flow 稳定性、失败证据、Maestro selector、日志脱敏、是否误入 PR required gate。
- Review 结论必须在 commit 前记录。

| Review 项 | 结果 | 备注 |
|---|---|---|
| 发现问题 | dry-run `timings.json` 原先只包含 status/steps，缺少 case ID、平台、账号、设备、消息计划和 skipped 语义；命令日志会原样打印 URL query、手机号和 OTP 参数。 | 已修复。 |
| 已修复问题 | 已修复 | 增加 `mobile-two-device` report metadata、`MOBILE-E2E-001`、dry-run `caseStatus: skipped`、service URL query 剥离、device ID 和路径脱敏、命令参数 redaction。 |
| 剩余风险 | real iOS/Android 两设备 E2E 未在当前 Linux host 运行 | 当前环境没有真实设备池、Maestro real run 条件、非生产账号 local config；真实通过仍需 nightly/release/manual 环境验证。 |
| 新增或缺失测试 | 已新增非真实 gate 覆盖 | runner 单测覆盖 dry-run report 和命令日志脱敏；真实设备登录/消息互通仍只能在设备池环境运行。 |
| 已更新或缺失文档 | 已更新 | `docs/testing.md`、`tests/e2e_test/README.md`、主 Plan 和本 Step 均已记录 dry-run 语义、skipped 规则和真实设备前提。 |

## 10. Commit 要求

- Commit 时机：实现、验证、Review 都完成后。
- Commit 范围：mobile runner、Maestro flows、example config、docs 的聚焦修改。
- Commit 前状态：记录 `git status --short --branch`。
- 纳入文件：记录本步骤 commit 包含的文件。
- Commit 后证据：记录 commit hash 和 commit 后 `git status`。
- 建议消息：`test: add mobile two device e2e`
- Commit 前状态：`git status --short --branch` 显示本步骤相关 runner、unit test、docs 修改，另有无关未跟踪旧草稿目录 `docs/e2e/desktop-cli-peer-macos-linux-execution/` 和 ignored `.e2e/` dry-run 产物。
- 纳入文件：`docs/e2e/awiki-me-e2e-regression-plan/plan.md`、本文件、`docs/testing.md`、`tests/e2e_test/README.md`、`tests/e2e_test/harness/mobile_e2e_runner.dart`、`tests/unit_test/e2e_harness/mobile_e2e_runner_test.dart`。
- Commit 后证据：提交后回填 commit hash 和 post-commit status。

## 11. Blocked 处理

| Blocker | 证据 | 已尝试方案 | 影响范围 | 下一步决策 |
|---|---|---|---|---|
| 无设备池 | runner/maestro 报错 | 保留 dry-run 和 desktop E2E | Mobile real E2E | 标 nightly/manual blocked |
| Maestro selector 不稳定 | flow 失败截图 | 补稳定 semantics 或拆分 flow | 当前步骤 | 先保留最小登录/消息 flow |

## 12. Plan 变更记录

| 日期 | 变更 | 原因 | 主 Plan 变更记录链接 |
|---|---|---|---|
| 待记录 | 待记录 | 待记录 | [../plan.md#17-plan-变更记录](../plan.md#17-plan-变更记录) |

## 13. 风险、回滚与后续文档

- 风险：移动 E2E flake 高于桌面 E2E。
- 回滚 / 回退：将 mobile real run 保持 manual/nightly，不纳入 required gate。
- 后续文档：Step 08 记录移动 E2E 的运行频率和失败处理策略。
