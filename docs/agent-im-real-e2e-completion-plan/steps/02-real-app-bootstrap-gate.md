# Step 02：App 真实 bootstrap probe 与 P0 gate 改造

主 Plan：[../plan.md](../plan.md)
Step index：02
状态：committed

## 1. 执行状态

| 字段 | 值 |
|---|---|
| Status | committed |
| Branch | `feature/release-0526/agent-im-hutong` |
| Started | 2026-06-14 |
| Completed | 2026-06-14 |
| Commit | `awiki-me` `0c72111` `test: enforce real agent im e2e gate` |
| Review evidence | 已新增真实 Dart App probe、App bootstrap `run_id`、App 回传轮询、P0 缺证据 fail gate 和 secret redaction；非 dry-run 中缺少 App bootstrap / App return evidence 会 fail，不再 skipped；App return evidence 必须证明 control payload 被普通聊天过滤（`hiddenFromChat=true`），否则 P0 fail。 |
| Verification evidence | `flutter test tests/unit_test/e2e_harness/desktop_agent_im_harness_test.dart` 22 passed；targeted `dart analyze` No issues；example config dry-run PASS。 |
| Next action | 等真实远端 `awiki.info` E2E 跑通后做最终 Review；如需修正 gate 再追加提交。 |

状态取值：`pending`、`in_progress`、`review`、`blocked`、`committed`、`done`。

## 2. 目标

- 结果：非 dry-run E2E 使用真实 `awiki-me` Dart/SDK 路径完成 App 账号恢复/登录、session refresh、daemon subkey package、agent inventory、bootstrap 发送、App history/payload 回传轮询。
- 用户 / 系统可见行为：runner 的 `AIM-E2E-001` / `AIM-E2E-002` 只有在真实证据满足时 pass；否则 fail。
- 非目标：不做完整 UI 自动点击；不改旧 legacy skill；不输出秘密。
- 完成标准：`AgentImAppBootstrapScenario` 不再依赖 fake `_RecordingMessagingService` 作为非 dry-run 证据；`agent-im-scenario-result.json` 包含真实 App identity、daemon DID、bootstrap send result、received sync/action result 证据摘要。

## 3. 设计方法

- 设计边界：真实 App path 可以通过 `tool/agent_im_real_e2e_probe.dart` 或 `tests/e2e_test` Dart helper 调用 App application/data 层；它必须使用 `AwikiImCoreRuntime` 和 App adapters，而不是手写 message-service RPC。
- 核心决策：
  - dry-run 仍可使用计划，不调用真实服务。
  - non dry-run 必须：recover/register App 用户、ensure session、ensure daemon subkey package、list/select daemon agent、send bootstrap、poll history/inbox for returned payload。
  - config 增加 daemon selection 和 app workspace 字段时，必须更新 example 和 report redaction。
- 契约 / API / 数据流：`DefaultAgentControlService.ensureMessageAgentBootstrap` 仍是 bootstrap 构造与发送入口；`ImCoreMessagingService` / `AwikiImCoreMessageAdapter` 是发送路径。
- 兼容性：本地 `agent_im_delegated.local.yaml` 不提交；已有 example 可 dry-run。
- 迁移策略：无数据库迁移。
- 风险控制：Dart probe stdout 只输出脱敏 JSON；stderr 不能包含 token/private package。

## 4. 实现方法

1. 扩展 `AgentImDelegatedConfig`：支持 App E2E workspace、可选 daemon DID/handle/selection、message sync poll timeout；更新 example/report。
2. 新增真实 App probe：
   - 初始化隔离 `AwikiImCorePathLayout` 或可配置路径；
   - 用 App 用户 env 的 phone/OTP recover，失败则 register；
   - select identity 并 ensure messaging session；
   - 通过 `AwikiImCoreIdentityAdapter.ensureDaemonSubkeyPackage` 生成 delegated subkey；
   - 用 `UserServiceAgentInventoryAdapter` 读取 agents 或按 config 选择 Daemon；
   - 调 `DefaultAgentControlService.ensureMessageAgentBootstrap` 发送真实 payload；
   - 轮询与 Daemon 的 direct history，寻找 `awiki.message.sync.v1` / `awiki.app.action.result.v1` 且 runId/message ID 匹配。
3. 改造 `AgentImDelegatedMessageScenario`：non dry-run 下 P0 只有 `appBootstrapRealOk && cliSendOk && remote/returnEvidenceOk` 才 pass；否则 fail。
4. 增加 unit tests：
   - non dry-run App+CLI ok 但无回传时 P0 fail；
   - 有回传和远端证据时 P0 pass；
   - P0 dry-run skipped 仍保留；
   - report 不含 private key/token/env value。
5. 更新 `tests/e2e_test/README.md`、`docs/testing.md` 和本 Plan 台账。

## 5. 路径

| 仓库 / 模块 / 文件 | 计划变更 | 备注 |
|---|---|---|
| `awiki-me/tool/agent_im_real_e2e_probe.dart` | 新增或扩展真实 App probe | 使用 App data/application 层。 |
| `awiki-me/tests/e2e_test/harness/src/agent_im_config.dart` | 新增配置字段 | 需要 example 和 report 更新。 |
| `awiki-me/tests/e2e_test/scenarios/agent_im_delegated_message/` | 改 P0 gate、接入 probe result | 非 dry-run 不允许 P0 skipped。 |
| `awiki-me/tests/unit_test/e2e_harness/` | 补 gate/unit tests | 防止回归到 skipped。 |
| `awiki-me/tests/e2e_test/configs/agent_im_delegated.example.yaml` | 更新示例 | 不写真实秘密。 |
| `awiki-me/docs/testing.md`、`awiki-me/tests/e2e_test/README.md` | 更新真实 E2E 说明 | 记录 P0 gate。 |

## 6. 依赖

- 前置步骤：Step 01。
- 外部文档或决策：`awiki-cli-rs2/docs/agent-im/plan/steps/06-awiki-me-pairing-bootstrap-ui-service.md`、`steps/08-app-action-schema-and-visibility.md`。
- 环境前提：App 用户 OTP env、`awiki.info`、`awiki-cli-rs2` CLI binary。

## 7. 验收标准

- [ ] Non dry-run scenario 不再在 App+CLI ok 时返回 P0 skipped。
- [ ] 真实 App probe 可 recover/register App 用户并通过 `DefaultAgentControlService` 发 bootstrap。
- [ ] App 侧能轮询并识别回传 payload；没有回传时 P0 fail。
- [ ] Unit tests 覆盖 P0 gate、redaction 和 config。
- [ ] Review 发现已经修复或明确记录。
- [ ] 本步骤在进入下一步之前已经创建聚焦 commit。

## 8. 验证方式

| 检查项 | 命令 / 方法 | 预期证据 |
|---|---|---|
| Analyze | `cd awiki-me && dart analyze` | No issues。 |
| Unit | `cd awiki-me && flutter test tests/unit_test/e2e_harness tests/unit_test/e2e_scenarios` | Focused tests pass。 |
| Dry-run | `cd awiki-me && dart run tests/e2e_test/harness/desktop_e2e_runner.dart --platform=macos --scenario=agent-im-delegated-message --config tests/e2e_test/configs/agent_im_delegated.example.yaml --dry-run --skip-cli-build --skip-flutter-smoke` | 计划输出，P0 dry-run skipped。 |
| Real initial | `cd awiki-me && dart run tests/e2e_test/harness/desktop_e2e_runner.dart --platform=macos --scenario=agent-im-delegated-message --config tests/e2e_test/configs/agent_im_delegated.local.yaml --skip-flutter-smoke` | 若服务侧未修复，应清晰 fail 并给出缺口，不 skipped。 |

## 9. Review 环节

- Review 时机：本步骤代码实现完成后、commit 前。
- Review 重点：真实 App path、P0 gate 语义、配置兼容、秘密脱敏、是否绕过 SDK、是否依赖 legacy skill。
- Review 结论必须在 commit 前记录；必须修复必要问题，或明确记录剩余风险。

| Review 项 | 结果 | 备注 |
|---|---|---|
| 发现问题 | 待回填 | - |
| 已修复问题 | 待回填 | - |
| 剩余风险 | 待回填 | - |
| 新增或缺失测试 | 待回填 | - |
| 已更新或缺失文档 | 待回填 | - |

## 10. Commit 要求

- Commit 时机：实现、验证、Review 都完成后。
- Commit 范围：`awiki-me` App probe、E2E gate、unit tests、docs 和本计划台账。
- Commit 前状态：记录 `git status`。
- 纳入文件：记录本步骤 commit 包含的文件。
- Commit 后证据：记录 commit hash 和 commit 后 `git status`。
- 遗留未提交变更：必须记录原因以及为什么安全。
- 建议消息：`test: enforce real agent im app e2e gate`

## 11. Blocked 处理

| Blocker | 证据 | 已尝试方案 | 影响范围 | 下一步决策 |
|---|---|---|---|---|
| App recover/register 失败 | probe 脱敏错误 | 确认 env、handle、local state；尝试 register fallback | 当前步骤 | 不能 skipped；记录 fail 并修复。 |
| 没有可用 Daemon agent | inventory 为空 | 远端确认 Daemon 是否为该 controller 注册；必要时引导安装/绑定 | P0 E2E | 进入 Step 03/04 修复远端。 |

## 12. Plan 变更记录

| 日期 | 变更 | 原因 | 主 Plan 变更记录链接 |
|---|---|---|---|
| 2026-06-14 | 创建 Step 02 | 补真实 App E2E gate | [../plan.md#15-plan-变更记录](../plan.md#15-plan-变更记录) |

## 13. 风险、回滚与后续文档

- 风险：probe 可能输出敏感字段；必须使用 redactor 和最小 JSON。
- 回滚 / 回退：回滚 `awiki-me` probe/gate commit 可恢复旧 skeleton，但不得作为完成状态。
- 后续文档：Step 05 汇总真实运行方式和故障排查。
