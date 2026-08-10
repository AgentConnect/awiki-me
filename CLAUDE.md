# awiki-me/

> Repository context | Parent workspace: [../CLAUDE.md](../CLAUDE.md) | Local rules: [AGENTS.md](AGENTS.md)

1. **地位**：AWiki 跨平台 Flutter App，面向人类用户和 Agent，承载身份 onboarding、tenant 管理、会话/群组/附件/Mention、Agent/Daemon 控制和产品 UI。
2. **边界**：App 拥有 UI、导航、application orchestration、平台适配、短期交互状态和 presentation overlay；消息、conversation、read-state、sync/outbox、identity vault 与密码正确性由 sibling `../awiki-cli-rs2/packages/awiki_im_core` / Rust `im-core` 提供。
3. **约束**：
   - 不直接拼 message-service wire、读 raw SQLite、写 reliable checkpoint 或持有 DID/E2EE 私钥。
   - `ProductLocalStore` 只保存 App overlay，不建立第二套 durable message truth。
   - tenant 切换必须先释放旧 runtime，并按不可变 Storage Scope 隔离 identity、conversation、cache 与 vault。
   - 首页只保留统一登录/注册；已验证 Handle 存在时才显示 Join/Recovery 选择。Join grant 只能留在 adapter 内存并由 opaque continuation 单次消费；Recovery 必须丢弃该 grant、发送 purpose 隔离的专用 OTP、省略 selector，并由 Core 按输入 Handle 匹配或新增身份，不能把当前身份、`credentialName`/alias 当作目标猜测。
   - 设备管理等高风险操作通过 `UserPresencePort` 调用系统认证，设备不支持、用户取消或平台认证失败时必须 fail closed。
   - `system_notification_changed` 仅作为设备域因果失效信号：App 必须独立读取 Core typed Join inbox 并展示全局审批入口，不能等待通用 message sync 成功，也不能从 realtime payload 直接构造请求、自动验证/拒绝/批准。
   - Core reliable sync 必须把 v2 `system.notification` marker 作为 exact-device durable inbox hydration 门禁，在提交该页 cursor 前完成 typed notification 投影；因此 realtime hint 丢失时，前台 catch-up 仍能恢复 Join 请求。
   - Android/iOS remote push transport 是进程级平台能力，不随 tenant runtime 重建；Push 只作为同步提示，不能成为消息或未读状态的事实来源。
   - Realtime/Push 都只是同步提示；前台会话必须以有界周期触发 Core reliable sync，补偿提示丢失，并在后台停止，不能把 WebSocket 投递当作可靠消息事实源。
   - Core diagnostics 中带 `pending` / `scheduled` 的本地 mutation outbox 由 App 消息同步协调器按 Core `nextRetryAt` 串行重试；这属于 application scheduling，不改变 Core 对 outbox、游标和重试状态的事实源所有权。
   - 消息同步的认证拒绝（HTTP 401/403、耗尽重试后的 `1401` 和设备资格 fence）是终止性 `authRevoked`；普通可重试失败在连续 3 次后才开始提示，并仍按连续失败时长升级为红色提示。Core commit 后的 Join inbox/会话列表投影刷新异常必须单独标记，不能反向改写为“同步失败”。App 安全诊断只记录 stage/category/稳定 code/HTTP status/count/time，不包含异常正文、身份、cursor、token 或 payload。
   - 无业务消息体但携带 Core `sync` hint 的 realtime 事件必须保留为 sync-only `RealtimeUpdate` 并调度 reliable sync；普通 P3 Direct 的兄弟设备 outgoing 投影来自 sender owner 的 `sync.delta` / `sync.thread_after`，不能由 App 构造 plain own-sync 或升级为 P5。App 使用的稳定 conversationId 只是展示/存储路由，普通 Direct 的不可变 wire identity 仍由 Core 保持为 `direct + peer DID`。
   - Agent 页面以 User Service Inventory 为存在性基线，以 IM Core committed control patch 为运行状态/因果失效信号，以 App pending intent 为短期交互层；realtime control 只触发 reliable sync，不能直接成为 Agent UI 真相。typed account binding 存在时，Agent provider 的 cache/load owner 必须是稳定 `owner_identity_id + account_id`，应用权威 Inventory 后标记同一 owner 与当前 session operation 已加载，不能因 Handle/DID key 不一致阻塞 create pending 首帧。权威 Inventory 中的 runtime Agent 在发布到 UI 前通过 Core Directory 投影 canonical Direct route，失败不伪造 Persona，并由后续 Inventory 对账重试。可见 Agent 页面在 App 前台按 30 秒静默重读 Inventory，以补偿失效信号丢失，页面销毁或 App 后台时不发起对账。
   - Agent/Daemon 能力按 App 内置 realm 白名单 fail-closed；仅当 HTTPS backend host 与 DID Host 相同且命中 `awiki.ai`、`agent-connect.cn`、`awiki.info`、`anpclaw.com` 时启用。Skill onboarding 还必须由当前同源 User Service 的 `server-info` 显式声明受支持 V1 和固定 `/cli/onboarding.md`，不能另建域名名单或仅按 realm 猜测发布状态。
   - Daemon 安装命令只签发自动命名意图，不在 App 或 token metadata 中预先写死 `Daemon N`；最终默认名由 User Service 在实际 exchange 的账号级事务内分配，未执行命令不得占号。
   - 新加入的 tail-only 设备可以先拥有 canonical Agent/Direct route、后拥有服务端 durable thread binding；App 只在空 Direct 且无本地 server sequence 时把 typed `SYNC_THREAD_BINDING_REQUIRED` 解释为“暂无加入后历史”，不得由 DID/Handle/Inventory 伪造 binding，已有服务端序号时仍 fail closed。
   - 行为和 UI 变化同时更新 `tests/unit/`；真实 backend、CLI peer、平台或设备流程变化同步更新 `tests/e2e/`。
   - 平台 runner 变更只触及任务明确要求的平台，避免提交无关生成文件。

## 主要目录

| 路径 | 职责 |
|---|---|
| `lib/src/domain/` | Domain entities、ports 和纯业务约束 |
| `lib/src/application/` | auth/session/messaging/groups/profile/agents/attachments/tenant 等用例编排 |
| `lib/src/data/` | `awiki_im_core` adapters、service clients、local/secure storage 与 platform bridge |
| `lib/src/data/push/` | Android/iOS EMAS transport adapter、共享 MethodChannel 与其他平台 no-op factory |
| `lib/src/data/storage/` | UUID Storage Scope registry/manifest/layout、provision/recovery、strict envelope、platform/E2E secret provider及统一root解析；runtime只可openExisting |
| `lib/src/presentation/` | Flutter 页面、Riverpod providers、组件、响应式布局和反馈 |
| `tests/unit/` | 快速确定性 unit/widget/provider/fake-backed tests；line/branch baseline 由 `tests/quality/coverage_baseline.json` 约束 |
| `tests/e2e/` | audited suite manifest + case catalog/checker、killable runner、schema-v2 case/assertion attestation、首失败脱敏诊断、configs、Flutter implementations、本地 production-bootstrap/native-Core capability gate、真实远端 `awiki.info` App+CLI/backend/device flows与资源台账 |
| `integration_test/` | Flutter tooling 薄 shim； durable scenario 在 `tests/e2e/flutter/`；App-pair shim 由两个隔离 bundle 分别编译 |
| `scripts/` | packaging/build helper与显式developer/release gate；cleanup默认dry-run，不进入production startup |
| `docs/` | 产品、架构、测试、Personal Agent、SecretVault、性能和计划文档 |
| `ios/` | iOS 13+ Runner；使用 `UIScene`、CocoaPods Debug/Profile/Release 配置，并承载 App 自定义 platform channels |
| `android/`, `macos/`, `web/` | 其他平台 runners |

## 权威入口

- [README.md](README.md)：产品定位、架构、运行、测试、打包与安全边界。
- [docs/testing.md](docs/testing.md)：unit/smoke/full E2E 分层。
- [docs/test-case-catalog.md](docs/test-case-catalog.md)：由 catalog 生成的 case→oracle→gate→evidence 追踪表。
- [docs/test-quality.md](docs/test-quality.md)：line/branch baseline、mutation proof 与大文件治理入口。
- [docs/conversation-presentation-ownership.md](docs/conversation-presentation-ownership.md)：conversation-first 显示与 overlay 边界。
- [docs/identity-secret-storage.md](docs/identity-secret-storage.md)：App root key provider 与 SecretVault 边界。
- [docs/multi-device-join-ui.md](docs/multi-device-join-ui.md)：默认关闭的设备列表、SMS Join、双端 6 位 SAS、角色选择与 App/Core 秘密边界。
- [docs/multi-device-app-pair-e2e.md](docs/multi-device-app-pair-e2e.md)：单机双隔离 App 的构建、驱动、协调与秘密边界。
- [docs/root-key-transfer-ui.md](docs/root-key-transfer-ui.md)：默认关闭的管理设备根导入、user-presence、management-ready 投影与控制消息过滤边界。
- [docs/group-encryption-ui.md](docs/group-encryption-ui.md)：默认关闭的本设备群加密准备/重试/就绪投影与 P6 v2 Core 启用门禁。
- [docs/handle-recovery-ui.md](docs/handle-recovery-ui.md)：默认关闭的 Manifest Handle Recovery V1、operation-bound OTP、风险确认、Core-owned activate/resume 与 DID replacement 边界。
- [docs/storage-scope-vault-contract.md](docs/storage-scope-vault-contract.md)：首发 UUID Storage Scope、稳定 Keychain locator 与 lifecycle 权威契约。
- [docs/scope-secret-platform.md](docs/scope-secret-platform.md)：typed envelope、平台 provider、channel 隔离与 native/E2E gate。
- [docs/pre-release-storage-cleanup.md](docs/pre-release-storage-cleanup.md)：首发前旧 namespace 目录/Keychain inventory、dry-run、archive 与显式删除 runbook。
- [docs/personal-agent/personal-agent-design.md](docs/personal-agent/personal-agent-design.md)：Personal Agent 产品与 daemon binding。
- [../awiki-cli-rs2/docs/flutter-sdk/awiki-im-core-flutter-sdk.md](../awiki-cli-rs2/docs/flutter-sdk/awiki-im-core-flutter-sdk.md)：Dart/Flutter SDK 权威。

## 验证

```bash
dart analyze
dart run tests/unit/runner.dart --branch-coverage
dart run tool/test_coverage_gate.dart
dart run tool/validate_test_catalog.dart
dart run tests/e2e/runner.dart --case smoke
dart run tests/e2e/runner.dart --case multi-device
# Requires reviewed awiki.info rollout/account env:
dart run tests/e2e/runner.dart --case multi-device-remote-join --config <local-awiki-info-config.yaml>
dart run tests/e2e/runner.dart --case multi-device-app-pair --config <local-awiki-info-config.yaml>
dart run tests/e2e/runner.dart --case multi-device-app-pair-functional --config <local-awiki-info-config.yaml>
dart run tests/e2e/runner.dart --case multi-device-remote-recovery --config <local-awiki-info-config.yaml>
dart run tests/e2e/runner.dart --case multi-device-app-pair-recovery-registration-rejoin-management-transfer --config <explicit-macos-awiki-info-config.yaml>
```

`multi-device` 当前只证明生产 provider 树可挂载本地 Join surface 且高风险 gate 默认关闭，不代表远端 Join/SAS/Root/Recovery
通过。`multi-device-remote-join` 是另一个显式激活、fail-closed 的双向真实 Join suite：
覆盖 App 新设备 + CLI 管理设备、App 管理设备 + CLI 新设备；根导入、永久 revoke 与 MLS
由各自独立 suite 承担，不属于 Join suite 的通过结论。两个方向均使用独立 native Core root、
受保护配置中的固定测试 OTP 和最终 Registry oracle；CLI 批准走生产前台 TTY，App 批准及高风险操作在 E2E 中使用
明确配置、仅测试可见的 `UserPresencePort`，正式 App 仍使用 macOS LocalAuthentication。
Join 请求发现必须分别经过 CLI foreground listener 的专用 host event 与
App runtime 的 system-notification 全局审批入口；E2E 不得直接调用 Inbox hydration、
`requestSync()` 或 `refreshJoinInbox()` 代替唤醒。Join/Recovery 仍调用真实 purpose-bound
短信接口，测试手机号和六位验证码只从 ignored、权限受限的 local YAML 读取，并由 runner
redact，不能进入 run config、attestation、诊断或报告。
`multi-device-remote-recovery` 先创建远端 ready-admin fixture，再销毁 setup root，并在没有
任何本地身份的 fresh App/native Core root 上经统一登录/注册进入 Join/Recovery 选择；Recovery
覆盖绑定 `awiki.identity.handle-recovery.v1` 与 operation ID 的专用发码、不可逆风险确认、
activate/bounded resume、新本地 owner 安装、Handle 保留和 DID replacement。
该 suite 同时运行第二套独立 App root：旧 App member 的 principal 被 fence 后用 fresh ordinary
Join 加入新 DID，两套 App 的 Registry 与 session 收敛，再与第二个 App 中的独立外部 identity
双向完成 Direct exact-one，并验证 rejoined sibling own-sync。
Join 与 Recovery 专项均可在 Linux Flutter desktop runner 或 macOS runner 执行；完整双 App
Join/re-Join、revoke 与 MLS 矩阵属于第二阶段，不能由本阶段结论外推。
Join 专项还包含 `DEVICE-JOIN-MESSAGE-CORE-E2E-001`：复用已 Join 的 App、同账号 CLI
sibling 和独立 CLI peer，验证 Direct、own-sync、App offline 后同 root 恢复、可见 read
提交以及 Core-directed sync 回到 idle；不得用双 App functional suite 冒充。
注册与 Recovery 可复用 ignored local YAML 中同一测试手机号和固定验证码；它使用仅测试可见的
`UserPresencePort`，不证明真实系统认证。远端 rollout/账号前置条件未就绪
时不得声称通过。其他真实
backend/CLI peer/Personal Agent 使用对应 focused/full E2E，并按宿主平台选择本地 config。
精确 case `multi-device-app-pair-recovery-registration-rejoin-management-transfer`
只接受显式 macOS `awiki.info` 配置。它保留两套 fresh App/Core root，在旧 member 被
Recovery 围栏后从统一 onboarding 重新提交 existing Handle；Dart 只消费 Core opaque
continuation 投影，正式 `UserPresencePort` 确认后由 Core 发起 Recovery-aware Join。审批后
继续执行标准 Root/P5，要求旧 App peer 成为 management-ready admin，再验证双向 Direct
exact-one；不新增 App JSON 通知，也不把 token/transition/owner 选择暴露给 App。
`multi-device-app-pair` 是独立的单机双进程模式：通过通用 Debug 构建脚本生成稳定且不同
bundle ID、独立 Flutter build root 与独立 native Core state root 的管理端/加入端 App，
再由两个 driver 并发操作真实 UI。loopback coordinator 只交换生命周期 checkpoint，并在
内存中比较 SAS；不得调用产品 API、触发 inbox/sync 或持久化秘密。当前该模式仅注册
`DEVICE-JOIN-E2E-004`，不能外推为其他 E2E 已具备 App↔App 覆盖。两个双 App suite 都只在
integration-test provider override 中自动确认 user presence；正式 App 仍使用 macOS
LocalAuthentication。独立的 `multi-device-app-pair-functional` 用真实双 App、Daemon、
Agent Inventory、CLI peer 和远端消息链路验证
Daemon/Codex/Claude Agent 跨设备收敛、普通 P3 消息的双向 sender-side sync 及双端入站消息；它不修改生产授权实现，也不提供 LocalAuthentication 安全 attestation。
其 Account State operator 固定为 Mac→`ssh ali` 的 managed-release argv，
不得把本机误建模为 `/home/ecs-user/...` 服务主机；临时 E2E account 由服务器通过
active Handle 的手机号绑定和受保护的测试手机号摘要授权，App runner 不接收或转发动态
account allowlist。Stage-3 retention-gap operator 同样固定到 Ali 不可变 Message Service
发布、已审查的 Ali `/usr/bin/python3.11` stdlib runtime 与 root-owned、service-group-readable 且不可由 group/other 写入的配置，由服务端显式门禁；Message helper 唯一解析 account 后复用 User
operator 的 active Handle 测试手机号摘要绑定和 active-device 授权，再重验映射、要求
replica 已 bootstrap 并精确更新一个 active stream。App runner 不接收或转发 account
ID/allowlist，闭合 receipt 也不作为消息或恢复 oracle。

⚡触发器：App 目录职责、SDK/App 边界、tenant/state/vault 归属、测试结构或平台支持变化时同步更新本文件。
