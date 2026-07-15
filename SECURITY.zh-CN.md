# AWiki Me Security Policy

[English](SECURITY.md) | [简体中文](SECURITY.zh-CN.md)

## 支持范围

安全修复优先覆盖当前维护中的最新发布线和默认分支。历史预发布分支、未签名构建、个人 fork 或自行修改安全边界的版本不承诺获得同等支持。

## 报告漏洞

请不要在公开 GitHub Issue、Discussion、群聊或普通消息中披露未修复漏洞、可利用步骤、token、私钥或用户数据。

<!-- TODO(security-contact): 启用 GitHub Private Vulnerability Reporting，或填写组织正式安全邮箱/表单。 -->

推荐顺序：

1. 使用仓库的 GitHub Private Vulnerability Reporting；
2. 如果该功能尚未启用，使用 AgentConnect 公开声明的私有安全联系渠道；
3. 在收到维护者确认前，不公开技术细节。

报告建议包含：

- 受影响版本、commit 和平台；
- 复现步骤与最小 PoC；
- 影响范围；
- 是否涉及真实账号或数据；
- 建议缓解方式；
- 可安全分享的日志或截图（必须脱敏）。

## 重点安全边界

AWiki Me 不应直接持有或记录：

- DID private key；
- JWT / bearer token；
- SecretVault root key、envelope 或 raw `SecretRef`；
- Direct/Group E2EE 私有状态；
- Daemon delegated/subkey package；
- macOS/iOS/Android 签名私钥；
- 真实 OTP 和测试账号池。

每个租户必须使用不可变 Storage Scope 隔离本地数据和平台安全存储。Vault 打开或验证失败时必须 fail closed，不能生成替代 root key、回退明文或静默执行旧迁移。

## 高风险变更

以下变更需要额外安全评审和测试：

- SecretVault、Keychain/Keystore、Storage Scope；
- DID 注册、恢复、替换或 active identity；
- E2EE session/prekey/MLS；
- 租户切换与 route 变更；
- Agent 授权、controller scope 和 control payload；
- 附件下载授权与本机打开；
- Bundle ID、entitlement、签名与自动更新；
- 日志、诊断、E2E 报告和错误详情。

## 加密说明

本地 SecretVault 与安全消息能力不等于所有消息天然 E2EE。实际覆盖取决于会话类型、对端、服务端和当前发布。连接明确不支持 E2EE 的服务时，应向用户展示准确边界。

## 披露

维护者确认问题后，应协调修复、发布和公告时间。未经协调的提前公开可能使用户处于风险中，但项目不会要求报告者隐瞒已经公开或无法合理保密的事实。
