# awiki.info 服务端联调 Runbook

状态：draft  
主方案：[README.md](README.md)

## 1. 目的

本 Runbook 只定义 E2E 测试期间如何与 `awiki.info` 远端服务联调、采集证据、脱敏和回滚。它不是生产部署文档，也不记录远端机器上的真实目录、密钥或数据库连接信息。

## 2. 连接入口

当测试域名是 `awiki.info` 时，可通过 SSH alias 连接远端：

```bash
ssh ali
```

联调输出中禁止包含：

- DID 私钥、daemon subkey private package、seed、助记词。
- JWT、refresh token、Authorization header、runtime RPC token。
- OTP 值、手机号完整值、数据库密码、服务端密钥路径。
- 未脱敏的用户消息正文；E2E runId 消息正文可以使用固定测试短句。

## 3. 每次 E2E run 的证据关联

E2E harness 必须生成 `runId`，并把 `runId` 用于：

- CLI peer 发送的测试消息内容或 metadata。
- App 本地 report 目录：`awiki-me/.e2e/<platform>/reports/<runId>/`。
- 远端日志过滤条件。
- evidence template 中的远端观测记录。

## 4. 远端检查清单

| 检查项 | 方法 | 预期 |
|---|---|---|
| 服务健康 | 通过远端现有 service manager、health endpoint 或日志确认 | User Service、Message Service、Daemon/Hermes 均运行。 |
| 部署版本 | 查看服务启动日志、二进制版本或当前部署 commit | 与本地待测分支或预期部署一致；不一致时记录。 |
| DID Document | 只查看 public method / authentication 是否包含 `#daemon-key-1` | 不输出 private key；确认 owner DID 与 delegated proof 一致。 |
| Message fanout | 按 `runId` 查 Message Service 日志 | App 与 Daemon 同 DID 连接均收到普通消息。 |
| Daemon delegated identity | 按 `runId` 查 Daemon 日志 | bootstrap 收到、identity 导入、cursor 更新、processed message 去重。 |
| Hermes 处理 | 按 `runId` 查 Hermes/Daemon runtime 日志 | 普通消息进入 untrusted content envelope；E2EE opaque 不进 prompt。 |
| App sync/action result | 按 `runId` 查 Daemon outbound 或 App event | `awiki.message.sync.v1` / `awiki.app.action.result.v1` 返回 App。 |

## 5. 服务端修改或部署原则

如果 E2E 编写过程中必须修改远端服务代码或部署：

1. 先在对应 step 的 Plan 中记录必要性、影响仓库、回滚策略。
2. 在本地仓库修改、验证、commit，再按项目现有部署流程同步到远端。
3. 远端临时改动必须能回溯到本地 commit 或明确标记为临时 hotfix。
4. 部署后记录服务名、部署 commit、健康检查结果和回滚命令。
5. 不要把远端真实路径、密钥和数据库连接写入仓库文档。

## 6. 脱敏规则

E2E harness 和人工采集日志都要应用同一类脱敏规则：

| 类型 | 脱敏占位 |
|---|---|
| Auth header / bearer-style token | `<REDACTED_TOKEN>` |
| JWT-like string | `<REDACTED_JWT>` |
| DID private key / PEM / seed | `<REDACTED_PRIVATE_KEY>` |
| daemon subkey private package | `<REDACTED_DAEMON_SUBKEY_PACKAGE>` |
| runtime RPC token | `<REDACTED_RUNTIME_TOKEN>` |
| OTP | `<REDACTED_OTP>` |
| 手机号 | `<REDACTED_PHONE>`，或只保留测试账号后缀。 |

## 7. Blocker 处理

| Blocker | 处理方式 |
|---|---|
| `ssh ali` 不可连接 | 记录本地命令错误；继续可独立完成的 dry-run / unit / integration；远端验证标记 blocked。 |
| 服务版本与本地分支不一致 | 记录版本差异；不要伪造通过；由用户确认是否部署。 |
| Message Service 401 / invalid delegated proof | 先确认 DID Document public method、authentication、owner DID、key fragment，再决定是测试数据问题还是服务端问题。 |
| Daemon 没有收到 bootstrap | 检查 App send result、Message Service delivery、Daemon inbox cursor，按链路二分。 |
| Hermes 未处理消息 | 检查 Daemon 是否忽略 E2EE、runtime 是否启动、prompt 是否含 untrusted envelope。 |
