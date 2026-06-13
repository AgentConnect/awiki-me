# Agent IM 委托消息处理 E2E 测试方案

状态：draft
日期：2026-06-13
归属仓库：`awiki-me`
关联计划：[plan.md](plan.md)

## 1. 背景与目标

本方案面向 Agent IM 的核心能力：用户在 `awiki-me` App 中把自己的消息处理能力委托给服务端 Daemon 侧的智能体。目标链路如下：

```text
awiki-me App
  -> 生成 / 读取用户 DID 子私钥包：user_did#daemon-key-1
  -> 通过普通非 E2EE 消息发送 awiki.daemon.bootstrap.v1 给 Daemon
  -> Daemon 导入 delegated identity，并用该子私钥连接 awiki.info Message Service
  -> CLI peer 或其他用户给 App 当前账号发送普通消息
  -> Daemon/Hermes 代表用户侧智能体接收并处理该消息
  -> Daemon 将 awiki.message.sync.v1 / awiki.app.action.result.v1 等摘要或状态返回 App
  -> App 展示摘要、状态、草稿或待确认动作，并且 system/control payload 不污染普通聊天
```

本方案只设计测试与联调落地，不在当前文档阶段修改功能代码或执行远端部署。

## 2. 权威上下文

| 来源 | 作用 |
|---|---|
| `awiki-cli-rs2/docs/agent-im/agent_im_core_design.md` | Agent IM 总体功能设计。 |
| `awiki-cli-rs2/docs/agent-im/agent_delegated_identity_message_proof_plan.md` | 用户 DID delegated subkey、DID proof、message proof 策略。 |
| `awiki-cli-rs2/docs/agent-im/plan/plan.md` | 已完成开发计划与系统测试收口历史。 |
| `awiki-cli-rs2/docs/agent-im/plan/steps/05-awiki-deamon-user-delegated-inbox-sync.md` | Daemon delegated inbox sync、cursor、E2EE opaque ignore。 |
| `awiki-cli-rs2/docs/agent-im/plan/steps/06-awiki-me-pairing-bootstrap-ui-service.md` | App bootstrap UI/service、`awiki.daemon.bootstrap.v1`。 |
| `awiki-cli-rs2/docs/agent-im/plan/steps/07-message-service-delegated-key-policy-and-fanout.md` | Message Service delegated key policy 与同 DID 多连接 fanout。 |
| `awiki-cli-rs2/docs/agent-im/plan/steps/08-app-action-schema-and-visibility.md` | App action schema、allowlist、未知 `awiki.*` payload 可见性。 |
| `awiki-me/docs/awiki-me-test-framework-plan.md` | `awiki-me` 当前测试框架与 Mac/Linux E2E 复用原则。 |
| `awiki-me/docs/testing.md` | `awiki-me` 测试目录、runner、integration shim 规则。 |
| `awiki-me/codex.md` | `awiki.info` 联调可通过 `ssh ali`，且不得输出密钥、JWT、私钥。 |
| [context-contract-baseline.md](context-contract-baseline.md) | Step 01 对当前代码、契约、测试入口、ANP SDK 依赖边界和 P0 缺口的基线核对。 |

## 3. 测试边界

### 3.1 MVP 必测边界

- 只要求普通非 E2EE 消息进入 Agent 处理链路。
- `awiki.daemon.bootstrap.v1` 是 system/control payload，不显示为普通聊天内容。
- Daemon 使用 `user_did#daemon-key-1` 进行 delegated proof，Message Service 校验 DID Document `authentication`、owner 一致性和普通消息 scope。
- 同一用户 App 与 Daemon 同时连接时，Message Service fanout 应覆盖 App 与 Daemon。
- Daemon/Hermes 返回给 App 的摘要、同步、action result 必须进入 App 的系统状态或待确认区域，而不是普通聊天气泡。
- 私钥包、JWT、access token、refresh token、message proof secret、runtime token 不得进入日志、报告、截图、CLI stdout 或 UI。

### 3.2 明确非目标

- 不在 MVP 中测试 Agent 解密 E2EE 私聊明文。
- 不要求群聊 E2EE、MLS、Agent participant 或 explicit E2EE forward。
- 不把服务端 remote 部署路径、密钥路径、数据库密码写入仓库文档。
- 不把用户生产账号作为测试账号。

## 4. 与现有 E2E 框架的关系

现有 `awiki-me` E2E 框架已经确立三类并行测试目录：

```text
awiki-me/tests/unit_test/
awiki-me/tests/integration_test/
awiki-me/tests/e2e_test/
```

本功能的真实端到端测试应放在：

```text
awiki-me/tests/e2e_test/scenarios/agent_im_delegated_message/
```

如果需要 Flutter `integration_test` 插件驱动真实 macOS/Linux App，则保留根级 shim：

```text
awiki-me/integration_test/agent_im_delegated_message_e2e_test.dart
```

实际实现仍应位于 `awiki-me/tests/e2e_test/scenarios/` 或 `awiki-me/tests/integration_test/`，根级 `integration_test/` 只作为 Flutter tooling entrypoint。

CLI peer 使用 `awiki-cli-rs2`，不要使用旧 `awiki-cli` 作为当前端侧架构权威。

## 5. E2E 参与者

| 参与者 | 角色 | 测试实现 |
|---|---|---|
| App A | 用户 A 的 `awiki-me` App，负责登录、bootstrap、展示同步结果 | Flutter macOS/Linux integration target 或后续移动 target。 |
| CLI Peer B | 另一个测试用户，向用户 A 发送普通消息 / E2EE 消息 | `awiki-cli-rs2` 的 `awiki-cli`，使用隔离 workspace。 |
| Daemon / Hermes | 用户 A 委托的服务端智能体宿主 | `awiki.info` 服务器，通过 `ssh ali` 查看日志、状态、部署版本。 |
| User Service | DID Document、delegated public key、auth/JWT | `awiki.info`。 |
| Message Service | 普通消息、fanout、delegated proof、E2EE opaque 边界 | `awiki.info`。 |
| E2E Harness | 编排 App、CLI、远端观测、报告与脱敏 | `awiki-me/tests/e2e_test/harness/`。 |

## 6. 核心场景

详见 [scenario-matrix.md](scenario-matrix.md)。优先级建议：

1. P0 Happy Path：App bootstrap -> Daemon delegated inbox -> CLI 普通消息 -> Hermes 处理 -> App 收到 summary/status。
2. P0 Bootstrap 幂等：相同 `idempotency_key` 不重复创建 runtime/message agent。
3. P0 Daemon 重启恢复：cursor 不回退，历史消息不重复处理，新消息继续处理。
4. P1 E2EE 不进入 Agent：opaque 消息不解密、不摘要、不进入 Hermes prompt。
5. P1 Delegated key 撤销：DID Document 移除 `#daemon-key-1` 后 delegated proof 被拒绝并可恢复提示。
6. P1 私钥泄漏检查：本地报告、CLI workspace、App logs、远端 logs 均无敏感材料。
7. P1 未知 `awiki.*` payload：不污染普通聊天，进入 unsupported/system dispatch。

## 7. 配置建议

建议新增 example config，但不要提交 local config 或真实账号状态：

```text
awiki-me/tests/e2e_test/configs/agent_im_delegated.example.yaml
awiki-me/tests/e2e_test/configs/agent_im_delegated.local.yaml   # gitignored/local only
```

配置结构建议：

```yaml
service:
  baseUrl: https://awiki.info
  userServiceUrl: https://awiki.info
  messageServiceUrl: https://awiki.info
  messageServiceWsUrl: wss://awiki.info/im/ws
  didDomain: awiki.info

remote:
  sshAlias: ali
  collectLogs: true
  redactSecrets: true

cliPeer:
  repo: ../awiki-cli-rs2
  workspaceRoot: .e2e/agent-im/cli-peer

app:
  platform: macos
  runMode: integration_test

agent:
  expectedRuntime: hermes
  delegatedKeyFragment: daemon-key-1

accounts:
  appUser:
    phoneEnv: DEV_OTP_PHONE
    otpEnv: DEV_OTP_CODE
    handle: awiki-e2e-agent-app
  peerUser:
    phoneEnv: AWIKI_E2E_PEER_PHONE
    otpEnv: AWIKI_E2E_PEER_OTP
    handle: awiki-e2e-agent-peer

timeouts:
  bootstrapSeconds: 60
  daemonConnectSeconds: 90
  messageProcessSeconds: 120
```

注意：文档和 runner 只能记录环境变量名，不要输出变量值。

## 8. 服务端联调方案

服务端位于 `awiki.info`，联调入口为：

```bash
ssh ali
```

详见 [remote-awiki-info-runbook.md](remote-awiki-info-runbook.md)。联调时需要做到：

- 每次 E2E run 生成 `runId`，本地 report、CLI 消息内容、App 日志、远端日志统一带上该 `runId`。
- 远端只收集和 `runId` 相关的 Daemon、Hermes、Message Service、User Service 日志。
- 日志进入报告前必须脱敏：私钥、JWT、token、OTP、Authorization header、proof secret、runtime token 均要替换为固定占位符。
- 如果需要临时修改服务端代码或部署，必须在后续执行计划中作为单独 step，记录 commit、部署版本、回滚命令和验证证据。

## 9. 验收标准

- App 能成功发送 `awiki.daemon.bootstrap.v1`，并且 payload 不显示为普通聊天。
- Daemon 能导入 delegated subkey，并以 delegated identity 连接 / 拉取普通消息。
- CLI Peer 给 App 用户发普通非 E2EE 消息后，App 与 Daemon 都能收到，Hermes 只处理一次。
- Daemon 返回的摘要或 action result 能被 App 展示在正确区域。
- E2EE 消息不进入 Agent 明文处理链路。
- 重复 bootstrap、Daemon 重启、delegated key 撤销均有明确可观测结果。
- 本地 `.e2e` 报告、CLI workspace、App logs、远端 logs 不包含敏感材料。
- Mac 与 Linux E2E 共享 scenario、CLI peer、config parser、report/redaction，只在 platform adapter 分叉。

## 10. 后续落地计划

详细分步计划见 [plan.md](plan.md)。
