# Step 03：CLI peer 与测试账号编排

主 Plan：[../plan.md](../plan.md)  
Step index：03  
状态：done

## 1. 执行状态

| 字段 | 值 |
|---|---|
| Status | done |
| Branch | `feature/release-0526/agent-im-hutong` |
| Started | 2026-06-13 21:10:17 +0800 |
| Completed | 2026-06-13 21:13:38 +0800 |
| Commit | `test: add cli peer orchestration`；短 hash 以本步骤提交后的 `git log -1` 为准 |
| Review evidence | Review 完成：确认 CLI peer adapter 只调用 `awiki-cli-rs2` 命令，不拼 message-service RPC；workspace 按 runId/peer-b 隔离；dry-run 只输出 env 名；command stdout/stderr/report 经过 redaction；未修改 `awiki-cli-rs2`。 |
| Verification evidence | `flutter test tests/unit_test/e2e_harness` 25 passed；`dart analyze` No issues；`cargo build -p awiki-cli --bin awiki-cli` 通过；Agent IM dry-run PASS 并生成 `cli-peer-plan.json`；report sensitive scan 通过。真实 CLI send 未执行，原因是当前未配置 peer 测试账号 env。 |
| Next action | 启动 Step 04：App bootstrap 自动化与 integration entry |

## 2. 目标

- 结果：E2E harness 能用 `awiki-cli-rs2` 作为对端，创建隔离 workspace，登录/恢复测试账号，并发送普通消息给 App 用户。
- 用户 / 系统可见行为：后续 scenario 可以稳定用 CLI peer B 给 App 用户 A 发送带 `runId` 的普通消息。
- 非目标：不使用旧 `awiki-cli`；不在 App 内重复实现 CLI wire；不把真实账号状态提交到仓库。
- 完成标准：CLI peer ordinary message 能在 dry-run 和真实运行路径中被编排；缺失 CLI 能力已在 `awiki-cli-rs2` 中以最小方式补齐并验证。

## 3. 设计方法

- 设计边界：`awiki-me` 只负责 harness 调用与 report；CLI 命令、im-core 行为和身份状态属于 `awiki-cli-rs2`。
- 核心决策：每个 run 使用 `.e2e/<platform>/cli-workspaces/<runId>/peer-b/` 隔离状态。
- 契约 / API / 数据流：CLI peer 通过 im-core/User Service/Message Service 正常登录和发送消息，不绕过业务 API。
- 兼容性：CLI JSON/机器输出必须保留 DID/Handle，human output 不作为解析依赖；harness 优先解析结构化输出。
- 迁移策略：如果 CLI 缺少命令，优先在 `awiki-cli-rs2` 增加薄壳调用 im-core，而不是在 `awiki-me` shell 中拼 RPC。
- 风险控制：OTP、token、workspace config、DID 私钥不得写入 report；只记录账号 handle 或脱敏 DID。

## 4. 实现方法

1. 在 Step 02 的 config 基础上增加 CLI peer 字段解析：repo、binary、workspaceRoot、account env、timeouts。
2. 新增 harness CLI peer adapter：
   - `initWorkspace(runId)`；
   - `loginOrRestore(account)`；
   - `sendOrdinaryMessage(to, text, metadata)`；
   - `sendE2eeMessage(...)` 作为 P1 可选能力；
   - `status()` 和 `collectLogs()`。
3. 若 `awiki-cli-rs2` 现有 CLI 缺少必要命令：在 `awiki-cli-rs2/crates/awiki-cli` 补最小命令或 JSON 输出，并增加对应 cargo tests。
4. 为 adapter 写 fake command runner 单元测试，验证命令参数、env、日志脱敏和失败分类。
5. 真实运行时只使用 non-production 测试账号；`agent_im_delegated.local.yaml` 不提交。

## 5. 路径

| 仓库 / 模块 / 文件 | 计划变更 | 备注 |
|---|---|---|
| `awiki-me/tests/e2e_test/harness/src/` | 新增 CLI peer adapter | 调用 CLI，不拼 RPC |
| `awiki-me/tests/unit_test/e2e_harness/` | 新增 CLI adapter 单元测试 | fake command runner |
| `awiki-me/tests/e2e_test/configs/agent_im_delegated.example.yaml` | 增加 CLI peer account/env 示例 | 不写真实值 |
| `awiki-cli-rs2/crates/awiki-cli/` | 必要时补 CLI 命令或 JSON 输出 | 仅当缺口确认存在 |
| `awiki-cli-rs2/crates/im-core/` | 必要时补 SDK 能力调用 | 避免 CLI 直拼 wire |
| `awiki-cli-rs2/docs/agent-im/` | 如 CLI/契约变更则同步 docs | 文档同变更 |

## 6. 依赖

- 前置步骤：Step 02。
- 外部文档或决策：`awiki-harness/context/nodes/client-architecture.node.md`、`awiki-cli-rs2/docs/api/im-core-interface/`。
- 环境前提：可构建 `awiki-cli-rs2` CLI；真实账号凭证通过环境变量提供。

## 7. 验收标准

- [x] CLI peer workspace 按 runId 隔离。
- [x] harness 不输出 OTP、token、private key 或 raw config。
- [x] CLI peer ordinary send 支持带 runId 的测试消息。
- [x] 如果新增 CLI 命令，命令走 im-core，不直接拼 message-service wire。
- [x] dry-run 能显示 CLI 编排计划；真实模式能收集 CLI send result。
- [x] Review 发现已经修复或明确记录。
- [x] 本步骤在进入下一步之前已经创建聚焦 commit。

## 8. 验证方式

| 检查项 | 命令 / 方法 | 预期证据 |
|---|---|---|
| awiki-me unit | `cd awiki-me && flutter test tests/unit_test/e2e_harness` | CLI adapter 测试通过。 |
| awiki-me analyze | `cd awiki-me && dart analyze` | 无新增 analyze 错误。 |
| CLI build | `cd awiki-cli-rs2 && cargo build -p awiki-cli --bin awiki-cli` | CLI 可构建。 |
| CLI tests | `cd awiki-cli-rs2 && cargo test -p awiki-cli --locked` | 如改 CLI，相关 tests 通过。 |
| im-core tests | `cd awiki-cli-rs2 && cargo test -p im-core --locked` | 如改 im-core，相关 tests 通过。 |
| Harness dry-run | `cd awiki-me && dart run tests/e2e_test/harness/desktop_e2e_runner.dart --platform=macos --scenario=agent-im-delegated-message --config tests/e2e_test/configs/agent_im_delegated.example.yaml --dry-run` | CLI peer steps 出现在计划中。 |

### Step 03 验证记录

| 命令 / 检查 | 结果 | 说明 |
|---|---|---|
| `flutter test tests/unit_test/e2e_harness` | 通过 | 25 passed，覆盖 CLI peer adapter fake runner、dry-run plan、missing env、redaction。 |
| `dart analyze` | 通过 | No issues found。 |
| `cargo build -p awiki-cli --bin awiki-cli` | 通过 | 未修改 CLI 仓库；验证现有 CLI binary 可构建。 |
| Agent IM dry-run | 通过 | 输出 `cli-peer-plan`，生成 `scenario-plan.json`、`cli-peer-plan.json`、`timings.json`。 |
| Report sensitive scan | 通过 | 扫描 `.e2e/macos/reports`，未发现 private key、bearer/JWT、raw phone、raw OTP matcher 命中。 |
| 真实 CLI peer send | 跳过 | 当前未配置 `AWIKI_E2E_PEER_PHONE` / `AWIKI_E2E_PEER_OTP`；真实链路留给 Step 05/06 local config/remote run。 |

## 9. Review 环节

- Review 时机：CLI adapter 和必要 CLI 改动完成后、commit 前。
- Review 重点：CLI 不绕过 im-core、账号隔离、日志脱敏、结构化输出稳定性、失败分类、跨仓 commit 边界。

| Review 项 | 结果 | 备注 |
|---|---|---|
| 发现问题 | 有发现 | 初版 command line 打印未统一 redaction，CLI flag 形式 `--otp <code>` 未覆盖；已在本步骤修复。 |
| 已修复问题 | 已修复 | `DesktopCommandRunner` 打印前 redaction；`SecretRedactor` 增加 CLI flag token/OTP 规则；CLI peer report 仅记录 env 名和脱敏 JSON。 |
| 剩余风险 | 已记录 | 当前未配置 peer 测试账号 env，因此未执行真实远端 `msg send`；Step 05/06 需要用 local config 或远端账号完成真实链路。 |
| 新增或缺失测试 | 已新增 | 新增 fake command runner 单测，覆盖 dry-run plan、真实 flow command 编排、missing env 失败、redaction。缺少真实 CLI peer send，按账号 env 未配置记录为跳过。 |
| 已更新或缺失文档 | 已更新 | 更新 `docs/testing.md`、`tests/e2e_test/README.md`、example config、主 Plan 和本 Step 台账。 |

## 10. Commit 要求

- Commit 时机：实现、验证、Review 完成后。
- Commit 范围：`awiki-me` harness 改动独立 commit；如改 `awiki-cli-rs2`，在该仓库单独 commit。
- Commit 前状态：记录各仓 `git status`。
- 纳入文件：记录本步骤 commit 包含的文件。
- Commit 后证据：记录 commit hash 和 commit 后 `git status`。
- 遗留未提交变更：必须记录原因以及为什么安全。
- 建议消息：`test: add cli peer orchestration`

执行记录：

| 项 | 记录 |
|---|---|
| Commit 前状态 | `awiki-me` ahead 2；本步骤只修改 `awiki-me` harness/config/tests/docs；`awiki-cli-rs2` 与 `message-service` 保留既有用户变更。 |
| 纳入文件 | `tests/e2e_test/harness/src/cli_peer_adapter.dart`、`desktop_e2e_runner.dart`、`agent_im_config.dart`、`scenario_registry.dart`、`secret_redactor.dart`、`agent_im_delegated.example.yaml`、`desktop_agent_im_harness_test.dart`、`tests/e2e_test/README.md`、`docs/testing.md`、本 Plan/Step 台账。 |
| Commit 后证据 | 待提交后由 `git log -1 --oneline` 确认；短 hash 不写入同一提交正文，避免自引用 hash 无法稳定。 |
| 遗留未提交变更 | 仅保留其他仓库既有用户变更；Step 03 不修改这些仓库。 |

## 11. Blocked 处理

| Blocker | 证据 | 已尝试方案 | 影响范围 | 下一步决策 |
|---|---|---|---|---|
| CLI 登录流程需要交互输入 | 待填写 | 支持 env/test config 非交互模式 | 当前步骤 | 补 CLI test mode 或标记 blocker |
| CLI 无普通消息发送能力 | 待填写 | 在 awiki-cli-rs2 补薄壳命令 | 当前步骤 | 更新 Plan scope 后实现 |
| 测试账号不可用 | 当前未配置 `AWIKI_E2E_PEER_PHONE` / `AWIKI_E2E_PEER_OTP` | fake runner 覆盖真实 command 编排；dry-run 输出 CLI peer plan；不执行远端 send | 真实 CLI peer send | Step 05/06 使用 local config 或远端账号执行真实 run |

## 12. Plan 变更记录

| 日期 | 变更 | 原因 | 主 Plan 变更记录链接 |
|---|---|---|---|
| 2026-06-13 | 创建 Step 03 小 Plan | 初始计划拆分 | [../plan.md#15-plan-变更记录](../plan.md#15-plan-变更记录) |

## 13. 风险、回滚与后续文档

- 风险：CLI peer 把账号密钥或 token 写入 report。
- 回滚 / 回退：回滚 adapter/CLI commit，删除本地 `.e2e` report 和 workspace，修复 redactor 后重做。
- 后续文档：如新增 CLI 命令，同步 `awiki-cli-rs2` README/API/Agent IM docs。
