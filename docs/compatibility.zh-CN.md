# AWiki Me 平台与服务兼容性

[English](compatibility.md) | [简体中文](compatibility.zh-CN.md)

最后整理日期：2026-07-14。对外发布时，应补充实际版本/commit 与最近验证日期。

## 1. 平台矩阵

| 平台 | SDK/工程状态 | 当前产品状态 | 发布前还需要什么 |
| --- | --- | --- | --- |
| macOS arm64 | Flutter App + native SDK | 重点支持 | 正式签名、DMG、Keychain restart Gate、真实消息流程 |
| macOS x64 | Flutter App + native SDK | 重点支持 | 正式签名、DMG、Intel 设备或可信构建验证 |
| Android arm64 | Flutter App + native SDK | 重点支持 | Release APK 签名、真机/模拟器启动与消息流程 |
| iOS | Flutter 工程 + native SDK | 开发目标 | 签名、真机、后台、网络、安全存储和分发验证 |
| Web | UI 工程存在，Core 为 stub | 不支持 | 需要真正的 Web Core/存储/加密/同步实现后再声明 |
| Linux | `awiki_im_core` 支持 native Linux | AWiki Me 未声明为产品目标 | App runner、打包、UX、通知与安全存储验证 |
| Windows | 当前未列为支持平台 | 不支持/未规划声明 | 需要 App runner、SDK、打包和完整验证 |

## 2. 服务矩阵

| 服务类型 | 登录/身份 | Direct | Group | Attachment | Agent/Daemon | E2EE |
| --- | --- | --- | --- | --- | --- | --- |
| AWiki 默认/托管服务 | 主要路径 | 主要路径 | 主要路径 | 主要路径 | 主要路径 | 按消息类型和服务能力验证 |
| `awiki-open-server` | 基础兼容目标 | 明文 Direct | 参与者群能力 | 本地对象能力 | 非 allowlist 域名默认关闭 | 不支持 |
| 其他兼容 AWiki 服务 | 逐项验证 | 逐项验证 | 逐项验证 | 逐项验证 | 受 realm allowlist 限制 | 逐项验证 |
| 纯 ANP 远端 | 仅实现范围内 | 取决于服务描述和互通方法 | 不等于完整 federation | 取决于对象协议 | 不自动获得 AWiki Agent API | 不可推断 |

## 3. 自托管域名的 Agent 边界

AWiki Me 当前只对以下精确 realm 启用 Agent 与 Daemon 功能：

```text
awiki.ai
awiki.info
anpclaw.com
```

启用条件包括：

- backend 是对应 hostname 的 HTTPS origin；
- DID host 与 hostname 完全一致；
- realm 位于内置 allowlist。

其他租户应：

- 继续允许经过验证的基础身份/消息路径；
- 在 Agent 页面展示“不支持”状态；
- 不调用 Agent 后端 API；
- 不通过修改 UI 文案伪装成完整兼容。

如果希望 AWiki Open Server 支持完整 Agent Console，需要先设计可验证的 realm binding 或公开扩展机制，而不是简单放宽 allowlist。

## 4. 加密能力说明

不要在 README 使用“所有消息默认端到端加密”这类无条件描述。

准确判断需要同时考虑：

1. Direct 或 Group；
2. 文本或附件；
3. 当前 `awiki-im-core` 能力；
4. 对端客户端能力；
5. 服务端是否保留/转发所需协议形状；
6. 本地 SecretVault 和身份状态；
7. 当前发布是否完成真实 E2E 验证。

当前可安全公开的表述是：

> AWiki Me 将身份密钥和安全消息状态交由共享 IM Core 与 SecretVault 管理；具体 E2EE 覆盖范围依赖会话类型、对端和服务能力。连接 `awiki-open-server` 时，消息不是端到端加密。

## 5. ANP 支持边界

AWiki Me 当前聚焦：

- `did:wba` 身份与 DID-WBA 认证；
- `ANPMessageService` 端点；
- Direct/Group 消息、本地投影、未读、read ack、realtime hint 与可靠 sync；
- 附件/Object Transfer 方向；
- 群消息 Mention；
- Agent/Daemon/Message Agent 产品入口。

不应宣称一次覆盖：

- 所有 ANP 应用协议；
- 完整跨域 federation；
- AP2 支付；
- 任意服务端上的完整 Group E2EE；
- 任意域名上的 AWiki Agent Runtime 管理。

## 6. 发布兼容记录模板

```text
验证日期：YYYY-MM-DD
AWiki Me：<version + commit>
awiki_im_core：<version + commit>
awiki-im-core：<version + commit>
服务端：<name + version + domain>
平台：<OS + arch + version>

已验证：
- registration/login
- direct send/receive/history
- unread/read
- group create/join/send
- attachment send/download/open
- contact/follow
- Agent inventory/status
- secure direct/group（如适用）

未验证：
- ...
```
