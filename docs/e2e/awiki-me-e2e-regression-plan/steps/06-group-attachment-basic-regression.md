# Step 06：群组与附件基础回归 E2E

主 Plan：[../plan.md](../plan.md)  
Step index：06  
状态：done

## 1. 执行状态

| 字段 | 值 |
|---|---|
| Status | done |
| Branch | `feature/test-awiki-me` |
| Started | 2026-06-14 13:51 CST |
| Completed | 2026-06-14 14:03 CST |
| Commit | `bc17b19` |
| Review evidence | Review 完成：已确认 App 侧使用 `GroupApplicationService` / `MessagingService`，CLI 侧使用 `group messages`、`msg send --group`、`msg send --file`、`msg attachment download` 高层命令；未直接访问 raw RPC、WebSocket、SQLite、附件内部存储对象或 `ModMessage` fixture。 |
| Verification evidence | `dart analyze` 通过；`flutter test tests/unit_test/e2e_harness/desktop_cli_peer_e2e_runner_test.dart` 通过，11 tests；`xvfb-run -a flutter test integration_test/desktop_cli_peer_smoke_test.dart -d linux` 在 `AWIKI_E2E` 未开启时安全 skip；real group/attachment E2E 当前 host 未注入真实后端、OTP 和可用 CLI binary，未运行。 |
| Next action | 启动 Step 07：Mobile 双设备 E2E |

状态取值：`pending`、`in_progress`、`review`、`blocked`、`committed`、`done`。

## 2. 目标

- 结果：把群组和附件纳入 E2E 回归体系，覆盖 direct message 之外的基础协作能力。
- 用户 / 系统可见行为：后续新功能不会破坏群组创建、成员消息、附件发送/接收和基础失败回归。
- 非目标：本步骤不实现 Agent 作为 IM App 处理者的互通场景，不实现端到端加密；这两类场景保留在主矩阵中并标记为 `Skipped`。本步骤也不在第一版覆盖复杂群管理矩阵、大文件、多附件批量、断点续传或所有附件预览类型。
- 完成标准：群组最小两人场景和附件小文件双向场景都有明确 case、环境契约、验收标准和验证命令。

## 3. 设计方法

- 设计边界：群组和附件 E2E 优先使用 App + CLI peer 或 App + 第二设备；服务端群组/附件契约由 `message-service` 和 `awiki-system-test` 提供补充证据。
- 核心决策：第一版只做最小可回归场景：两人群、群内文本、单个小附件。
- 契约 / API / 数据流：App/CLI 必须通过 SDK/CLI 高层能力操作群组和附件，不直接拼 message-service RPC、附件存储路径或本地 SQLite。
- 兼容性：macOS/Linux 共用 scenario；Linux 只在 platform adapter 和 `xvfb-run` 分叉。
- 迁移策略：先在 Desktop App + CLI peer real E2E 基础上扩展群组和附件。
- 风险控制：remote 不可用时记录 skipped/blocker，不伪造 happy path。

## 4. 实现方法

1. 增加群组最小 E2E：
   - App 创建两人群或测试群。
   - 添加 CLI peer 或第二测试账号。
   - App 在群内发送带 runId 的文本。
   - peer 通过 CLI 或第二设备确认收到。
   - peer 在群内反向发送文本，App 确认收到。
2. 增加群组基础回归：
   - 群资料可见。
   - 成员列表可见。
   - history 不重复。
   - 新 direct message 不破坏群会话列表。
3. 增加附件最小 E2E：
   - 准备小型 fixture，例如文本文件或小图片。
   - App 发送附件给 CLI peer 或群组。
   - peer 确认附件 metadata、大小、文件名、hash 或内容摘要。
   - peer 发送附件给 App，App 确认会话中出现附件并能完成基础下载/打开状态断言。
4. 增加附件错误回归：
   - 可控上传失败。
   - 可控下载失败。
   - 重复发送不会破坏会话 history。
5. 将 case 加入场景矩阵：
   - `GROUP-E2E-001`
   - `GROUP-E2E-002`
   - `GROUP-REG-001`
   - `ATTACH-E2E-001`
   - `ATTACH-E2E-002`
   - `ATTACH-REG-001`
6. 输出 redaction scan：
   - CLI logs。
   - App report。
   - scenario result。

### 4.1 本步骤实现记录

- 扩展 `integration_test/desktop_cli_peer_smoke_test.dart` 的真实 `AWIKI_E2E=true` 路径，在 Step 05 direct message 基础上增加群组和附件基础回归。
- 群组路径：App 通过 `GroupApplicationService.createGroup` 创建带 `runId + nonce` 的最小测试群，使用 `addMember` 添加 CLI peer，App 发送群文本，CLI 通过 `group messages` 确认；CLI 使用 `msg send --group` 反向发送群文本，App 通过 `GroupApplicationService.listMessages` 和 `MessagingService.loadHistory` 确认并检查去重。
- 附件路径：App 使用 `MessagingService.sendAttachment` 发送小型 `text/plain` 内存 fixture 给 CLI，CLI 通过 `msg history` 看到 caption，并用 `msg attachment download --with` 下载后校验文件内容。
- CLI 反向附件路径：CLI 用 `msg send --file` 发送小型 `text/plain` fixture 给 App，App 通过 `MessagingService.loadHistory` 检查附件 filename/mime/size/caption，并用 `downloadAttachment` 下载后校验文件内容。
- 扩展 `tool/desktop_cli_peer_e2e_runner.dart` 的 `timings.json` case IDs，纳入 `GROUP-E2E-001`、`GROUP-E2E-002`、`GROUP-REG-001`、`ATTACH-E2E-001`、`ATTACH-E2E-002`、`ATTACH-REG-001`。
- 扩展 `tests/unit_test/e2e_harness/desktop_cli_peer_e2e_runner_test.dart`，验证 dry-run report 中包含群组和附件 case IDs，且仍保持 secret/path redaction。

## 5. 路径

| 仓库 / 模块 / 文件 | 计划变更 | 备注 |
|---|---|---|
| `test-awiki-me/tests/e2e_test/scenarios/` | 后续新增 group / attachment scenario | 复用桌面 runner |
| `test-awiki-me/tests/e2e_test/configs/` | 后续补 group / attachment example config | 只提交 example |
| `test-awiki-me/test/fixtures` 或 `test-awiki-me/tests/e2e_test/fixtures` | 后续放小型附件 fixture | 不放敏感文件或大文件 |
| `awiki-system-test/` | 群组、附件、服务端契约证据 | 需要时运行 focused suite |

## 6. 依赖

- 前置步骤：Step 03、Step 05。
- 外部文档或决策：群组/附件 CLI 能力、附件 fixture 策略、local config、测试账号。
- 环境前提：群组/附件 real run 需要真实服务。

## 7. 验收标准

- [x] 群组创建和群内双向文本消息有 runId evidence 路径；当前 host 未提供真实后端/OTP/CLI binary，未运行 real E2E。
- [x] 附件双向发送/接收至少覆盖一个小型 fixture 路径；当前 host 未提供真实后端/OTP/CLI binary，未运行 real E2E。
- [x] Agent 作为 IM App 处理者的互通场景在主矩阵中标记为 `Skipped`，不要求相关验证证据。
- [x] 本轮端到端加密在主矩阵中标记为 `Skipped`，不要求相关验证证据。
- [x] remote/log/report 经过 redaction scan 的要求已保留；本步骤只运行 safe-skip 和 dry-run/report 单测，没有生成真实 remote log。
- [x] 不把 remote unavailable 伪装为 pass；real group/attachment E2E 未运行项明确记录为未运行。
- [x] Review 发现已经修复或明确记录。
- [x] 本步骤在进入下一步之前已经创建聚焦 commit。

## 8. 验证方式

| 检查项 | 命令 / 方法 | 预期证据 |
|---|---|---|
| Safe skip smoke | `cd test-awiki-me && xvfb-run -a flutter test integration_test/desktop_cli_peer_smoke_test.dart -d linux` | `AWIKI_E2E` 未开启时安全 skip，证明 shim、编译和 skip gate 不阻塞 PR。 |
| Group/attachment real run | `cd test-awiki-me && AWIKI_E2E=true DEV_OTP_PHONE="$DEV_OTP_PHONE" DEV_OTP_CODE="$DEV_OTP_CODE" AWIKI_CLI_BIN="$AWIKI_CLI_BIN" AWIKI_USER_SERVICE_URL="$AWIKI_USER_SERVICE_URL" AWIKI_MESSAGE_SERVICE_URL="$AWIKI_MESSAGE_SERVICE_URL" xvfb-run -a flutter test integration_test/desktop_cli_peer_smoke_test.dart -d linux` | 同一真实 App + CLI peer 路径覆盖 direct、history/inbox、群组基础文本和小附件双向发送/下载；缺真实后端、OTP、CLI binary 或账号池时记录 skipped/blocker，不伪造通过。 |
| System evidence | `cd awiki-system-test && make local-test-message-v2` 或 group/attachment focused suite | 服务侧群组/附件契约不回归；如果无 focused suite，记录缺口。 |

## 9. Review 环节

- Review 时机：群组、附件场景实现或文档更新完成后、commit 前。
- Review 重点：群组成员和会话断言是否真实，附件 fixture 是否小且稳定，附件内容/metadata 校验是否明确，App/CLI 边界是否正确。
- Review 结论必须在 commit 前记录。

| Review 项 | 结果 | 备注 |
|---|---|---|
| 发现问题 | 初版群成员匹配没有过滤空字段；CLI 反向附件下载若使用 App 本地模型 message id 可能与 CLI send result 不一致。 | 已过滤空字段；CLI send 后解析 `data.message.id` 和 `data.attachment.attachment_id` 作为 App 下载目标。 |
| 已修复问题 | 已修复 | 群组和附件路径均使用 `runId + nonce`；附件 fixture 写入隔离 `.e2e/desktop-cli-peer/<runId>/cli-peer` 工作区；runner report case IDs 已扩展。 |
| 剩余风险 | real group/attachment E2E 未在当前 host 运行 | 真实通过仍需 manual/nightly/release 环境提供真实后端、OTP、可用 CLI binary 和附件服务；macOS real run 未在当前 Linux host 运行。 |
| 新增或缺失测试 | 已新增非真实 gate 覆盖 | runner dry-run 单测覆盖 case IDs/report/redaction；Linux safe-skip 覆盖默认跳过。真实群组/附件只完成实现路径，未获得 real backend 证据。 |
| 已更新或缺失文档 | 已更新 | 主 Plan 和本 Step 已记录实现、验证、Review 状态；Step 08 后续负责 gate 收口。 |

## 10. Commit 要求

- Commit 时机：实现、验证、Review 都完成后。
- Commit 范围：群组、附件相关 scenario、harness、docs；跨仓改动单独 commit。
- Commit 前状态：记录 `git status --short --branch`。
- 纳入文件：记录本步骤 commit 包含的文件。
- Commit 后证据：记录 commit hash 和 commit 后 `git status`。
- 建议消息：`test: cover group attachment e2e`
- Commit 前状态：`git status --short --branch` 显示本步骤相关测试/runner/docs 修改，另有无关未跟踪旧草稿目录 `docs/e2e/desktop-cli-peer-macos-linux-execution/`。
- 纳入文件：`docs/e2e/awiki-me-e2e-regression-plan/plan.md`、本文件、`integration_test/desktop_cli_peer_smoke_test.dart`、`tool/desktop_cli_peer_e2e_runner.dart`、`tests/unit_test/e2e_harness/desktop_cli_peer_e2e_runner_test.dart`。
- Commit 后证据：提交后回填 commit hash 和 post-commit status。

## 11. Blocked 处理

| Blocker | 证据 | 已尝试方案 | 影响范围 | 下一步决策 |
|---|---|---|---|---|
| CLI 或 SDK 缺少群组命令 | CLI help/test 证据 | 先用 App service boundary 或补最小 CLI 能力 | 群组 E2E | 更新 Plan 影响范围 |
| CLI 或 SDK 缺少附件命令 | CLI help/test 证据 | 先做 App->service smoke 或补最小 CLI 能力 | 附件 E2E | 更新 Plan 影响范围 |
| 附件存储服务不可用 | 上传/下载错误和服务日志 | 使用小 fixture、检查服务配置 | 附件 E2E | 标 blocked，不进入 required gate |

## 12. Plan 变更记录

| 日期 | 变更 | 原因 | 主 Plan 变更记录链接 |
|---|---|---|---|
| 待记录 | 待记录 | 待记录 | [../plan.md#17-plan-变更记录](../plan.md#17-plan-变更记录) |

## 13. 风险、回滚与后续文档

- 风险：群组和附件场景一次性做太多，导致失败定位困难。
- 回滚 / 回退：按优先级保留群组文本和附件小文件两个独立 scenario；不稳定项单独标 blocked。
- 后续文档：Step 08 将群组、附件场景纳入 nightly/release gate 和 evidence 模板。
