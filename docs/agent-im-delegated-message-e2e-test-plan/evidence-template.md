# Agent IM E2E 证据模板

状态：draft  
主方案：[README.md](README.md)

> 复制本模板到本地 report 或执行台账中使用。提交仓库前必须确认已脱敏。

## 1. Run 信息

| 字段 | 值 |
|---|---|
| runId |  |
| 日期 |  |
| 执行人 / Agent |  |
| 分支 |  |
| App 平台 | macOS / Linux / iOS / Android |
| Backend | `https://awiki.info` |
| Remote SSH | `ssh ali` |
| App 用户 Handle / DID | 只记录测试 handle 或脱敏 DID |
| CLI Peer Handle / DID | 只记录测试 handle 或脱敏 DID |

## 2. 本地命令

| 阶段 | 命令 | 结果 | 证据文件 |
|---|---|---|---|
| analyze |  |  |  |
| unit |  |  |  |
| integration smoke |  |  |  |
| desktop E2E |  |  |  |
| redaction scan |  |  |  |

## 3. 远端观测

| 服务 | 过滤条件 | 结果摘要 | 脱敏证据 |
|---|---|---|---|
| User Service | `runId` / DID |  |  |
| Message Service | `runId` / conversation |  |  |
| Daemon | `runId` / delegated identity |  |  |
| Hermes | `runId` / prompt id |  |  |

## 4. 场景结果

| 场景 ID | 结果 | 通过证据 | 失败 / 跳过原因 |
|---|---|---|---|
| AIM-E2E-001 | pass / fail / skipped |  |  |
| AIM-E2E-002 | pass / fail / skipped |  |  |
| AIM-E2E-003 | pass / fail / skipped |  |  |
| AIM-E2E-004 | pass / fail / skipped |  |  |
| AIM-E2E-005 | pass / fail / skipped |  |  |
| AIM-E2E-006 | pass / fail / skipped |  |  |
| AIM-E2E-007 | pass / fail / skipped |  |  |

## 5. 安全检查

- [ ] 本地 report 无 JWT / token / OTP / private key。
- [ ] CLI workspace 无 private package 明文泄漏到日志。
- [ ] App log 无 raw private package。
- [ ] 远端日志证据已脱敏。
- [ ] E2EE opaque 消息没有进入 Hermes prompt。

## 6. 结论

- 通过项：
- 失败项：
- 跳过项及原因：
- 剩余风险：
- 下一步：
