# aWiki.me 切换到 Rust IM Core SDK 计划

## 1. 目标与结论

将 `awiki-me` 当前 Dart 手写的 IM、账号、认证、群组、Profile、实时消息能力，切换到 `../awiki-cli-rs2/packages/awiki_im_core` 提供的 Rust-backed Dart SDK。

迁移结论：可以迁移，但不要直接把 SDK DTO 暴露给 UI。`awiki-me` 应保留现有 Provider / domain entity / UI 对外形状，在 data/bootstrap 层新增 SDK adapter，把 Rust SDK DTO 映射到现有 domain model。

迁移原则：

- 不重写 UI。
- 不改变现有 Provider / domain entity 对外形状。
- 在 `awiki-me` 内新增 SDK adapter，隔离 Rust SDK DTO 与 app domain model。
- 第一阶段只承诺 Android / iOS / macOS native 路径；Flutter Web 维持 analyze 通过，不承诺运行。
- 不在 app 层继续维护 raw `/im/rpc`、ANP proof、WebSocket frame、reconnect timer 等 transport 细节。
- 不覆盖 `awiki-cli-rs2` 当前未提交 SDK 相关改动；执行前必须先检查该仓库状态。

## 2. 现状与证据

### 2.1 awiki-me 当前生产路径

当前生产实现集中在：

- `lib/src/app/bootstrap.dart`
- `lib/src/domain/repositories/awiki_gateway.dart`
- `lib/src/domain/repositories/awiki_account_gateway.dart`
- `lib/src/domain/services/realtime_gateway.dart`
- `lib/src/data/gateways/awiki_anp_gateway.dart`
- `lib/src/data/services/awiki_account_service.dart`
- `lib/src/data/services/awiki_ws_realtime_gateway.dart`
- `lib/src/data/awiki_sdk/*`

当前问题：

- `AwikiAnpGateway` 手写 `/im/rpc` direct/group/inbox/history/group RPC。
- `AwikiAccountService` 手写 DID 生成、WBA auth、JWT refresh、本地凭证存储。
- `AwikiWsRealtimeGateway` 手写 WebSocket URL、Bearer header、frame 过滤、reconnect。
- app 已有一套 `lib/src/im_core/*` 抽象与 fake，但它是 app 内冻结接口，不是 `awiki_im_core` Rust SDK adapter。

### 2.2 Rust-backed Dart SDK 能力

`../awiki-cli-rs2/packages/awiki_im_core` 当前已暴露：

- Core lifecycle：`AwikiImCore.open`、`validatePaths`、`dispose`
- Identity：list/default/resolve、phone/email 注册、recover handle
- Auth：status、login、ensureSession、refreshSession
- Profile：读取/更新自己 Profile、读取公开 Profile
- Directory：resolve peer、lookup handle、relation status
- Message：sendText、inbox、history、markRead、conversations
- Group：create/join/get/list/listMembers/listMessages/leave、join code
- Realtime：capability/status/start/stop、`client.events`、`client.connectionStates`

关键 SDK 文档：

- `../awiki-cli-rs2/docs/flutter-sdk/awiki-im-core-flutter-sdk.md`
- `../awiki-cli-rs2/packages/awiki_im_core/README.md`
- `../awiki-cli-rs2/packages/awiki_im_core/lib/awiki_im_core.dart`
- `../awiki-cli-rs2/packages/awiki_im_core/lib/src/awiki_im_core_native.dart`

### 2.3 已知 SDK 差距

执行前需要确认或补齐：

- SDK 文档明确：`retryMessage` v0.1 不支持；`awiki-me` 的 retry 应先按“重新发送原消息内容”处理。
- SDK public wrapper 需要确认是否公开 `follow/unfollow`；如果只在 generated API 层存在，应先在 SDK wrapper 补公开方法，再迁移关注/取消关注功能。
- SDK public wrapper 需要确认是否公开群成员添加能力；Rust core 内部有 group member mutation，但 Dart wrapper 当前是否可用需确认。
- 附件、direct secure、group E2EE、store export/import 不作为首轮迁移阻塞项。
- Flutter Web 使用 stub，调用 native SDK 会抛 `UnsupportedError`。

## 3. 目标架构

迁移后结构：

```text
awiki-me UI / Riverpod providers
  -> existing domain repositories/services
    -> Rust SDK adapters inside awiki-me data layer
      -> package:awiki_im_core
        -> im-core-dart FRB facade
          -> Rust im-core
```

核心边界：

- UI 只看现有 app domain model：`ChatMessage`、`ConversationSummary`、`GroupSummary`、`UserProfile`、`RealtimeUpdate`。
- SDK DTO 只存在于 adapter 内部。
- app 不直接依赖 SDK generated API，优先使用 `package:awiki_im_core/awiki_im_core.dart` 公开 API。
- Rust SDK 管 identity/auth/session/store/realtime transport。
- awiki-me 只负责 app lifecycle、provider orchestration、UI cache、notification 展示。

## 4. 实施计划

### 阶段 0：执行前保护

1. 检查两个仓库状态：

```bash
cd /Users/cs/work/agents/awiki-space
git -C awiki-me status --short
git -C awiki-cli-rs2 status --short
```

2. 如果 `awiki-cli-rs2` 存在未提交变更：
   - 不格式化、不重跑大范围 codegen、不覆盖 generated 文件。
   - 只在明确必要时做最小 wrapper 补充。
   - 所有 SDK 侧改动必须单独列出。

### 阶段 1：引入 SDK 依赖

在 `awiki-me/pubspec.yaml` 增加本地 path dependency：

```yaml
dependencies:
  awiki_im_core:
    path: ../awiki-cli-rs2/packages/awiki_im_core
```

暂时保留旧依赖：

- `anp`
- `http`
- `web_socket_channel`

删除旧依赖必须等生产路径完全切走并通过测试后再做。

验证：

```bash
cd awiki-me
PUB_HOSTED_URL=https://mirrors.tuna.tsinghua.edu.cn/dart-pub flutter pub get
dart analyze
```

### 阶段 2：新增 Rust SDK runtime 管理层

新增 app 内部 runtime service，负责：

- 构造 `AwikiImCoreConfig`
- 生成 `AwikiImCorePaths`
- 打开/关闭 `AwikiImCore`
- 根据当前 identity 获取 `AwikiImClient`
- 缓存 client，避免每个 provider 重复 open
- logout / identity switch 时正确 dispose 或切换 client

路径策略：

- identity root：app support directory
- registry path：app support directory 下固定文件
- default identity path：app support directory 下固定文件
- sqlite path：app support directory 下 SDK 数据库
- cache/temp：平台 cache/temp directory

配置来源：

- `AWIKI_USER_SERVICE_URL`
- `AWIKI_MESSAGE_SERVICE_URL`
- `AWIKI_DID_DOMAIN`
- 可选 `AWIKI_ANP_SERVICE_DID`

默认值保持当前 app 行为：`https://awiki.ai` 与 `awiki.ai`。

### 阶段 3：新增 DTO mapper

新增 mapper，把 SDK DTO 转成现有 domain entity：

- SDK `Message` → app `ChatMessage`
- SDK `Conversation` → app `ConversationSummary`
- SDK `GroupSummary/GroupSnapshot` → app `GroupSummary`
- SDK `GroupMember` → app `GroupMemberSummary`
- SDK `UserProfile` → app `UserProfile`
- SDK `RelationStatus` → app `RelationshipSummary`
- SDK `RealtimeEvent` → app `RealtimeUpdate`
- SDK connection state → app `RealtimeConnectionStatus`

映射要求：

- 保持现有 direct thread ID 规则：`dm:<sorted did A>:<sorted did B>`。
- 保持 group thread ID 规则：`group:<groupId>`。
- `Message.metadata.serverSequence` 映射到 app `ChatMessage.serverSequence`。
- `Message.body.text` 映射到 app `ChatMessage.content`。
- `Message.direction` 映射到 app `isMine` 与 `MessageSendState`。
- `GroupSummary.did` 优先映射为 app `groupId`。
- SDK 错误不得泄露 token、private key、signature。

### 阶段 4：迁移账号与认证

新增 Rust SDK account adapter，实现 `AwikiAccountGateway`：

- `registerHandle` → SDK `registerHandleWithPhone`
- `registerHandleWithEmail` → SDK `registerHandleWithEmail`
- `recoverHandle` → SDK `recoverHandle`
- `listLocalCredentials` → SDK `listIdentities`
- `restoreSession/currentSession` → SDK default identity 或 app 记录的 active identity + SDK auth status/login
- `refreshSession` → SDK `auth.refreshSession`
- `loginWithLocalCredential` → SDK identity selector
- `deleteLocalCredential` → 如果 SDK 暂无删除 identity API，保留明确 unsupported 行为，不假装删除成功

兼容项：

- 如果 SDK 尚未公开 `sendOtp`、`sendEmailVerification`、`checkEmailVerified`、`lookupHandleRegistration`，这些 onboarding utility 可暂时保留旧 User Service client，但必须隔离在 account adapter 内部，并在文档中标为待 SDK 收敛。
- 如果 `currentAnpSession` 只被旧 gateway 使用，应随旧 gateway 退出生产路径；测试夹具可临时保留兼容。

注册后 Profile 处理：

- SDK `InitialProfile` 当前只包含 displayName/avatarUrl；如果 app 传入 `profileMarkdown`，注册后需要调用 SDK `profile.updateProfile` 写入 markdown。

### 阶段 5：迁移消息、群组、Profile、关系

新增 Rust SDK gateway adapter，实现 `AwikiGateway`：

- `loadCapabilities`：从 SDK capability + app feature policy 组合返回。
- `listConversations` → `client.messages.conversations`
- `fetchDmHistory` → `client.messages.history(ThreadRef.direct(peerDid))`
- `fetchGroupHistory` → `client.groups.listMessages`
- `sendTextMessage` → `client.messages.sendText`
- `markRead` → `client.messages.markRead`
- `retryMessage` → 重新调用 `sendTextMessage`，不调用 SDK retry
- `createGroup` → `client.groups.createGroup`
- `joinGroup` → `client.groups.joinGroup`
- `getGroup` → `client.groups.getGroup`
- `listGroups` → `client.groups.listGroups`
- `listGroupMembers` → `client.groups.listMembers`
- `addGroupMember` → SDK member mutation；如果 SDK wrapper 未公开，先补 SDK wrapper，不在 app 层回退手写 signed RPC
- `loadMyProfile` → `client.profile.loadMyProfile`
- `updateProfile` → `client.profile.updateProfile`
- `loadPublicProfile` → `client.profile.loadPublicProfile`
- `getRelationshipStatus` → `client.directory.relationStatus`
- `follow/unfollow` → SDK directory follow/unfollow；如果 wrapper 未公开，先补 SDK wrapper

本阶段完成后，`awiki-me` 生产路径不应再调用 `AwikiMessageClient` 或手写 `/im/rpc`。

### 阶段 6：迁移实时消息

新增 Rust SDK realtime adapter，实现 `RealtimeGateway`：

- `connect` → `client.realtime.start`
- `disconnect` → realtime session `stop`
- `connectionStatusStream` → `client.connectionStates`
- SDK `client.events` 中的 message/group event 经 mapper 转成 `Map` 或直接进入 `RealtimeUpdate` 处理链

建议后续简化：

- 当前 `RealtimeGateway` 的 `onMessage` 类型是 `Map<String, Object?>`，这是旧 raw frame 时代遗留。
- 第一阶段可保留接口以减少 UI 改动。
- 第二阶段应把 `RealtimeGateway` 改成直接输出 `Stream<RealtimeUpdate>`，彻底删除 raw map 边界。

迁移后 app 层不再关心：

- WebSocket URL
- Bearer header
- raw JSON-RPC frame
- reconnect timer
- ping/pong
- transport-level dispatch

### 阶段 7：切换 bootstrap

修改 `AppBootstrap.create()`：

- 构造 Rust SDK runtime。
- 注入新的 Rust SDK account gateway。
- 注入新的 Rust SDK awiki gateway。
- 注入新的 Rust SDK realtime gateway。
- 保持 notification、locale、update service 不变。

切换策略：

- 优先一次性切换生产 bootstrap。
- 测试中继续通过 provider override 使用 fake gateway。
- 不引入长期 feature flag，避免两套生产 IM 路径长期并存。

### 阶段 8：清理旧代码与依赖

在测试通过后：

- 删除或 test-only 隔离 `AwikiAnpGateway`
- 删除或 test-only 隔离 `AwikiMessageClient`
- 删除或 test-only 隔离 `AwikiWsRealtimeGateway`
- 删除旧 ANP proof builder
- 删除未使用依赖：`anp`、`web_socket_channel`、多余 `http`
- 更新 `README.md` 与相关 docs：说明 IM/身份/实时由 Rust-backed Dart SDK 提供

## 5. 测试计划

必须新增或更新：

- SDK mapper 单测
- Account gateway 单测
- Message gateway 单测
- Group gateway 单测
- Profile gateway 单测
- Relationship gateway 单测
- Realtime gateway 单测
- Bootstrap/provider 注入测试
- 现有 chat/group/onboarding/profile provider 回归测试

重点场景：

1. 新用户手机号注册 → 自动登录 → Profile markdown 写入。
2. 新用户邮箱注册 → 邮箱已验证 → 自动登录。
3. 已注册 handle 手机号恢复 → 当前 session 更新。
4. 本地 identity list → 切换 identity → provider session 更新。
5. DM 发送、历史读取、会话列表更新。
6. Group 创建、加入、消息发送、成员列表读取、添加成员。
7. Profile 自己读取/更新，公开 Profile 按 handle/DID 查询。
8. follow/unfollow/status 完整闭环。
9. Realtime connect → 收到 message event → UI conversation/chat 更新。
10. Realtime reconnect / refresh session 不再依赖 app 自己的 WebSocket token header。

验证命令：

```bash
cd awiki-me
PUB_HOSTED_URL=https://mirrors.tuna.tsinghua.edu.cn/dart-pub flutter pub get
dart analyze
flutter test
```

可选 SDK 侧验证：

```bash
cd ../awiki-cli-rs2
scripts/flutter/codegen-check.sh
cd packages/awiki_im_core
flutter test
```

如改动了 Rust facade 或 generated API，还需要运行对应 Rust 测试：

```bash
cd ../awiki-cli-rs2
cargo test -p im-core-dart
cargo test -p im-core
```

## 6. 验收标准

迁移完成后必须满足：

- `awiki-me` 生产路径不再直接调用 `/im/rpc`。
- `awiki-me` 生产路径不再自己构造 ANP origin proof。
- `awiki-me` 生产路径不再自己维护 raw WebSocket。
- 登录、注册、恢复、Profile、好友关系、会话列表、DM 发送、群消息、群成员、实时状态都通过 Rust SDK adapter 工作。
- `retryMessage` 不调用 SDK unsupported retry，而是按 app 语义重新发送原内容。
- SDK DTO 不泄露到 presentation 层。
- `dart analyze` 通过。
- `flutter test` 通过。
- macOS native 至少完成一次 app 启动和 SDK open smoke test。
- Web 不作为首轮运行目标，但不能破坏 analyze。

## 7. 风险与缓解

| 风险 | 影响 | 缓解 |
| --- | --- | --- |
| SDK native library packaging 失败 | iOS/macOS/Android app 启动或 SDK open 失败 | 阶段 1 后尽早做 macOS smoke test，再扩到 iOS/Android |
| SDK wrapper 缺 `follow/unfollow` | 好友关系无法完全迁移 | 先补 SDK public wrapper，再切 app 关系功能 |
| SDK wrapper 缺 group add member | 群成员添加无法迁移 | 先补 SDK Dart bridge；不要回退 app 手写 signed RPC |
| SDK identity store 与当前 ZIP 凭证不兼容 | 导入/导出功能受影响 | 首轮标记 unsupported 或保留独立兼容设计，后续补 SDK import/export |
| Flutter Web 不支持 native SDK | Web 运行不可用 | 首轮明确 native-only；Web 只保证 analyze |
| `awiki-cli-rs2` 有未提交改动 | 易覆盖他人工作 | 执行前检查 status，只做最小必要改动 |
| 两套 IM 路径长期并存 | 行为分叉、维护成本高 | 迁移完成后删除旧 production path，只保留 test fixture |

## 8. 推荐执行顺序

1. 引入 SDK dependency。
2. 新增 SDK runtime + mapper。
3. 先迁移 Profile 和 Directory，因为风险低、UI 影响小。
4. 再迁移 Message 和 Group。
5. 再迁移 Account/Auth。
6. 最后迁移 Realtime。
7. 全部测试通过后删除旧 ANP/HTTP/WebSocket 实现。
8. 做 macOS native smoke test。
9. 再进入 iOS/Android packaging 验证。

## 9. 可交给 goal 的执行摘要

目标：在 `awiki-me` 中新增 Rust SDK adapter 层，切换生产 bootstrap，使 IM、账号、认证、群组、Profile、关系、实时消息走 `../awiki-cli-rs2/packages/awiki_im_core`。

硬约束：

- 不改 UI contract。
- 不把 SDK DTO 暴露到 presentation 层。
- 不覆盖 `awiki-cli-rs2` 未提交改动。
- 不长期保留两套生产 IM 路径。
- Web native SDK unsupported 不作为首轮阻塞。

完成定义：

- `awiki-me` production path 不再手写 `/im/rpc`、ANP proof、raw WebSocket。
- `dart analyze` 与 `flutter test` 通过。
- macOS native SDK open smoke test 通过。
