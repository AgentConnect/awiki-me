# awiki-me IM 接入新版 ANP Dart SDK 与 User/Message Service 方案

## 1. 背景

`awiki-me` 是一个移动端 Flutter/Dart App，目标是基于 ANP 协议实现 IM 接入。相关协议与参考实现包括：

- DID-WBA 方法规范：`AgentNetworkProtocol/chinese/03-did-wba方法规范.md`
- ANP message 相关规范：`AgentNetworkProtocol/chinese/message/*`
- ANP Dart SDK：`anp/dart`
- 新版 Go CLI 实现：`awiki-cli`

现在服务端已经重构，IM 接入不再使用旧的混合 message/group RPC，而是使用新版 user service 和 message service。`awiki-cli` 已经基于新版 Go SDK 和最新 API 完成接入，因此 `awiki-me` 的迁移应以 `awiki-cli` 的 wire behavior 为主要参考，同时在 Dart 侧使用 `anp/dart` 提供的 DID-WBA、key、proof 等协议能力。

本方案只描述设计和实施路径，不直接实现代码。

## 2. 当前 awiki-me 实现判断

`awiki-me` 当前已经有较清晰的应用层封装：

- 领域接口：`lib/src/domain/repositories/awiki_gateway.dart`
- 当前实现：`lib/src/data/gateways/awiki_rpc_gateway.dart`
- 实时网关：`lib/src/data/services/awiki_ws_realtime_gateway.dart`
- 本地缓存：`lib/src/data/services/awiki_local_cache.dart`
- App 注入点：`lib/src/app/bootstrap.dart`

其中 `AwikiGateway` 是合理的 app 侧边界。页面和 provider 基本通过 `AwikiGateway` 访问 IM、profile、relationship、group 等能力，因此迁移时不应该让 UI 层理解新版 ANP wire schema，也不应该大面积改页面。

当前 `AwikiRpcGateway` 仍然直接拼旧 RPC：

- 私聊消息：`/message/rpc`
- 群组消息：`/group/rpc`
- 用户服务：`/user-service/*/rpc`
- WebSocket：`/message/ws`

旧消息方法包括：

- `send`
- `get_history`
- `get_inbox`
- `mark_read`
- `post_message`
- `list_messages`
- `create`
- `join`
- `list_members`

这些方法已经和新版 message service 的接口不一致。

## 3. 是否已有可替换 SDK

结论：`awiki-me` 里有应用层 gateway 封装，但没有可直接替换为新版 user service/message service 的 Dart 业务 SDK。

`anp/dart` 是独立 Dart SDK，但它目前更偏底层协议能力，导出内容包括：

- `keys`
- `authentication`
- `proof`
- `wns`
- `codec`

它可以用于 DID-WBA、key material、HTTP signature、origin proof 等能力，但不包含 awiki user service 或 message service 的高层业务 client。

因此推荐做法是：

1. 保留 `AwikiGateway` 作为 app 领域接口。
2. 在 `awiki-me` 内封装一个内部 Dart SDK/adapter。
3. 内部 Dart SDK 使用 `anp/dart` 完成协议签名和 DID-WBA 相关能力。
4. 内部 Dart SDK 参考 `awiki-cli` 实现新版 user service/message service 的 HTTP RPC、WebSocket、wire mapper。
5. 用新的 `AwikiAnpGateway` 替换当前 `AwikiRpcGateway` 的默认注入。

## 4. 目标架构

新增内部模块：

```text
lib/src/data/awiki_sdk/
  awiki_service_client.dart
  awiki_user_client.dart
  awiki_message_client.dart
  awiki_anp_proof_builder.dart
  awiki_anp_session.dart
  awiki_wire_mapper.dart
  awiki_service_error.dart
```

新增 gateway：

```text
lib/src/data/gateways/awiki_anp_gateway.dart
```

分层职责：

- `AwikiGateway`：保持现有 app 领域接口，页面层不变。
- `AwikiAnpGateway`：实现 `AwikiGateway`，组合 user client、message client、本地 cache、credential archive、secure storage。
- `AwikiServiceClient`：统一 JSON-RPC、REST、超时、Authorization、错误处理。
- `AwikiUserClient`：封装 user service。
- `AwikiMessageClient`：封装 message service `/im/rpc` 与 `/im/ws`。
- `AwikiAnpProofBuilder`：使用 `anp/dart` 生成 ANP origin proof。
- `AwikiWireMapper`：把新版 wire response 映射为现有领域实体。

`AwikiAnpGateway` 应复用现有组件：

- `AwikiLocalCache`
- `FlutterSecureStorage`
- `CredentialArchiveService`
- `DocumentPickerService`
- `DidRegistrationFacade`
- `DartDidRegistrationFacade`

身份格式约束：

- 新版 IM 写操作只支持 e1 DID 身份。
- 移动端注册、恢复登录签名和新版 IM 写操作统一走 `DartDidRegistrationFacade` + `anp/dart`，默认生成 `did:wba:<domain>:<handle>:e1_<fingerprint>`。
- K1 旧身份不做兼容签名，也不在移动端新增 K1 适配层。
- 如果本地存在 K1 credential，需要先通过账号迁移或重新签发得到 e1 DID 后再使用新版 IM。

## 5. 依赖与版本策略

在 `awiki-me/pubspec.yaml` 中依赖已发布的 Dart SDK：

```yaml
dependencies:
  anp: ^0.8.7
```

需要注意 `anp` Dart SDK 当前 Dart SDK constraint 是：

```yaml
environment:
  sdk: ^3.8.0
```

而 `awiki-me` 当前是：

```yaml
environment:
  sdk: ">=3.5.0 <4.0.0"
  flutter: ">=3.24.0"
```

实施时需要先确认当前 Flutter SDK 是否支持 Dart 3.8。如果支持，推荐把 `awiki-me` 的 Dart SDK 下限调整为 `>=3.8.0 <4.0.0`。不推荐复制 `anp/dart` 源码到 `awiki-me`，避免后续 SDK 更新困难。

## 6. 新版 Message Service 接入

以 `awiki-cli/internal/message` 当前实现为基准。

新版端点：

- HTTP RPC：`/im/rpc`
- WebSocket：`/im/ws`

环境变量：

- `AWIKI_MESSAGE_SERVICE_URL`
- `AWIKI_WS_URL` 可选；未配置时从 `AWIKI_MESSAGE_SERVICE_URL` 推导 `ws://` 或 `wss://`

JSON-RPC 请求格式：

```json
{
  "jsonrpc": "2.0",
  "method": "direct.send",
  "params": {
    "meta": {},
    "auth": {},
    "body": {}
  },
  "id": "req-1"
}
```

### 6.1 私聊接口映射

| awiki-me 当前能力 | 旧实现 | 新实现 |
| --- | --- | --- |
| 发送私聊 | `/message/rpc` + `send` | `/im/rpc` + `direct.send` |
| 拉私聊历史 | `/message/rpc` + `get_history` | `/im/rpc` + `direct.get_history` |
| 会话/inbox | `/message/rpc` + `get_inbox` | `/im/rpc` + `inbox.get` |
| 标记已读 | `/message/rpc` + `mark_read` | `/im/rpc` + `inbox.mark_read` |

私聊发送请求规则：

- method：`direct.send`
- `meta.anp_version`：`1.0`
- `meta.profile`：`anp.direct.base.v1`
- `meta.security_profile`：`transport-protected`
- `meta.sender_did`：当前用户 DID
- `meta.target.kind`：`agent`
- `meta.target.did`：目标 DID
- `meta.operation_id`：`op-` 前缀
- `meta.message_id`：`msg-` 前缀
- `meta.created_at`：UTC RFC3339
- `meta.content_type`：默认 `text/plain`
- `body.text`：消息正文
- `auth.scheme`：`anp-rfc9421-origin-proof-v1`
- 发送方 DID 必须是 e1 格式；K1 旧身份应在发起请求前直接失败。

### 6.2 群组接口映射

| awiki-me 当前能力 | 旧实现 | 新实现 |
| --- | --- | --- |
| 创建群组 | `/group/rpc` + `create` | `/im/rpc` + `group.create` |
| 发送群消息 | `/group/rpc` + `post_message` | `/im/rpc` + `group.send` |
| 获取群详情 | `/group/rpc` + `get` | `/im/rpc` + `group.get` 或 `group.get_info` |
| 群成员 | `/group/rpc` + `list_members` | `/im/rpc` + `group.list_members` |
| 群消息历史 | `/group/rpc` + `list_messages` | `/im/rpc` + `group.list_messages` |
| 加群 | `/group/rpc` + `join` | `/im/rpc` + `group.join` |

群组发送请求规则：

- method：`group.send`
- `meta.anp_version`：`1.0`
- `meta.profile`：`anp.group.base.v1`
- `meta.security_profile`：`transport-protected`
- `meta.sender_did`：当前用户 DID
- `meta.target.kind`：`group`
- `meta.target.did`：群 DID
- `meta.operation_id`：`op-` 前缀
- `meta.message_id`：`msg-` 前缀
- `meta.created_at`：UTC RFC3339
- `meta.content_type`：默认 `text/plain`
- `body.text`：消息正文
- `auth.scheme`：`anp-rfc9421-origin-proof-v1`
- 发送方 DID 必须是 e1 格式；K1 旧身份应在发起请求前直接失败。

群组创建请求规则：

- method：`group.create`
- `meta.profile`：`anp.group.base.v1`
- `meta.target.kind`：`service`
- `meta.target.did`：message service DID
- `body.group_profile`：群资料
- `body.group_policy`：群策略
- 写操作需要 `auth.origin_proof`

### 6.3 查询接口规则

查询类接口不生成 origin proof，按 `awiki-cli` 当前行为构造 `meta/body`：

- `inbox.get`：`profile = anp.inbox.local.v1`
- `direct.get_history`：`profile = anp.direct.local.v1`
- `group.get`：`profile = anp.group.local.v1`
- `group.list_members`：`profile = anp.group.local.v1`
- `group.list_messages`：`profile = anp.group.local.v1`

## 7. ANP Dart SDK 使用方式

`AwikiAnpProofBuilder` 统一负责新版 ANP 写操作的 proof 生成，不允许在 gateway、provider 或 UI 层散落签名逻辑。

输入：

- RPC method
- `meta`
- `body`
- 当前 DID
- DID Document
- authentication verification method id
- private key PEM 或等价 key material

输出：

```json
{
  "scheme": "anp-rfc9421-origin-proof-v1",
  "origin_proof": {
    "contentDigest": "...",
    "signatureInput": "...",
    "signature": "..."
  }
}
```

proof 固定策略：

- scheme：`anp-rfc9421-origin-proof-v1`
- ANP version：`1.0`
- security profile：`transport-protected`
- operation id 前缀：`op-`
- message id 前缀：`msg-`
- 时间：UTC RFC3339
- signer DID：只接受 e1 格式，K1 不进入 proof 生成流程。

如果 `anp/dart` 当前 proof API 与 `awiki-cli` 的 Go SDK 输出存在细微差异，应在 `AwikiAnpProofBuilder` 内做薄适配，并以 `awiki-cli/internal/message/proof.go` 的 wire behavior 为准。

## 8. User Service 接入

`AwikiUserClient` 封装当前移动端已使用的 user service 能力。

环境变量：

- `AWIKI_USER_SERVICE_URL`

需要覆盖的能力：

- 短信 OTP：`sendOtp`
- 邮箱验证：`sendEmailVerification`、`checkEmailVerified`
- 注册 handle：`registerHandle`
- 邮箱注册 handle：`registerHandleWithEmail`
- 恢复 handle：`recoverHandle`
- session restore / verify / refresh
- 当前用户 profile：`loadMyProfile`
- 更新 profile：`updateProfile`
- 公共 profile：`loadPublicProfile`
- DID/handle resolve
- 关注关系：`follow`、`unfollow`、`listFollowers`、`listFollowing`、`getRelationshipStatus`

策略：

- `awiki-cli/internal/identity/client.go` 已覆盖的 user service endpoint 和鉴权方式，以 CLI 为准。
- CLI 未覆盖但 `awiki-me` 已有的能力，以当前 `AwikiRpcGateway` 的外部行为为准迁移到底层 client。
- session token 仍存 `FlutterSecureStorage`。
- credential archive/import/export 继续复用现有 `CredentialArchiveService`。

## 9. Gateway 切换与回滚

新增：

```dart
class AwikiAnpGateway implements AwikiGateway
```

保留：

```dart
class AwikiRpcGateway implements AwikiGateway
```

`AppBootstrap.create()` 默认切换到新版 gateway：

```dart
final gateway = AwikiAnpGateway.fromEnvironment(...);
```

为了降低服务端联调风险，增加编译期开关：

```dart
const useLegacyRpc = bool.fromEnvironment(
  'AWIKI_USE_LEGACY_RPC',
  defaultValue: false,
);
```

行为：

- `AWIKI_USE_LEGACY_RPC=false`：默认使用 `AwikiAnpGateway`
- `AWIKI_USE_LEGACY_RPC=true`：回退到 `AwikiRpcGateway`

这样可以在不改 UI 的情况下快速回滚。回滚开关只用于服务端联调或旧账号过渡，不代表新版 IM 支持 K1；K1 credential 仍需要迁移或重新签发为 e1 后再进入新版 IM。

## 10. Realtime / WebSocket 迁移

当前 `AwikiWsRealtimeGateway` 使用 `/message/ws`，需要迁移到新版 `/im/ws`。

URL 规则：

- 如果配置了 `AWIKI_WS_URL`，优先使用。
- 如果没有配置，从 `AWIKI_MESSAGE_SERVICE_URL` 推导：
  - `https` -> `wss`
  - `http` -> `ws`
  - path：`/im/ws`

鉴权：

- 第一阶段沿用当前 token query 参数方式：`?token=<jwt>`。
- 如果服务端新版要求 header 或 subprotocol 鉴权，只集中修改 `AwikiWsRealtimeGateway`。

事件处理：

- 新版事件 envelope 在 realtime gateway 内归一化。
- 输出仍调用现有 `RealtimeMessageHandler`。
- 新事件继续进入 `AwikiGateway.consumeRealtimeEvent()`。
- gateway 负责映射为 `RealtimeUpdate` 并写入本地 cache。

需要兼容的事件：

- 私聊新消息
- 群组新消息
- inbox 更新
- 已读状态更新
- 连接断开后的重连

重连策略保持当前实现：

- 初始 1 秒
- 指数退避
- 最大 30 秒

## 11. 数据映射与本地缓存

保持现有领域实体不变：

- `SessionIdentity`
- `ChatMessage`
- `ConversationSummary`
- `GroupSummary`
- `GroupMemberSummary`
- `RelationshipSummary`
- `UserProfile`
- `RealtimeUpdate`

新增 `AwikiWireMapper` 负责兼容新版 wire schema：

- message id：兼容 `message_id`、`id`
- sender：兼容 `sender_did`、`from`
- receiver：兼容 `target_did`、`receiver_did`、`peer_did`
- group：兼容 `group_did`、`group_id`
- created time：兼容 `created_at`、`accepted_at`
- sequence：兼容 `seq`、`server_sequence`、`group_event_seq`
- content：兼容 `text`、`body.text`、`content.text`

thread id 规则保持当前 UI 兼容：

- 私聊：继续使用当前 owner DID + peer DID 规则生成稳定 thread id。
- 群聊：继续使用 `group:<groupDid>`。

缓存策略保持当前行为：

- 拉历史成功后写入 `AwikiLocalCache`。
- 拉历史失败时，如果本地有缓存，则返回缓存。
- 发送消息时先生成本地 sending 状态。
- 发送成功后回填 remote id、accepted time、sequence，并标记 sent。
- 发送失败保留 failed 状态，允许 `retryMessage()` 复用原消息内容重发。
- `markRead()` 使用 message service 返回或本地 conversation 中的 message ids，不再依赖旧 thread id 直接标记。

## 12. 非目标范围

第一阶段不做：

- 不实现端到端加密，`E2eeCapability.supported` 继续为 `false`。
- 不接入附件能力，即使 `awiki-cli` 已有 attachment flow。
- 不重构 UI 页面。
- 不删除旧 `AwikiRpcGateway`。
- 不删除现有 Python 脚本。
- 不修改 ANP Dart SDK 本身，除非发现 SDK 缺少必要公开导出且无法通过公开 API 完成 proof 生成。
- 不兼容 K1 身份格式；新版 IM 写操作只支持 e1 DID。

## 13. 实施步骤

1. 增加已发布的 `anp` SDK dependency，并确认 Flutter/Dart SDK 版本是否满足 Dart 3.8。
2. 新增 `awiki_sdk` 内部模块，实现 service client、user client、message client、proof builder、mapper、error 类型。
3. 新增 message wire 单元测试，对齐 `awiki-cli` 的 `/im/rpc`、`direct.send`、`inbox.get`、`group.send` 等请求结构。
4. 新增 `AwikiAnpGateway implements AwikiGateway`，先覆盖私聊、inbox、历史、mark read。
5. 迁移群组 create/join/get/list members/list messages/send。
6. 迁移 user service profile、relationship、handle/session 相关逻辑。
7. 更新 `AwikiWsRealtimeGateway` 到 `/im/ws`。
8. 在 `AppBootstrap` 增加 `AWIKI_USE_LEGACY_RPC` 回滚开关，并默认启用新版 gateway。
9. 跑完整测试与静态检查。
10. 服务端联调通过后，再评估是否清理旧 RPC 路径。

## 14. 测试计划

### 14.1 Proof 测试

- 注册 facade 生成 e1 DID、Ed25519/Multikey key-1、`DataIntegrityProof` + `eddsa-jcs-2022`。
- DIDWba 恢复登录 header 只接受 e1 DID。
- 私聊 payload 能生成 `anp-rfc9421-origin-proof-v1`。
- 群聊 payload 能生成 `anp-rfc9421-origin-proof-v1`。
- 缺 DID Document 时返回明确错误。
- 缺 private key 时返回明确错误。
- 非 e1 DID 发起写操作时，在本地返回明确错误，不发送 HTTP 请求。

### 14.2 Message client 测试

- `direct.send` endpoint 是 `/im/rpc`。
- `direct.get_history` params 使用 `meta/body`。
- `inbox.get` 使用 `anp.inbox.local.v1`。
- `inbox.mark_read` 使用 message ids。
- `group.send` 使用 `anp.group.base.v1`。
- `group.create` target kind 是 `service`。

### 14.3 User client 测试

- profile get/update。
- public profile resolve。
- follow/unfollow/list/status。
- session verify/refresh。
- email verification。
- OTP send。

### 14.4 Mapper 测试

- 新版私聊消息映射为 `ChatMessage`。
- 新版群消息映射为 `ChatMessage`。
- 新版 inbox 映射为 `ConversationSummary`。
- 字段别名兼容。

### 14.5 Gateway 测试

- 发送成功写 cache。
- 发送失败保留 failed 状态。
- 拉历史失败走 cache fallback。
- retry message 使用新版 send。
- mark read 调用 `inbox.mark_read`。

### 14.6 WebSocket 测试

- 默认 URL 从 `AWIKI_MESSAGE_SERVICE_URL` 推导为 `/im/ws`。
- `AWIKI_WS_URL` 覆盖默认值。
- 新消息事件归一化后进入 `consumeRealtimeEvent`。
- 断线后按现有退避策略重连。

### 14.7 回归测试

- `flutter test`
- `dart analyze`
- Android smoke build
- iOS smoke build

## 15. 验收标准

实现完成后应满足：

- `awiki-me` 默认使用 `anp/dart` + 新 user/message service。
- 新版 IM 写操作只支持 e1 DID；K1 credential 必须迁移或重新签发。
- 私聊发送、历史、会话列表、已读可用。
- 群组创建、加入、群详情、成员、消息历史、群消息发送可用。
- profile 与 relationship 功能保持原有页面行为。
- WebSocket 连接新版 `/im/ws`，新消息能进入本地会话。
- 本地缓存 fallback 行为与当前 app 一致。
- `AWIKI_USE_LEGACY_RPC=true` 时可以回退旧实现。
- 页面层不需要理解新版 ANP wire schema。
- 测试覆盖新版 wire payload、proof、mapper、gateway 行为。

## 16. 默认假设

- `awiki-me/docs` 用于保存本方案文档。
- `awiki-me` 依赖 pub.dev 上发布的 `anp` Dart SDK，版本号与其他语言 SDK 保持一致。
- message service 新版 API 以 `awiki-cli/internal/message` 当前实现为准。
- user service 新版 API 以 `awiki-cli/internal/identity` 当前实现为准。
- 第一阶段只迁移移动端现有 IM 能力，不扩大到附件和 E2EE。
- 第一阶段不兼容 K1，只支持 e1 DID 身份。
- 服务端默认 base URL 继续使用：
  - `AWIKI_USER_SERVICE_URL=https://awiki.ai`
  - `AWIKI_MESSAGE_SERVICE_URL=https://awiki.ai`
- 如果 `anp/dart` 的 proof API 与 Go SDK wire 输出有差异，在 `AwikiAnpProofBuilder` 内兼容，不把差异扩散到 gateway 或 UI。
