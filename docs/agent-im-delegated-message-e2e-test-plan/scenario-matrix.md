# Agent IM 委托消息处理场景矩阵

状态：draft  
主方案：[README.md](README.md)

## 1. 优先级定义

| 优先级 | 含义 | Release gate |
|---|---|---|
| P0 | 没有该场景就无法证明核心功能可用 | 必须进入首批 E2E 自动化或明确 blocker。 |
| P1 | 核心边界、安全和恢复能力 | 可以分阶段进入 nightly/manual gate，但必须有计划。 |
| P2 | 长尾兼容、压力、体验增强 | 不阻塞首轮完整链路。 |

## 2. 场景矩阵

| ID | 优先级 | 场景 | 前置条件 | 步骤摘要 | 预期结果 | 主要观测点 |
|---|---|---|---|---|---|---|
| AIM-E2E-001 | P0 | Happy Path 普通消息委托处理 | App 用户已登录；Daemon/Hermes 在 `awiki.info` 可用；CLI peer 可登录 | App 发送 `awiki.daemon.bootstrap.v1`；CLI peer 给 App 用户发普通消息；等待 Daemon 处理并回传 | App 收到普通消息和 Agent 摘要/状态；Daemon 只处理一次；system payload 不进聊天 | App UI/event、CLI send result、Daemon log、Message Service fanout log、report `runId` |
| AIM-E2E-002 | P0 | Bootstrap 幂等 | AIM-E2E-001 的账号与 Daemon 可用 | 使用相同 `idempotency_key` 重发 bootstrap | 不重复创建 runtime/message agent；App 状态稳定 | Daemon state、agent registry、App status |
| AIM-E2E-003 | P0 | Daemon 重启恢复 | 已完成一次消息处理 | 记录 cursor；重启 Daemon；发送第二条普通消息 | 第一条不重复处理；第二条正常处理；cursor 前移 | Daemon cursor、processed message table/log、Hermes prompt count |
| AIM-E2E-004 | P1 | E2EE opaque 不进入 Agent | App 与 CLI peer 均支持 E2EE 发送 | CLI peer 发送 E2EE 消息给 App 用户 | App 可按客户端能力处理；Daemon 不解密、不摘要、不把明文送 Hermes | Message Service opaque log、Daemon ignored event、无 Hermes prompt 明文 |
| AIM-E2E-005 | P1 | Delegated key 撤销 | 用户 DID Document 已包含 `#daemon-key-1` | 撤销或移除 delegated public method；等待刷新；Daemon 尝试 delegated send/inbox | Message Service 拒绝 delegated proof；App/Daemon 展示可恢复状态 | User Service DID Document、Message Service auth failure、Daemon error classification |
| AIM-E2E-006 | P1 | 私钥与 token 泄漏检查 | 任意完整 E2E run | 扫描本地 report、CLI workspace、App logs、远端 runId logs | 不出现私钥、JWT、Authorization、OTP、runtime token、raw private package | redaction scan report |
| AIM-E2E-007 | P1 | 未知 `awiki.*` payload 可见性 | App 与 Daemon 连接正常 | CLI/Daemon 注入未知 `awiki.unknown.v1` 或 unsupported action | App 不显示普通聊天；进入 unsupported/system 状态；Daemon 不执行危险动作 | App reducer、UI state、Daemon dispatch log |
| AIM-E2E-008 | P2 | Message Service fanout 多连接顺序 | App 与 Daemon 同 DID 同时在线 | 连续发送多条普通消息 | App 与 Daemon 都收到；顺序一致或按契约排序；无重复处理 | inbox/history、server seq、Daemon cursor |
| AIM-E2E-009 | P2 | 远端服务短暂不可用恢复 | 可控制测试环境服务重启 | 短暂断开 Message Service 或 Daemon 连接，再恢复 | reconnect 后继续同步，不丢失未处理普通消息 | reconnect log、cursor、App status |

## 3. 首批自动化建议

首批只实现最小闭环，不一次性覆盖所有 P1/P2：

```text
首批：AIM-E2E-001 + AIM-E2E-002 + AIM-E2E-006 的基础扫描
第二批：AIM-E2E-003 + AIM-E2E-004
第三批：AIM-E2E-005 + AIM-E2E-007
```

这样可以先把 App + CLI peer + awiki.info + Daemon/Hermes 的可运行骨架建立起来，再逐步加恢复、安全与异常场景。


## 4. 当前自动化落地状态（Step 05）

| ID | 当前状态 | 自动化入口 | 说明 |
|---|---|---|---|
| AIM-E2E-001 | skeleton / dry-run skipped | `agent-im-scenario-result.json` | 已把 App bootstrap、CLI peer ordinary send、remote evidence plan 串到同一 scenario result；真实 Daemon/Hermes/App summary pass 需要 Step 06 远端证据后判定。 |
| AIM-E2E-002 | skeleton / dry-run skipped | `agent-im-scenario-result.json` | App 侧可观测 message-agent-bootstrap idempotency key；Daemon runtime/message agent 去重证据需要 Step 06 远端 registry/log。 |
| AIM-E2E-006 | automated | `AgentImRedactionScanner` + `agent-im-scenario-result.json` | dry-run 已扫描 report/log 文件；真实 run 会继续扫描 report 与 CLI peer log 文件，不扫描 credential store 原始私钥。 |
| AIM-E2E-003 | skipped skeleton | `agent-im-scenario-result.json` | 需要可控 Daemon restart/cursor 观测窗口。 |
| AIM-E2E-004 | skipped skeleton | `agent-im-scenario-result.json` | MVP 不让 Agent 解密 E2EE；后续只验证 opaque 不进 prompt。 |
| AIM-E2E-005 | skipped skeleton | `agent-im-scenario-result.json` | 需要 User Service DID Document 撤销与 Message Service delegated proof 远端证据。 |
| AIM-E2E-007 | skipped skeleton | `agent-im-scenario-result.json` | 需要未知 `awiki.*` 注入与 App/Daemon dispatch 组合验证。 |
