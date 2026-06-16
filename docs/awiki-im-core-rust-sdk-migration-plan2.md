# aWiki-me 与 IM Core SDK 连接开发计划（Codex 执行版）

## 0. 目标

将 `awiki-me` 从当前 app 侧手写 IM/账号/认证/群组/实时传输实现，迁移为以 `awiki-cli-rs2/packages/awiki_im_core` 为底层核心能力的架构。

本计划面向 Codex 执行，目标是让 Codex 可以按阶段完成 `awiki-me` 侧开发；其中 IM Core SDK 尚未补齐的能力，在 `awiki-me` 侧先建立清晰的 application service、port、adapter 边界，不再回退到旧 app 手写 `/im/rpc`、ANP proof、raw WebSocket。IM Core 侧缺口后续由 IM Core 仓库补齐。

核心要求：

1. `awiki-me` UI 能保留就尽量保留。
2. `awiki-me` 中间层可以较大幅度重写。
3. IM Core SDK 是底层核心能力与主数据源。
4. IM Core 中不要掺杂过多 `awiki-me` 产品业务逻辑。
5. 关系系统最终升级为 IM Core 的通用协议能力；`awiki-me` 侧先按 IM Core dependency 设计，不再走旧 HTTP/ANP fallback。

---

## 1. 当前判断

### 1.1 原迁移方案的问题

原方案以“保留现有 `AwikiGateway` / `AwikiAccountGateway` contract，在 data 层新增 adapter”为主要策略。这个策略适合小规模替换底层实现，但不适合当前场景，原因是：

- 当前 `AwikiGateway` 把 Profile、Relationship、Message、Conversation、Group、Realtime event consume、local delete 混在一个大接口里。
- 当前 `AwikiAccountGateway` 仍暴露 `jwtToken`、`currentAnpSession`、ZIP 凭证导入导出等旧架构概念。
- 当前 `AwikiLocalCache` 与 IM Core SDK 自己的 SQLite 都可能保存 message/conversation/group 主数据，容易形成双主数据源。
- 当前 app realtime 仍是 raw `Map<String, Object?>` event，IM Core SDK 已经提供 typed realtime event stream。
- 关系系统会进入 IM Core 通用协议能力，因此 app 不应保留旧 User Service relationship RPC 作为生产路径。

因此本计划改为：**保留 UI，重写 application/data 中间层，建立面向 IM Core 的清晰边界。**

### 1.2 迁移后的职责边界

```text
awiki-me UI / Riverpod providers
  -> awiki-me application services
    -> awiki-me domain/app models
    -> awiki-me product local store, only UI overlay data
    -> awiki-me IM Core adapters
      -> package:awiki_im_core public API
        -> im-core-dart FRB facade
          -> Rust im-core
            -> IM Core DB / identity store / session store / transport / protocol
```

### 1.3 不再保留的旧生产能力

迁移完成后，`awiki-me` 生产路径不应继续维护：

- raw `/im/rpc` 构造。
- app 侧 ANP origin proof builder。
- app 侧 WebSocket URL、Bearer header、frame filter、reconnect timer。
- app 侧 JWT refresh / DID auth header 构造。
- app 侧 message/conversation/group 主数据 cache。
- app 侧 relationship HTTP/RPC fallback。

---

## 2. 能力归属矩阵

### 2.1 IM Core SDK 当前已有，可直接使用

| 能力 | 当前 IM Core SDK API | `awiki-me` 调用方式 |
| --- | --- | --- |
| Core lifecycle | `AwikiImCore.open`, `validatePaths`, `dispose` | `AwikiImCoreRuntime` 统一 open/close |
| Client lifecycle | `core.client(IdentitySelector)` / `client.dispose` | runtime 缓存当前 client，identity 切换时 dispose 旧 client |
| Identity list/default/resolve | `listIdentities`, `defaultIdentity`, `resolveIdentity` | `AppSessionService` 获取本地身份与当前身份 |
| 手机注册 | `registerHandleWithPhone` | `OnboardingService.registerWithPhone` |
| 邮箱注册 | `registerHandleWithEmail` | `OnboardingService.registerWithEmail` |
| handle 恢复 | `recoverHandle` | `OnboardingService.recoverHandle` |
| Auth status/login/ensure/refresh | `client.auth.status/login/ensureSession/refreshSession` | `AppSessionService`，UI 不持有 JWT |
| Profile | `client.profile.loadMyProfile/updateProfile/loadPublicProfile` | `ProfileApplicationService` |
| Directory resolve | `client.directory.resolvePeer/lookupHandle/relationStatus` | `DirectoryApplicationService` 与 `RelationshipApplicationService.status` |
| 关系 follow/unfollow/list | `client.directory.follow/unfollow/listFollowers/listFollowing` | `RelationshipApplicationService` 通过 `AwikiImCoreRelationshipAdapter` 直接调用 SDK |
| 发文本消息 | `client.messages.sendText` | `MessagingService.sendText` |
| inbox/history | `client.messages.inbox/history` | `ConversationService` / `MessagingService` |
| markRead by message IDs | `client.messages.markRead(List<String>)` | 不直接用于首轮 thread read；当前 Message DTO 不暴露 read-state，`awiki-me` 不从 history 猜 unread IDs |
| 会话列表 | `client.messages.conversations` | `ConversationService.listConversations` |
| 群创建/加入/读取/列表/成员列表/消息列表/退出 | `client.groups.createGroup/joinGroup/getGroup/listGroups/listMembers/listMessages/leaveGroup` | `GroupApplicationService` |
| 实时能力/status/start/stop | `client.realtime.capability/status/start/stop` | `RealtimeApplicationService` |
| 实时事件流 | `client.events`, `client.connectionStates` | typed event mapper，进入 UI update pipeline |

### 2.2 应补进 IM Core SDK 的核心能力

这些能力属于 IM Core 的通用协议能力或核心本地状态能力，不应在 `awiki-me` 内手写生产 fallback。

| 能力 | 当前状态 | 归属判断 | `awiki-me` 侧当前开发方式 |
| --- | --- | --- | --- |
| group add/remove member Dart facade | Rust `im-core` 有 `add_member/remove_member`，但 Dart facade/public wrapper 未暴露 | IM Core group mutation 能力 | 先写 `GroupCorePort.addMember/removeMember` 边界；SDK 补齐后启用 |
| `markThreadRead(ThreadRef)` | 当前 SDK 只有 `markRead(messageIds)`，`Message` DTO 不暴露 read-state，无法可靠从 history 判断 unread IDs | IM Core read-state 能力 | 首轮 app 侧标为 unsupported，不做不准确的 history 适配；TODO：SDK 后续补 `markThreadRead(ThreadRef)` 或 unread message query 后再启用 |
| set default / active identity | 当前 SDK 未公开独立 API；app 多身份恢复策略未完善 | IM Core identity store 能力 + app active identity preference | 首轮只恢复 default identity；TODO：后续保存 `activeIdentityId` 并在 SDK 补 set default/active API 后完善切换 |
| identity import/export/delete/explicit local login | 当前 SDK 未公开完整能力，app 旧 ZIP 凭证语义不适用于新 identity store | IM Core identity store 能力 + app 文件选择/UX | 首轮导入、导出、删除、显式登录本地凭证均标记 unsupported 或隐藏入口；TODO：SDK 补齐后 app 负责 picker/UX，SDK 负责解析/校验/写 store/切换 |
| group join code 真实实现 | public wrapper 有 `getJoinCode/refreshJoinCode`，当前 Rust facade 返回 `None` | IM Core group invite 能力 | UI 可隐藏或显示 unsupported，SDK 后续补真实实现 |
| relationship realtime event | 当前未确认 | IM Core realtime protocol 能力 | app 侧 event mapper 预留关系事件处理分支 |

### 2.3 应留在 `awiki-me` 业务层的能力

这些能力是产品体验、UI 流程或业务 orchestration，不应放进 IM Core。

| 能力 | `awiki-me` 模块 |
| --- | --- |
| 注册/登录页面流程、验证码倒计时、邮箱验证轮询、邀请入口 | `OnboardingService` + UI controller |
| 注册后补写 profile markdown | `OnboardingService` 调用 SDK register 后，再调用 `ProfileApplicationService.updateProfile` |
| 错误文案、本地化、toast/banner | `UiFeedback` / app message layer |
| in-app banner / system notification | `NotificationFacade` 与 `RealtimeApplicationService` orchestration |
| draft / composing state | `ProductLocalStore` |
| pinned / muted / hidden thread | `ProductLocalStore` |
| 本地隐藏会话 tombstone | `ProductLocalStore` |
| 自定义会话标题、avatar seed、UI 排序偏好 | `ProductLocalStore` |
| 产品级 retry 语义 | `MessagingService.retryByResendOriginalContent`，不调用 SDK unsupported retry |
| E2EE UI 开关、产品策略展示 | `E2eeFacade` / feature policy；具体加密能力由 IM Core 后续提供 |
| app lifecycle/resume 时刷新哪些数据 | `AppRuntimeController` / application service orchestration |

---

## 3. 目标代码结构

建议新增 `lib/src/application` 与 `lib/src/data/im_core`。

```text
lib/src/application/
  app_session_service.dart
  onboarding_service.dart
  conversation_service.dart
  messaging_service.dart
  group_application_service.dart
  profile_application_service.dart
  relationship_application_service.dart
  realtime_application_service.dart
  directory_application_service.dart
  product_local_store.dart

lib/src/application/ports/
  im_core_runtime_port.dart
  message_core_port.dart
  conversation_core_port.dart
  group_core_port.dart
  profile_core_port.dart
  relationship_core_port.dart
  realtime_core_port.dart
  identity_core_port.dart

lib/src/data/im_core/
  awiki_im_core_runtime.dart
  awiki_im_core_config.dart
  awiki_im_core_paths.dart
  awiki_im_core_identity_adapter.dart
  awiki_im_core_auth_adapter.dart
  awiki_im_core_message_adapter.dart
  awiki_im_core_conversation_adapter.dart
  awiki_im_core_group_adapter.dart
  awiki_im_core_profile_adapter.dart
  awiki_im_core_relationship_adapter.dart
  awiki_im_core_realtime_adapter.dart
  awiki_im_core_mappers.dart
  pending_im_core_group_mutation_adapter.dart

lib/src/data/local/
  awiki_product_local_store.dart
  awiki_product_local_store_sqlite.dart
lib/src/application/models/
  product_local_models.dart

lib/src/data/compat/
  compat_awiki_gateway.dart
  compat_awiki_account_gateway.dart
  compat_realtime_gateway.dart
```

### 3.1 为什么需要 compat 层

为了尽量保留 UI，第一阶段不要立刻重写所有 provider。可以先保留当前 provider 对 `AwikiGateway` / `AwikiAccountGateway` / `RealtimeGateway` 的依赖，但 bootstrap 注入新的 `Compat*` 实现：

```text
current UI/provider
  -> old gateway interface
    -> compat gateway implementation
      -> new application services
        -> IM Core adapters
```

等核心迁移稳定后，再逐步把 provider 从旧大 gateway 改成 granular application service provider。

### 3.2 需要最终废弃的旧文件

迁移完成后删除或 test-only 隔离：

```text
lib/src/data/gateways/awiki_anp_gateway.dart
lib/src/data/services/awiki_account_service.dart
lib/src/data/services/awiki_ws_realtime_gateway.dart
lib/src/data/awiki_sdk/*
lib/src/domain/services/did_registration_facade.dart
lib/src/data/services/dart_did_registration_facade.dart
```

`AwikiLocalCache` 不建议继续作为 message/conversation/group 主数据 cache 使用。可以重命名/重构为 `AwikiProductLocalStore`，仅保存 UI overlay。

### 3.3 现有 `lib/src/im_core` 的迁移/废弃策略

当前仓库已经存在一套 app 内部 IM Core contract/fake：

```text
lib/src/im_core/
test/im_core/
```

这套代码是早期 Dart-only app 内部边界，不是本计划要接入的 Rust SDK package。新迁移以
`package:awiki_im_core/awiki_im_core.dart` 为唯一 SDK 入口，因此必须先处理命名与测试边界，否则后续
`lib/src/data/im_core/*`、`AwikiImClient`、`GroupSummary`、`UserProfile` 等名称会和旧内部 contract 混淆。

首轮策略：

1. **不要把旧 `lib/src/im_core` 包装成新 SDK adapter。** 它不能作为生产路径 fallback。
2. **新增代码统一使用 import alias：**

   ```dart
   import 'package:awiki_im_core/awiki_im_core.dart' as core;
   ```

   app/domain model 继续使用现有 `ChatMessage`、`ConversationSummary`、`GroupSummary` 等 UI-facing model；SDK DTO 在 adapter/mapper 内部使用 `core.*`，不得裸名扩散到 UI/provider。
3. **迁移前先更新或隔离旧 `test/im_core/im_core_boundary_test.dart` 的 Phase 1 scope guard。**
   该 guard 目前会阻止 production wiring import `*/im_core`；进入 bootstrap cutover 前必须改成：
   - 允许 `lib/src/data/im_core/*` 作为 Rust SDK adapter 层；
   - 继续禁止 `lib/src/presentation/*` 直接 import SDK 或 adapter；
   - 继续禁止旧 raw `/im/rpc`、ANP proof、raw WebSocket fallback 进入新路径。
4. **旧 `lib/src/im_core` 最终二选一：**
   - 推荐：迁移完成后删除旧内部 contract/fake 与对应测试；
   - 过渡：重命名到 `lib/src/legacy_im_core_contract/` 并标记 test-only，所有 production import 禁止引用。

验收补充：

- repo 内只有 `lib/src/data/im_core/*` 直接 import `package:awiki_im_core/awiki_im_core.dart`。
- `lib/src/presentation/*`、`lib/src/domain/*` 不直接 import `package:awiki_im_core`。
- 旧 `lib/src/im_core` 不再出现在 production dependency path 中。

---

## 4. 新的 app session 模型

### 4.1 废弃 UI 持有 JWT

当前 `SessionIdentity` 带 `jwtToken`，这是旧 app 手写 HTTP/WebSocket 架构的遗留。迁移后 UI 不应知道 JWT。

新增：

```dart
class AppSession {
  const AppSession({
    required this.did,
    required this.identityId,
    required this.displayName,
    this.handle,
    this.localAlias,
    this.authenticated = false,
    this.expiresAt,
  });

  final String did;
  final String identityId;
  final String displayName;
  final String? handle;
  final String? localAlias;
  final bool authenticated;
  final DateTime? expiresAt;
}
```

兼容期可以继续保留 `SessionIdentity`，但 `jwtToken` 一律为 `null`，并逐步移除 UI 对 `jwtToken` 的判断。

### 4.2 `AppSessionService`

职责：

- 初始化 IM Core runtime。
- 获取本地 identities。
- 恢复 default identity。
- 登录某个 local identity。
- 调用 `client.auth.status/login/ensureSession/refreshSession`。
- identity 切换时通知 runtime 切换 client。
- logout 时 stop realtime、dispose current client、清 app session state。

不做：

- 不生成 DID。
- 不构造 WBA header。
- 不暴露 JWT。
- 不直接操作 SDK identity 文件。

建议接口：

```dart
abstract interface class AppSessionService {
  Future<AppSession?> restoreSession();
  Future<AppSession?> currentSession();
  Future<List<AppSession>> listLocalIdentities();
  Future<AppSession> loginWithIdentity(String identityIdOrAlias);
  Future<AppSession?> refreshSession();
  Future<void> logout();
}
```

首轮限制：

- `restoreSession` 优先恢复 SDK default identity。
- 显式多身份切换/登录（旧 `loginWithLocalCredential` 语义）首轮可以标记为 unsupported，不做半成品切换。
- `listLocalIdentities` 可以用于展示只读 identity 列表；如果 SDK identity store 不稳定，UI 可以隐藏本地身份选择入口。
- TODO：后续新增 app preference `activeIdentityId`，restore 时先 `resolveIdentity(IdentitySelector.id(activeIdentityId))`，失败再 fallback 到 `defaultIdentity()`；同时补显式 set default / active identity 语义。

---

## 5. IM Core Runtime 设计

### 5.1 `AwikiImCoreRuntime`

职责：

- 构造 `AwikiImCoreConfig`。
- 构造 `AwikiImCorePaths`。
- 调用 `AwikiImCore.open`。
- 调用 `validatePaths`。
- 缓存 `AwikiImCore`。
- 根据 active identity 缓存 `AwikiImClient`。
- identity 切换时 dispose 旧 client。
- app shutdown 时 dispose client/core。

接口：

```dart
abstract interface class ImCoreRuntimePort {
  Future<void> open();
  Future<void> validate();
  Future<AwikiImCore> core();
  Future<AwikiImClient> clientFor(IdentitySelector selector);
  Future<AwikiImClient> currentClient();
  Future<void> switchIdentity(IdentitySelector selector);
  Future<void> dispose();
}
```

### 5.2 paths 策略

```text
appSupport/awiki-me/im-core/identities/
appSupport/awiki-me/im-core/identities/registry.json
appSupport/awiki-me/im-core/identities/default
appSupport/awiki-me/im-core/state/im_core.sqlite
cache/awiki-me/im-core/
temp/awiki-me/im-core/
```

### 5.3 config 策略

`AwikiImCoreConfig` 由 app 环境变量生成：

```dart
const serviceBaseUrl = String.fromEnvironment(
  'AWIKI_SERVICE_BASE_URL',
  defaultValue: 'https://awiki.info',
);
const userServiceEndpoint = String.fromEnvironment(
  'AWIKI_USER_SERVICE_URL',
  defaultValue: 'https://awiki.info',
);
const messageServiceEndpoint = String.fromEnvironment(
  'AWIKI_MESSAGE_SERVICE_URL',
  defaultValue: 'https://awiki.info',
);
const didDomain = String.fromEnvironment(
  'AWIKI_DID_DOMAIN',
  defaultValue: 'awiki.info',
);
const anpServiceDid = String.fromEnvironment(
  'AWIKI_ANP_SERVICE_DID',
  defaultValue: '',
);
```

规则：

- `anpServiceDid` 对群创建是必需的；如果为空，`GroupApplicationService.createGroup` 应明确报错：`Group creation requires AWIKI_ANP_SERVICE_DID`。
- 不在 `awiki-me` 中动态解析 service DID；这属于 IM Core 配置或 IM Core service discovery 能力。

---

## 6. Application services 设计

### 6.1 `OnboardingService`

职责：

- 手机注册流程 orchestration。
- 邮箱注册流程 orchestration。
- handle recover 流程。
- 注册后 profile markdown 补写。
- 登录成功后切换 runtime active identity。
- 处理 invite code、UI 输入规范化、错误映射。

接口：

```dart
abstract interface class OnboardingService {
  Future<void> sendPhoneOtp(String phone);
  Future<void> sendEmailVerification(String email);
  Future<bool> checkEmailVerified(String email);
  Future<HandleRegistrationStatus> lookupHandleRegistration(String handle);

  Future<AppSession> registerWithPhone({
    required String phone,
    required String otp,
    required String handle,
    String? inviteCode,
    String? displayName,
    String? profileMarkdown,
  });

  Future<AppSession> registerWithEmail({
    required String email,
    required String handle,
    String? inviteCode,
    String? displayName,
    String? profileMarkdown,
  });

  Future<AppSession> recoverHandle({
    required String phone,
    required String otp,
    required String handle,
  });
}
```

实现细节：

- `registerWithPhone` 调用 `core.registerHandleWithPhone(...)`。
- `registerWithEmail` 调用 `core.registerHandleWithEmail(...)`。
- `recoverHandle` 调用 `core.recoverHandle(...)`。
- 注册/恢复成功后调用 `runtime.switchIdentity(...)`。
- 调用 `client.auth.ensureSession(AuthScope.userProfile)` 或必要 scope。
- 如果 `profileMarkdown` 不为空，调用 `ProfileApplicationService.updateProfile(markdown)`。
- `sendOtp/sendEmailVerification/checkEmailVerified/lookupHandleRegistration` 如 SDK 未提供，短期可以保留一个 `OnboardingUtilityClient`，但只能用于 onboarding utility，不能继续承载 IM/message/relationship 生产逻辑。

### 6.2 `MessagingService`

职责：

- 发送 DM/group 文本。
- 获取 DM/group history。
- retry 语义。
- 将 SDK DTO 映射为 app UI model。

接口：

```dart
abstract interface class MessagingService {
  Future<AppChatMessage> sendText({
    required AppThreadRef thread,
    required String content,
    String? clientMessageId,
  });

  Future<List<AppChatMessage>> loadHistory(AppThreadRef thread, {
    int limit = 100,
    String? cursor,
  });

  Future<AppChatMessage> retryByResendOriginalContent(AppChatMessage failed);
}
```

规则：

- 不调用 SDK `retryMessage`，因为当前 SDK v0.1 明确 retry unsupported。
- DM 发送使用 `SendTextRequest(target: MessageTarget.direct(peerDid), text: content)`。
- 群发送使用 `SendTextRequest(target: MessageTarget.group(groupDid), text: content)`。
- `sendState` 由 SDK result delivery state 映射；如果 SDK 没有明确状态，则 accepted/sent 映射为 sent。
- `threadId` 使用 SDK 返回 threadId 优先；app 兼容期可以保留旧 `dm:` / `group:` threadId 映射，但不要强行覆盖 SDK 语义。

### 6.3 `ConversationService`

职责：

- 获取会话列表。
- 按 thread 标记已读。
- 应用 product overlay：hidden/pinned/muted/custom title。

接口：

```dart
abstract interface class ConversationService {
  Future<List<AppConversation>> listConversations({
    required String ownerDid,
    int limit = 100,
    bool unreadOnly = false,
  });

  Future<void> markThreadRead(AppThreadRef thread);
  Future<void> setThreadHidden({
    required String ownerDid,
    required String threadId,
    required bool hidden,
  });
}
```

实现：

- `listConversations` 调用 `client.messages.conversations(...)`。
- 从 `ProductLocalStore` 读取 overlay，过滤 hidden tombstone，应用 pinned/muted/custom title。
- `markThreadRead` 首轮不做不准确实现：当前 SDK 只有 `markRead(messageIds)`，但 history/message DTO 不暴露 read-state，不能可靠获取某 thread 的未读 message IDs。首轮 `ConversationService.markThreadRead` 抛明确 `UnsupportedError('IM Core markThreadRead is not available yet')`；UI 可以本地清 unread badge，但不能展示“远端已读已成功”。
- TODO：后续由 IM Core 补 `markThreadRead(ThreadRef)`；或至少补 unread message query/read-state 字段后，app 再做分页拉取 incoming unread IDs 的临时适配。
- `setThreadHidden` 只写 `ProductLocalStore` tombstone，不删除 IM Core DB 主数据。

### 6.4 `GroupApplicationService`

职责：

- 群创建、加入、读取、列表、成员列表、消息列表、离开。
- 群成员添加/移除的 app 侧业务入口。
- 群 UI model 映射。

接口：

```dart
abstract interface class GroupApplicationService {
  Future<AppGroup> createGroup({
    required String name,
    required String slug,
    required String description,
    required String goal,
    required String rules,
    String? messagePrompt,
  });

  Future<AppGroup> joinGroup(String groupDid);
  Future<AppGroup> getGroup(String groupDid);
  Future<List<AppGroup>> listGroups({int limit = 100});
  Future<List<AppGroupMember>> listMembers(String groupDid, {int limit = 100});
  Future<List<AppChatMessage>> listMessages(String groupDid, {int limit = 100, String? cursor});
  Future<void> leaveGroup(String groupDid);

  Future<AppGroup> addMember({
    required String groupDid,
    required String memberDid,
    String role = 'member',
  });

  Future<AppGroup> removeMember({
    required String groupDid,
    required String memberDid,
  });
}
```

规则：

- create/join/get/list/listMembers/listMessages/leave 直接走 SDK。
- add/remove member 当前 IM Core Rust 有能力，但 Flutter facade 未公开；`awiki-me` 先通过 `GroupCorePort` 预留，默认 pending adapter 抛 `UnsupportedError('IM Core group member mutation is not available yet')`。
- 不允许回退旧 `AwikiMessageClient.addGroupMember`。
- `AWIKI_ANP_SERVICE_DID` 缺失时，create group 应给出明确错误。

### 6.5 `ProfileApplicationService`

职责：

- 读取自己 profile。
- 更新自己 profile。
- 读取公开 profile。
- app `ProfilePatch` 与 SDK `ProfilePatch` 映射。

接口：

```dart
abstract interface class ProfileApplicationService {
  Future<AppUserProfile> loadMyProfile();
  Future<AppUserProfile> updateProfile(AppProfilePatch patch);
  Future<AppUserProfile> loadPublicProfile(String didOrHandle);
}
```

映射：

```text
app.nickName          -> sdk.displayName
app.bio               -> sdk.bio
app.tags              -> sdk.tags
app.profileMarkdown   -> sdk.markdown
sdk.subject           -> app.did
sdk.displayName       -> app.nickName
sdk.markdown          -> app.profileMarkdown
```

### 6.6 `RelationshipApplicationService`

关系系统最终属于 IM Core 的通用协议能力，因此 `awiki-me` 业务层只做 orchestration、UI state、错误提示和 DTO mapping。

接口：

```dart
abstract interface class RelationshipApplicationService {
  Future<List<AppRelationship>> listFollowers({int limit = 100, String? cursor});
  Future<List<AppRelationship>> listFollowing({int limit = 100, String? cursor});
  Future<AppRelationship> getStatus(String didOrHandle);
  Future<void> follow(String didOrHandle);
  Future<void> unfollow(String didOrHandle);
}
```

核心 port：

```dart
abstract interface class RelationshipCorePort {
  Future<CoreRelationshipPage> listFollowers({int limit, String? cursor});
  Future<CoreRelationshipPage> listFollowing({int limit, String? cursor});
  Future<CoreRelationshipStatus> status(String peer);
  Future<void> follow(String peer);
  Future<void> unfollow(String peer);
}
```

当前实现策略：

- `AwikiImCoreRelationshipAdapter implements RelationshipCorePort`。
- `status` 调用 SDK `client.directory.relationStatus(peer)`。
- `follow/unfollow/listFollowers/listFollowing` 调用 SDK `client.directory.follow/unfollow/listFollowers/listFollowing`。
- `cursor` 在 app service 边界保持 `String?`，首轮用 offset 字符串适配 SDK 的 `offset` 参数；SDK 若后续返回真实 cursor，mapper 优先使用 SDK `nextCursor`。
- 不使用旧 `AwikiUserClient.relationshipRpc` 作为 fallback。

当前使用现有 directory API：

```dart
client.directory.listFollowers(...)
client.directory.listFollowing(...)
client.directory.relationStatus(peer)
client.directory.follow(peer)
client.directory.unfollow(peer)
```

Codex 先实现 `awiki-me` 的 service/port/provider/UI 对接，不要求修改 `awiki-cli-rs2`。

### 6.7 `RealtimeApplicationService`

职责：

- 启动/停止 IM Core realtime。
- 订阅 `client.events` 与 `client.connectionStates`。
- 将 typed realtime event 映射为 app update。
- 触发 notification / provider update。

接口：

```dart
abstract interface class RealtimeApplicationService {
  Stream<AppRealtimeConnectionStatus> get connectionStates;
  Stream<AppRealtimeUpdate> get updates;

  Future<void> start();
  Future<void> stop();
  bool get isRunning;
}
```

实现规则：

- 使用 SDK `client.realtime.start(...)`。
- 订阅 SDK `client.events`。
- 订阅 SDK `client.connectionStates`。
- 不再接触 raw WebSocket。
- 不再传入 bearer token。
- reconnect 使用 SDK options，例如 exponential。
- `AppRuntimeController` 不再比较 JWT 是否变化。

兼容期：

- 可以实现 `CompatRealtimeGateway implements RealtimeGateway`，内部调用 `RealtimeApplicationService`。
- `RealtimeMessageHandler` 的 raw map 语义应尽快删除；如果必须兼容，`CompatRealtimeGateway` 可将 typed event 转为 app `RealtimeUpdate` 后直接应用，不再走 raw map。

---

## 7. App model 与 mapper

### 7.1 建议保留或轻微调整的 UI-facing model

当前 UI 已使用这些 model，可以短期保留：

```text
ChatMessage
ConversationSummary
GroupSummary
GroupMemberSummary
UserProfile
RelationshipSummary
RealtimeUpdate
BridgeCapabilities
```

但建议将其视为 `awiki-me app model`，不要称为 IM Core model。

### 7.2 mapper 文件

新增：

```text
lib/src/data/im_core/awiki_im_core_mappers.dart
```

包含：

```dart
class AwikiImCoreMappers {
  AppSession sessionFromIdentityAndAuth(...);
  ChatMessage chatMessageFromCore(Message message, {required String ownerDid});
  ConversationSummary conversationFromCore(Conversation conversation, ProductConversationOverlay? overlay);
  GroupSummary groupFromCoreSummary(GroupSummary dto);
  GroupSummary groupFromCoreSnapshot(GroupSnapshot dto);
  GroupMemberSummary groupMemberFromCore(GroupMember dto);
  UserProfile userProfileFromCore(CoreUserProfile dto);
  RelationshipSummary relationshipFromCore(CoreRelationshipStatus dto);
  RealtimeUpdate? realtimeUpdateFromCore(RealtimeEvent event, {required String ownerDid});
  RealtimeConnectionStatus connectionStatusFromCore(RealtimeConnectionState state);
}
```

### 7.3 threadId 规则

首轮兼容策略：

- SDK `Message.threadId` / `Conversation.threadId` 优先。
- 如果 SDK 未给 threadId，则 fallback：
  - direct：`dm:<sorted did A>:<sorted did B>`。
  - group：`group:<groupDid>`。
- UI 层不应假设 threadId 一定由 app 生成。

### 7.4 时间解析

- SDK 时间是 ISO-8601 string。
- mapper 统一解析成 `DateTime`。
- 解析失败 fallback 到 `DateTime.fromMillisecondsSinceEpoch(0)`，但 error mapper 应记录 warning。

### 7.5 error sanitizer

新增：

```text
lib/src/data/im_core/awiki_im_core_error_mapper.dart
```

规则：

- 不暴露 token、private key、signature、Authorization header。
- `unsupported_capability` 映射为明确业务提示。
- auth expired 映射为 session expired / relogin 文案。
- invalid input 映射为字段级错误。

---

## 8. ProductLocalStore 设计

### 8.1 原则

IM Core DB 是 message/conversation/group/read-state 的主数据源。`awiki-me` 只保存产品 overlay。

### 8.2 ProductLocalStore 表

```sql
CREATE TABLE conversation_overlays (
  owner_did TEXT NOT NULL,
  thread_id TEXT NOT NULL,
  pinned INTEGER NOT NULL DEFAULT 0,
  muted INTEGER NOT NULL DEFAULT 0,
  hidden INTEGER NOT NULL DEFAULT 0,
  custom_title TEXT,
  avatar_seed TEXT,
  updated_at TEXT NOT NULL,
  PRIMARY KEY (owner_did, thread_id)
);

CREATE TABLE message_drafts (
  owner_did TEXT NOT NULL,
  thread_id TEXT NOT NULL,
  draft_text TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  PRIMARY KEY (owner_did, thread_id)
);

CREATE TABLE local_ui_preferences (
  owner_did TEXT NOT NULL,
  key TEXT NOT NULL,
  value_json TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  PRIMARY KEY (owner_did, key)
);
```

### 8.3 不再保存

`awiki-me` 本地 store 不再保存：

- message 主体。
- conversation 主体。
- group 主体。
- group members 主体。
- read-state 主体。

### 8.4 本地删除语义

旧 `deleteLocalThread` 应改为：

```text
hideThreadLocally(threadId)
```

它只写 `conversation_overlays.hidden = 1`。

当 SDK 会话列表刷新时，`ConversationService` 应过滤 hidden thread。用户重新收到该 thread 新消息时，策略二选一：

1. 自动取消 hidden，显示新消息。
2. 继续隐藏但计数保留。

推荐首轮选择 1：收到新 realtime message 后取消 hidden。

---

## 9. Bootstrap 与 provider 改造

### 9.1 `AppBootstrap.create()` 新依赖图

替换当前 bootstrap 中的旧实现。

```dart
static Future<AppBootstrap> create() async {
  final preferenceStorage = await _buildPreferenceStore();

  final imCoreRuntime = await AwikiImCoreRuntime.fromEnvironment().openAndValidate();
  final productLocalStore = await AwikiProductLocalStoreSqlite.create();

  final sessionService = AwikiAppSessionService(
    runtime: imCoreRuntime,
  );

  final onboardingService = AwikiOnboardingService(
    runtime: imCoreRuntime,
    sessionService: sessionService,
    profileService: profileService,
    onboardingUtilityClient: optionalUtilityClient,
  );

  final messagingService = AwikiMessagingService(
    runtime: imCoreRuntime,
    mapper: mapper,
  );

  final conversationService = AwikiConversationService(
    runtime: imCoreRuntime,
    productLocalStore: productLocalStore,
    mapper: mapper,
  );

  final groupService = AwikiGroupApplicationService(
    runtime: imCoreRuntime,
    groupCorePort: groupCorePort,
    mapper: mapper,
  );

  final relationshipService = AwikiRelationshipApplicationService(
    relationshipCorePort: relationshipCorePort,
    mapper: mapper,
  );

  final realtimeService = AwikiRealtimeApplicationService(
    runtime: imCoreRuntime,
    mapper: mapper,
  );

  return AppBootstrap(
    sessionService: sessionService,
    onboardingService: onboardingService,
    messagingService: messagingService,
    conversationService: conversationService,
    groupService: groupService,
    profileService: profileService,
    relationshipService: relationshipService,
    realtimeService: realtimeService,
    // compat for old providers during migration
    accountGateway: CompatAwikiAccountGateway(...),
    gateway: CompatAwikiGateway(...),
    realtimeGateway: CompatRealtimeGateway(...),
    notificationFacade: await AppNotificationFacade.create(),
    e2eeFacade: NoopE2eeFacade(),
    localePreferenceService: LocalePreferenceService(storage: preferenceStorage),
    updateService: AppUpdateService(storage: preferenceStorage),
  );
}
```

说明：以上是依赖图示例，不是可直接复制的完整代码；实际实现前需先构造 `mapper`、`profileService`、`groupCorePort`、`relationshipCorePort`、`optionalUtilityClient` 等依赖，并确保所有 SDK import 使用 `as core` alias。

### 9.2 新 providers

新增：

```text
appSessionServiceProvider
onboardingServiceProvider
messagingServiceProvider
conversationServiceProvider
groupApplicationServiceProvider
profileApplicationServiceProvider
relationshipApplicationServiceProvider
realtimeApplicationServiceProvider
productLocalStoreProvider
imCoreRuntimeProvider
```

兼容期保留：

```text
awikiGatewayProvider
awikiAccountGatewayProvider
realtimeGatewayProvider
```

这些旧 provider 注入 compat 实现，内部只委托新 service。

### 9.3 UI provider 改造顺序

优先级：

1. `session_provider` / `app_runtime_provider`：改成不依赖 JWT。
2. `conversation_provider`：改成调用 `ConversationService`。
3. `chat_provider`：改成调用 `MessagingService`。
4. `group_provider`：改成调用 `GroupApplicationService`。
5. `profile_provider`：改成调用 `ProfileApplicationService`。
6. `friends_provider`：改成调用 `RelationshipApplicationService`。
7. 删除 compat gateway。

---

## 10. 阶段执行计划

### 阶段 0：安全准备

Codex 执行前必须检查：

```bash
git status --short
git -C ../awiki-cli-rs2 status --short
```

规则：

- 上述命令假设当前工作目录是 `awiki-me` repo root；如果从 `awiki-space` 父目录执行，则先 `cd awiki-me` 或相应调整路径。
- 默认首轮只改 `awiki-me`；但如果阶段 1 macOS native gate 暴露 SDK packaging/FRB handle blocker，可以在
  `awiki-cli-rs2` 做最小 SDK 修复，并必须重新跑 SDK codegen/cargo/package tests。
- 不手改 `awiki-cli-rs2` generated 文件；如需 generated diff，必须来自 SDK codegen。
- 不在 `awiki-me` 调用 SDK generated/private API。
- 不引入旧 relationship HTTP fallback。
- 首轮不承诺 Flutter Web；Web 不作为阻断验收项，也不为了 Web 增加 fallback。
- 进入代码迁移前，先按 §3.3 处理旧 `lib/src/im_core` 的测试/边界策略，避免新旧 IM Core contract 混用。

### 阶段 1：引入 SDK dependency 与 runtime smoke

修改 `awiki-me/pubspec.yaml`：

```yaml
dependencies:
  awiki_im_core:
    path: ../awiki-cli-rs2/packages/awiki_im_core
```

新增文件：

```text
lib/src/data/im_core/awiki_im_core_config.dart
lib/src/data/im_core/awiki_im_core_paths.dart
lib/src/data/im_core/awiki_im_core_runtime.dart
```

验收：

```bash
flutter pub get
dart analyze
```

新增测试：

```text
test/data/im_core/awiki_im_core_config_test.dart
test/data/im_core/awiki_im_core_paths_test.dart
test/data/im_core/awiki_im_core_runtime_test.dart
```

runtime test 可用 fake runtime，不强制 native open。

Native gate：

- 因为 `package:awiki_im_core` 依赖 Rust FFI/native packaging，阶段 1 后必须尽早在 macOS 跑最小 native open smoke。
- 当前需要特别关注 macOS loader 与打包产物是否一致：如果 SDK loader 期待 `libawiki_im_core.dylib`，但 package 只提供 `.a`/xcframework 静态库，`AwikiImCore.open` 可能在运行时失败。
- 如果 macOS 使用静态 xcframework，SDK loader 应使用 `DynamicLibrary.process()` / `ExternalLibrary.process(...)`，Podspec 需要保证 FRB 符号被链接进 Runner；否则可能出现 `frb_get_rust_content_hash` lookup 失败。
- SDK public facade 必须保证 `AwikiImCore` / `AwikiImClient` / `RealtimeSession` 是可重复调用的 handle：除 `close/dispose/stop` 这类终止操作外，FRB Rust API 参数应按 borrow 语义生成，不能让普通调用消费 `RustOpaque`。否则 `validatePaths` 后再次调用 core/client API 会出现 `Cannot convert RustOpaque to inner value`。
- 如果 macOS native library load/core open 失败，不继续推进 Phase 4+ cutover；先记录为 SDK packaging blocker。
- Flutter Web 暂不处理：不要求 Web run/build 通过，也不为了 Web 恢复旧 HTTP/WS fallback。

### 阶段 2：新增 app models、ports、mappers

新增：

```text
lib/src/application/models/app_session.dart
lib/src/application/models/app_thread_ref.dart
lib/src/application/ports/*.dart
lib/src/data/im_core/awiki_im_core_mappers.dart
lib/src/data/im_core/awiki_im_core_error_mapper.dart
```

Codex 任务：

- 保留现有 UI model。
- mapper 中 SDK 类型一律通过 `core.*` alias 引用，避免和 app/domain model 裸名冲突。
- 新增 mapper 单测。
- 不改 UI。

验收：

```bash
dart analyze
flutter test test/data/im_core/*_test.dart
```

### 阶段 3：ProductLocalStore 替代 AwikiLocalCache 主数据职能

新增：

```text
lib/src/data/local/awiki_product_local_store.dart
lib/src/data/local/awiki_product_local_store_sqlite.dart
lib/src/application/models/product_local_models.dart
```

Codex 任务：

- 实现 conversation overlay。
- 实现 drafts。
- 实现 local ui preferences。
- 不再新增 message/conversation/group 主数据写入。
- 旧 `AwikiLocalCache` 暂时保留给旧 gateway 测试，不接入新 service。

### 阶段 4：Session 与 onboarding

新增：

```text
lib/src/application/app_session_service.dart
lib/src/application/onboarding_service.dart
lib/src/data/im_core/awiki_im_core_identity_adapter.dart
lib/src/data/im_core/awiki_im_core_auth_adapter.dart
lib/src/data/compat/compat_awiki_account_gateway.dart
```

Codex 任务：

- `CompatAwikiAccountGateway` 实现旧 `AwikiAccountGateway`，但：
  - `currentAnpSession` 抛 unsupported。
  - `exportCurrentCredentialAsZip` 若 SDK 未支持，抛明确 unsupported。
  - `importCredentialFromZip` 若 SDK 未支持，抛明确 unsupported。
  - `deleteLocalCredential` 若 SDK 未支持，抛明确 unsupported。
  - `loginWithLocalCredential`/显式本地身份切换首轮抛明确 unsupported；只保留 `restoreSession` 的 default identity 恢复与注册/恢复成功后的当前身份激活。
  - `listLocalCredentials` 可返回 SDK `listIdentities` 的只读映射；如果 UI 容易误导用户，可以先隐藏本地凭证选择入口。
  - `SessionIdentity.jwtToken` 永远为 null。
- 修改 `AppRuntimeController`：不要通过 `jwtToken` 判断 realtime recovery。
- 如果现有 UI 强依赖 credentialName，则用 `identity.localAlias ?? identity.id` 填充。
- Settings/onboarding 中导入、导出、删除本地凭证、登录本地凭证入口首轮应 disabled/隐藏，或点击后显示明确 unsupported；不能静默失败。

### 阶段 5：Message 与 conversation

新增：

```text
lib/src/application/messaging_service.dart
lib/src/application/conversation_service.dart
lib/src/data/im_core/awiki_im_core_message_adapter.dart
lib/src/data/im_core/awiki_im_core_conversation_adapter.dart
```

Codex 任务：

- 实现 send text。
- 实现 direct/group history。
- 实现 conversations。
- `markThreadRead` 首轮标记 unsupported，并加 TODO；不通过 history 猜 unread IDs。
- 实现 retry by resend。
- 用 ProductLocalStore overlay 处理 hidden/pinned/muted。

验收：

- conversation list 能从 SDK DTO 映射到 UI。
- chat history 能从 SDK DTO 映射到 UI。
- app 不再通过新路径写 `AwikiLocalCache.messages/conversations`。

### 阶段 6：Group

新增：

```text
lib/src/application/group_application_service.dart
lib/src/data/im_core/awiki_im_core_group_adapter.dart
lib/src/data/im_core/pending_im_core_group_mutation_adapter.dart
```

Codex 任务：

- create/join/get/list/listMembers/listMessages/leave 走 SDK public API。
- addMember/removeMember 通过 `GroupCorePort`，当前用 pending adapter 抛 unsupported。
- 不调用旧 `AwikiMessageClient.addGroupMember`。

### 阶段 7：Profile 与 directory

新增：

```text
lib/src/application/profile_application_service.dart
lib/src/application/directory_application_service.dart
lib/src/data/im_core/awiki_im_core_profile_adapter.dart
```

Codex 任务：

- profile load/update/public load 走 SDK。
- did/handle resolve 走 SDK directory。
- mapper 覆盖 markdown/displayName/bio/tags。

### 阶段 8：Relationship app 侧先行

新增：

```text
lib/src/application/relationship_application_service.dart
lib/src/application/ports/relationship_core_port.dart
lib/src/data/im_core/awiki_im_core_relationship_adapter.dart
```

Codex 任务：

- `RelationshipApplicationService` 完整实现 orchestration 与 app model mapping。
- `status` 通过 SDK `client.directory.relationStatus` 实现。
- `follow/unfollow/listFollowers/listFollowing` 通过 `RelationshipCorePort` 调用 SDK directory API。
- `friends_provider` 接入新 service，不保留旧 RPC fallback。
- 不保留旧 relationship RPC fallback。

无需改 UI。

### 阶段 9：Realtime

新增：

```text
lib/src/application/realtime_application_service.dart
lib/src/data/im_core/awiki_im_core_realtime_adapter.dart
lib/src/data/compat/compat_realtime_gateway.dart
```

Codex 任务：

- 使用 SDK `client.realtime.start`。
- 订阅 `client.events`。
- 订阅 `client.connectionStates`。
- 将 typed event 映射为 `RealtimeUpdate`。
- 删除新路径对 raw map 的依赖。
- `AppRuntimeController` 改成监听 `RealtimeApplicationService.updates`。

### 阶段 10：Bootstrap cutover

修改：

```text
lib/src/app/bootstrap.dart
lib/src/app/app_services.dart
lib/src/app/awiki_me_app.dart
```

Codex 任务：

- bootstrap 创建 IM Core runtime 与 application services。
- 旧 gateway provider 注入 compat gateway。
- 新 service provider 也注入实际 service。
- 保持 notification、locale、update service。

### 阶段 11：Provider 去 compat 化

逐个 provider 从旧 gateway 改到新 service：

```text
session_provider.dart
app_runtime_provider.dart
conversation_provider.dart
chat_provider.dart
group_provider.dart
profile_provider.dart
friends_provider.dart
```

全部完成后：

- 删除 `CompatAwikiGateway`。
- 删除 `CompatAwikiAccountGateway`。
- 删除 `CompatRealtimeGateway`。
- 删除旧 gateway interfaces 或降级 test fixture。

### 阶段 12：清理旧代码与依赖

删除或隔离：

```text
lib/src/data/gateways/awiki_anp_gateway.dart
lib/src/data/services/awiki_account_service.dart
lib/src/data/services/awiki_ws_realtime_gateway.dart
lib/src/data/awiki_sdk/*
lib/src/im_core/*                         # 删除，或重命名为 test-only legacy_im_core_contract
```

移除依赖：

```yaml
anp
web_socket_channel
http       # 如果 onboarding utility 不再使用
archive    # 如果 identity import/export 改由 SDK 且不再 app 侧打包
crypto     # 如果不再 app 侧签名/哈希
sqflite    # 如果 ProductLocalStore 不使用 sqflite，或改用 sqlite3/path_provider
```

### 10.1 当前执行状态（2026-05-23）

已落地：

- 阶段 0：旧 `lib/src/im_core` production boundary guard 已更新，避免 UI/domain/new data path 直接依赖旧 Dart-only contract 或 SDK internals。
- 阶段 1：`awiki_im_core` path dependency、runtime/config/paths、macOS native open smoke 已通过。
- 阶段 2：`AppSession`、`AppThreadRef`、core ports、SDK mapper、error sanitizer 已落地。
- 阶段 3：`ProductLocalStore` 与 in-memory/sqflite overlay store 已落地；新路径不写 message/conversation/group 主数据。
- 阶段 4：`AppSessionService`、`OnboardingService`、identity/auth adapters、`CompatAwikiAccountGateway` 已落地；JWT 不再作为新 session contract，凭证导入/导出/删除/显式本地登录均明确 unsupported/TODO。
- 阶段 5：`MessagingService`、`ConversationService`、message/conversation adapters 已落地；`markThreadRead` 明确 unsupported，不通过 history 猜 unread IDs。
- 阶段 6-9：group/profile/directory/relationship/realtime application services 与 SDK adapters 已落地；关系 follow/unfollow/listFollowers/listFollowing/status 已通过 SDK directory API 对接，group add/remove member 仍保持 unsupported/TODO。
- compat 层：`CompatAwikiGateway`、`CompatAwikiAccountGateway`、`CompatRealtimeGateway` 已创建。
- 阶段 10：`AppBootstrap.create()` 已切到 IM Core runtime + application services + compat gateways；`AwikiMeApp` 已注入新 application service providers 与旧 gateway compat providers。
- onboarding utility：SDK 尚未暴露 send OTP / email verification / unauthenticated handle lookup，当前由 `AwikiOnboardingSupportService` 作为临时 app-side onboarding utility 提供；注册/恢复本体仍走 IM Core SDK。
- 阶段 11（大部分）：presentation runtime/provider 路径已从旧 gateway/realtime compat 改为 granular application services；`app_runtime_provider` 使用 `AppSessionService` + `RealtimeApplicationService`，`app_shell` 使用新 realtime status provider，实时消息直接消费 typed `RealtimeUpdate`，不再通过 raw map + `AwikiGateway.consumeRealtimeEvent`。
- `profile_provider`、`peer_profile_provider`、`conversation_provider`、`chat_provider`、`group_provider`、`friends_provider`、`onboarding_provider`、`identity_flow` 已从旧 gateway 改为 granular application services；chat 发送/历史使用 `MessagingService`，会话列表/隐藏/mark-read 边界使用 `ConversationService`，群列表/创建/加入/成员读取使用 `GroupApplicationService`，联系人/身份查询使用 `ProfileApplicationService` + `RelationshipApplicationService`，注册/恢复使用 `OnboardingService`，OTP/email/handle lookup 使用 `OnboardingSupportService`。
- Settings credential actions 不再调用旧 account compat 成功路径；导入/导出/删除本地凭证首轮通过 `AppRuntimeController` 明确提示 IM Core unsupported/TODO。
- 测试 fixture：`test/test_support.dart` 已补齐 `FakeAppSessionService`、`FakeRealtimeApplicationService`、`FakeProfileApplicationService`、`FakeConversationService`、`FakeMessagingService`、`FakeGroupApplicationService`、`FakeRelationshipApplicationService`、`FakeOnboardingService`、`FakeOnboardingSupportService`，避免迁移后的 provider 继续直接依赖旧 gateway mock。
- 阶段 12（旧实现清理）：旧 app-side ANP/IM/WS production fallback 已删除，包括 `AwikiAnpGateway`、`AwikiAccountService`、`AwikiWsRealtimeGateway`、旧 `lib/src/data/awiki_sdk/*`、旧 `AwikiLocalCache`、旧 DID registration facade、旧 Dart-only `lib/src/im_core/*` 及其 legacy tests；`test/im_core/im_core_boundary_test.dart` 已改成防回归边界测试。
- 依赖清理：`anp`、`web_socket_channel`、`archive` 已不再是 direct dependencies；`archive` 仍由其他 Flutter tooling/package transitive 引入。`http` 保留给 onboarding utility、profile markdown loader、update service；`crypto` 保留给 update checksum；`sqflite` 保留给 `ProductLocalStore`。
- Relationship 增量对接：拉取 `awiki-cli-rs2/main` 后，SDK Rust core 已有 relationship runtime；本轮补齐 Flutter/Dart facade DTO/API（`follow/unfollow/listFollowers/listFollowing`），重跑 codegen 并重建 macOS xcframework，`awiki-me` 删除 `PendingImCoreRelationshipAdapter`，`AwikiImCoreRelationshipAdapter` 直接调用 SDK。

尚未完成：

- 阶段 11 仍保留过渡外壳：`session_provider` 继续使用 UI-facing `SessionIdentity` 形状，`AwikiMeApp` 仍注入旧 compat gateway provider 供尚未删除的测试/过渡面使用；但 presentation/provider 生产路径已不再直接读取旧 gateway/account/realtime providers，运行时会话、实时、消息、会话、群组、Profile、联系人、onboarding 均通过 granular application services。
- `CompatAwikiGateway` / `CompatAwikiAccountGateway` / `CompatRealtimeGateway` 与旧 gateway interface 仍作为过渡注入面保留；后续可在 `session_provider` 也改成 `AppSession` 后整体删除。
- Settings/onboarding UI 对导入、导出、删除、本地凭证登录入口当前明确 unsupported；后续可改为隐藏/disabled，或在 SDK 补齐 identity store 能力后启用。
- 多身份恢复/active identity preference 仍保留 TODO。

验证证据：

- `PUB_HOSTED_URL=https://mirrors.tuna.tsinghua.edu.cn/dart-pub flutter pub get`：通过；镜像源无法获取 `archive`/`http` advisories，且有若干非阻断 dependency newer-version 提示；`anp`、`web_socket_channel`、`archive` direct dependency 已移除（`archive` 变为 transitive）。
- `dart analyze`：通过，输出 `No issues found!`。
- Relationship 增量验证：SDK `scripts/flutter/codegen-check.sh`、`cargo test -p im-core-dart`、`packages/awiki_im_core dart analyze`、`packages/awiki_im_core flutter test` 通过；`awiki-me dart analyze`、`flutter test test/application/im_core_application_services_test.dart test/data/im_core/awiki_im_core_mappers_test.dart test/data/compat/compat_awiki_gateway_test.dart test/friends_workspace_test.dart`、`flutter test`、macOS native smoke 通过。
- `flutter test test/im_core/im_core_boundary_test.dart test/data/services/awiki_onboarding_support_service_test.dart test/data/compat/compat_awiki_account_gateway_test.dart test/bootstrap_test.dart`：通过，覆盖阶段 12 删除旧 fallback、onboarding utility 重命名、compat account contract、bootstrap 注入。
- `flutter test test/awiki_me_app_localization_test.dart test/onboarding_page_test.dart test/app_runtime_notification_test.dart test/app_runtime_archive_actions_test.dart test/settings_page_test.dart test/realtime_connection_status_toast_test.dart`：通过，覆盖 app runtime/realtime 去 compat 化、typed realtime update、credential unsupported 行为、manual bootstrap fake service 注入、onboarding 导入凭证 unsupported 行为。
- `flutter test test/chat_provider_open_test.dart test/chat_page_test.dart test/group_flow_test.dart test/app_runtime_notification_test.dart`：通过，覆盖 chat/group/provider 去 compat 化。
- `flutter test test/identity_flow_test.dart test/friends_workspace_test.dart test/app_runtime_notification_test.dart test/profile_page_test.dart test/chat_provider_open_test.dart`：通过，覆盖联系人/身份查询去 compat 化。
- `flutter test test/onboarding_page_test.dart test/app_runtime_archive_actions_test.dart test/settings_page_test.dart`：通过，覆盖 onboarding service/support service 去 compat 化以及 credential action unsupported 回归。
- `flutter test test/application test/data/im_core test/data/local test/data/compat test/data/services test/im_core/im_core_boundary_test.dart test/awiki_me_app_localization_test.dart test/bootstrap_test.dart`：通过，覆盖 application/data layer 与 IM Core migration boundary guard。
- `flutter test`：通过，134 个测试全部通过（旧 ANP/WS/Dart-only IM Core legacy tests 已随旧实现删除）。
- `flutter test tests/e2e/flutter/im_core_open_smoke_test.dart -d macos`：通过；仍有非致命 linker warning（duplicate library、SDK 静态库对象以 macOS 15.2 构建但 Runner 链到 10.15）以及 `Failed to foreground app; open returned 1`，不影响 smoke 通过。
- `rg -n "awikiGatewayProvider|awikiAccountGatewayProvider|realtimeGatewayProvider" lib/src/presentation`：无匹配，确认 presentation 生产路径不再直接读取旧 gateway/account/realtime providers。
- `rg -n "awiki_sdk|AwikiAnpSession|AwikiAnpGateway|AwikiAccountService|AwikiWsRealtimeGateway|AwikiMessageClient|AwikiAnpProofBuilder|DidRegistrationFacade|package:(anp|web_socket_channel|archive)" lib pubspec.yaml`：无匹配，确认旧 app-side ANP/IM/WS fallback 与 direct dependency 不在 production path。
- SDK 侧：`scripts/flutter/codegen-check.sh`、`cargo test -p im-core-dart`、`packages/awiki_im_core` 的 `dart analyze` 与 `flutter test` 已通过。

---

## 11. 关系系统后续 IM Core 补齐契约

虽然本计划不要求 Codex 修改 IM Core，但 `awiki-me` 侧要按下面契约预留。

### 11.1 期望 SDK DTO

```dart
class RelationshipSummaryDto {
  final String did;
  final String? handle;
  final String? displayName;
  final String relationship; // none, following, follower, mutual, blocked
  final String? avatarUrl;
  final String? updatedAt;
}

class RelationshipPageDto {
  final List<RelationshipSummaryDto> items;
  final String? nextCursor;
  final bool hasMore;
}
```

### 11.2 期望 SDK API

```dart
abstract interface class RelationshipApi {
  Future<RelationshipPageDto> listFollowers({int limit = 100, String? cursor});
  Future<RelationshipPageDto> listFollowing({int limit = 100, String? cursor});
  Future<RelationshipSummaryDto> status(String peer);
  Future<void> follow(String peer);
  Future<void> unfollow(String peer);
}
```

### 11.3 aWiki-me 侧不可做的事

- 不在 app 侧拼 relationship RPC。
- 不在 app 侧生成 relationship ANP proof。
- 不把旧 User Service relationship RPC 当 fallback。
- 不把 relationship 数据写成 app 主数据源。

---

## 12. 测试计划

### 12.1 Unit tests

新增测试：

```text
test/application/app_session_service_test.dart
test/application/onboarding_service_test.dart
test/application/messaging_service_test.dart
test/application/conversation_service_test.dart
test/application/group_application_service_test.dart
test/application/profile_application_service_test.dart
test/application/relationship_application_service_test.dart
test/application/realtime_application_service_test.dart
test/data/im_core/awiki_im_core_mappers_test.dart
test/data/local/awiki_product_local_store_test.dart
```

测试原则：

- application service 测试使用 fake core ports。
- mapper 测试直接构造 SDK model DTO。
- 不依赖真实网络。
- 不依赖真实 native library，除 smoke test 外。
- app session 测试覆盖：default identity restore 可用；显式本地身份登录/导入/导出/删除首轮 unsupported。
- conversation 测试覆盖：`markThreadRead` 首轮 unsupported，不调用 `markRead(ids)`。

### 12.2 Provider tests

更新现有 provider tests：

```text
test/chat_provider_test.dart
test/conversation_provider_test.dart
test/group_provider_test.dart
test/profile_provider_test.dart
test/friends_provider_test.dart
test/app_runtime_provider_test.dart
```

重点：

- provider 不再依赖 JWT。
- realtime update 能更新 chat/conversation/group state。
- relationship unsupported 状态能正确提示，不崩溃。
- `markThreadRead` unsupported 状态能正确提示，不伪造已读成功。
- 本地凭证导入/导出/删除/显式登录入口 disabled/unsupported 时 UI 不崩溃。

### 12.3 Native smoke tests

macOS：

```bash
flutter test tests/e2e/flutter/im_core_open_smoke_test.dart -d macos
```

或最小 app 启动 smoke：

```bash
flutter run -d macos --dart-define=AWIKI_ANP_SERVICE_DID=<service_did>
```

### 12.4 Full validation

```bash
flutter pub get
dart analyze
flutter test
```

SDK 补齐后额外跑：

```bash
cd ../awiki-cli-rs2
scripts/flutter/codegen-check.sh
cd packages/awiki_im_core
flutter test
cd ../..
cargo test -p im-core-dart
cargo test -p im-core
```

---

## 13. 验收标准

### 13.1 首轮 awiki-me 侧完成标准

- `awiki-me` 能通过 `awiki_im_core` dependency analyze。
- bootstrap 能构造 IM Core runtime。
- UI/provider 可以通过 compat 或新 service 访问 application services。
- session/onboarding/message/conversation/group/profile/realtime 主要路径已接入 IM Core SDK。
- relationship 已有 `RelationshipApplicationService` 与 `RelationshipCorePort`，follow/unfollow/list/status 走 IM Core SDK，不再走旧 User Service fallback。
- SDK 未补齐的 group member mutation 能以 unsupported 状态清晰失败。
- SDK 未补齐的 `markThreadRead(ThreadRef)` 能以 unsupported 状态清晰失败，不通过 history 猜测 unread IDs。
- 本地凭证导入/导出/删除/显式登录首轮已 disabled/隐藏或明确 unsupported。
- 旧 `lib/src/im_core` 已删除、重命名为 test-only legacy contract，或至少不再处于 production dependency path。
- UI 不再持有或比较 JWT。
- 新路径不再写 app 侧 message/conversation/group 主数据 cache。
- app 侧不再新增 raw WebSocket 代码。
- app 侧不再新增 ANP proof 代码。
- `dart analyze` 通过。
- `flutter test` 通过。

### 13.2 IM Core 补齐后完成标准

- relationship follow/unfollow/listFollowers/listFollowing/status 全部走 IM Core。
- group add/remove member 走 IM Core Flutter public API。
- `markThreadRead(ThreadRef)` 或等价 read-state API 走 IM Core，不再 unsupported。
- identity delete/set default/import/export 如产品保留，则走 IM Core API。
- `Compat*` 层删除。
- 旧 `AwikiAnpGateway`、`AwikiAccountService`、`AwikiWsRealtimeGateway` 删除。
- 旧 `anp`、`web_socket_channel`、不必要 `http` 依赖删除。
- macOS native open smoke test 通过。
- iOS/Android packaging smoke test 通过。

---

## 14. Codex 执行提示词

可以把下面这段直接交给 Codex：

```text
请按 docs/awiki-im-core-rust-sdk-migration-plan2.md 执行 awiki-me 侧迁移。默认只修改 awiki-me；若 macOS native gate 暴露 SDK packaging/FRB handle blocker，允许在 awiki-cli-rs2 做最小 SDK 修复并用 codegen/test 验证。目标是保留 UI，重写 application/data 中间层，将 IM、身份、认证、消息、会话、群组、Profile、Realtime 接入 package:awiki_im_core。

硬约束：
1. 不调用 awiki_im_core generated/private API，只使用 package:awiki_im_core/awiki_im_core.dart public API。
2. 不新增旧 /im/rpc、ANP proof、raw WebSocket、JWT refresh 逻辑。
3. 不把 SDK DTO 暴露到 UI/provider。
4. IM Core SDK 自己有 DB，awiki-me 不再保存 message/conversation/group 主数据，只保存 UI overlay。
5. 关系系统由 IM Core 提供；awiki-me 使用 RelationshipApplicationService + RelationshipCorePort + AwikiImCoreRelationshipAdapter，follow/unfollow/list/status 均走 SDK directory API，不走旧 HTTP fallback。
6. group add/remove member 当前也通过 port 预留，SDK 未补齐前 pending unsupported，不走旧 RPC fallback。
7. markThreadRead 当前标记 unsupported，并加 TODO；不通过 history 猜 unread IDs。
8. 本地凭证导入、导出、删除、显式登录首轮标记 unsupported 或隐藏入口。
9. 先处理旧 lib/src/im_core 的退场/隔离策略；新 SDK import 一律使用 `as core` alias。
10. UI 能保留就保留；必要时先用 CompatAwikiGateway/CompatAwikiAccountGateway/CompatRealtimeGateway 连接旧 provider 和新 services。
11. 每个阶段完成后运行 dart analyze 和相关 flutter test。首轮不处理 Flutter Web，不为 Web 增加 fallback。

优先完成阶段：
Phase 0 旧 lib/src/im_core 边界处理与 SDK native gate；
Phase 1 runtime/config/paths；
Phase 2 ports/mappers；
Phase 3 ProductLocalStore；
Phase 4 AppSession/Onboarding；
Phase 5 Messaging/Conversation；
Phase 6 Group；
Phase 7 Profile/Directory；
Phase 8 Relationship app-side port；
Phase 9 Realtime；
Phase 10 Bootstrap cutover。
```

---

## 15. 风险与处理

| 风险 | 影响 | 处理 |
| --- | --- | --- |
| SDK native library packaging 失败 | app 启动或 core open 失败 | 阶段 1 后立即跑 macOS native open smoke；失败则停止 Phase 4+ cutover，记录 SDK blocker |
| SDK FRB handle 被普通 API 消费 | core/client 第一次调用后后续调用崩溃或 panic | SDK 非终止 API 使用 borrow 语义；`close/dispose/stop` 才保留 owned 语义；native smoke 至少覆盖 open + validate + dispose |
| 旧 `lib/src/im_core` 与新 SDK adapter 混用 | 类型命名冲突、测试边界误判、生产路径不清晰 | 按 §3.3 删除/重命名/隔离旧 internal contract；新 SDK import 统一 `as core` |
| group add member SDK Flutter facade 未补齐 | 添加成员不可用 | app 侧 pending unsupported；SDK 补齐后替换 port |
| mark thread read SDK 未补齐 | 已读按钮不可用 | 首轮明确 unsupported，不伪造成功；TODO 等 SDK `markThreadRead(ThreadRef)` 或 read-state query |
| 本地凭证导入/导出/删除/显式登录 SDK 未补齐 | 设置/登录页部分入口不可用 | 首轮隐藏/disabled 或明确 unsupported；恢复 default identity 与注册/恢复成功激活先可用 |
| 多身份恢复/切换策略未完善 | 多身份用户只能依赖 default identity | 首轮 TODO；后续保存 `activeIdentityId` 并补 set default / active identity 语义 |
| 双数据库主数据冲突 | 消息/会话状态不一致 | IM Core DB 作为唯一主数据源；app store 只保存 overlay |
| UI 对 JWT 强依赖 | realtime/session recovery 逻辑失效 | 重写 AppSession，不暴露 JWT；realtime recovery 交给 SDK |
| 旧 provider 迁移范围过大 | 一次性改动风险高 | 先用 compat gateway，后续逐步去 compat |
| Web 不支持 native SDK | Flutter Web 运行失败 | 首轮不处理 Web，不把 Web 作为验收目标，也不为 Web 恢复旧 fallback |

---

## 16. 推荐最终状态

最终 `awiki-me` 应变成：

```text
UI = 产品界面
Application services = 产品业务流程
ProductLocalStore = 产品 UI overlay
IM Core SDK = 身份、认证、消息、会话、群组、关系协议、实时、核心 DB
```

`awiki-me` 不再知道 transport/proof/token/database 主数据细节，只通过 IM Core SDK 的 public API 使用底层能力。
