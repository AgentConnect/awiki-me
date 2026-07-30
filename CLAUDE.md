# awiki-me/

> Repository context | Parent workspace: [../CLAUDE.md](../CLAUDE.md) | Local rules: [AGENTS.md](AGENTS.md)

1. **地位**：AWiki 跨平台 Flutter App，面向人类用户和 Agent，承载身份 onboarding、tenant 管理、会话/群组/附件/Mention、Agent/Daemon 控制和产品 UI。
2. **边界**：App 拥有 UI、导航、application orchestration、平台适配、短期交互状态和 presentation overlay；消息、conversation、read-state、sync/outbox、identity vault 与密码正确性由 sibling `../awiki-cli-rs2/packages/awiki_im_core` / Rust `im-core` 提供。
3. **约束**：
   - 不直接拼 message-service wire、读 raw SQLite、写 reliable checkpoint 或持有 DID/E2EE 私钥。
   - `ProductLocalStore` 只保存 App overlay，不建立第二套 durable message truth。
   - tenant 切换必须先释放旧 runtime，并按不可变 Storage Scope 隔离 identity、conversation、cache 与 vault。
   - 设备管理等高风险操作通过 `UserPresencePort` 调用系统认证，设备不支持、用户取消或平台认证失败时必须 fail closed。
   - `system_notification_changed` 仅作为设备域因果失效信号：App 必须独立读取 Core typed Join inbox 并展示全局审批入口，不能等待通用 message sync 成功，也不能从 realtime payload 直接构造请求、自动验证/拒绝/批准。
   - Android/iOS remote push transport 是进程级平台能力，不随 tenant runtime 重建；Push 只作为同步提示，不能成为消息或未读状态的事实来源。
   - Realtime/Push 都只是同步提示；前台会话必须以有界周期触发 Core reliable sync，补偿提示丢失，并在后台停止，不能把 WebSocket 投递当作可靠消息事实源。
   - 无业务消息体但携带 Core `sync` hint 的 realtime 事件必须保留为 sync-only `RealtimeUpdate` 并调度 reliable sync；普通 P3 Direct 的兄弟设备 outgoing 投影来自 sender owner 的 `sync.delta` / `sync.thread_after`，不能由 App 构造 plain own-sync 或升级为 P5。App 使用的稳定 conversationId 只是展示/存储路由，普通 Direct 的不可变 wire identity 仍由 Core 保持为 `direct + peer DID`。
   - Agent 页面以 User Service Inventory 为存在性基线，以 IM Core committed control patch 为运行状态/因果失效信号，以 App pending intent 为短期交互层；realtime control 只触发 reliable sync，不能直接成为 Agent UI 真相。typed account binding 存在时，Agent provider 的 cache/load owner 必须是稳定 `owner_identity_id + account_id`，应用权威 Inventory 后标记同一 owner 与当前 session operation 已加载，不能因 Handle/DID key 不一致阻塞 create pending 首帧。权威 Inventory 中的 runtime Agent 在发布到 UI 前通过 Core Directory 投影 canonical Direct route，失败不伪造 Persona，并由后续 Inventory 对账重试。可见 Agent 页面在 App 前台按 30 秒静默重读 Inventory，以补偿失效信号丢失，页面销毁或 App 后台时不发起对账。
   - Agent/Daemon 能力按 App 内置 realm 白名单 fail-closed；仅当 HTTPS backend host 与 DID Host 相同且命中 `awiki.ai`、`awiki.info`、`anpclaw.com` 时启用。
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
- [docs/handle-recovery-ui.md](docs/handle-recovery-ui.md)：默认关闭的 Handle Recovery begin/status/cancel/finalize、独立二次 OTP、secret-free 旧管理设备通知、fresh user-presence 取消与本地-only dismiss 边界。
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
# Requires reviewed awiki.info rollout/account env and real macOS user presence:
dart run tests/e2e/runner.dart --case multi-device-remote-join --config <local-awiki-info-config.yaml>
dart run tests/e2e/runner.dart --case multi-device-app-pair --config <local-awiki-info-config.yaml>
dart run tests/e2e/runner.dart --case multi-device-app-pair-functional --config <local-awiki-info-config.yaml>
dart run tests/e2e/runner.dart --case multi-device-remote-recovery --config <local-awiki-info-config.yaml>
dart run tests/e2e/runner.dart --case multi-device-remote-mls --config <local-awiki-info-config.yaml>
```

`multi-device` 当前只证明默认关闭与 Join-only 公共入口，不代表远端 Join/SAS/Root/Recovery
通过。`multi-device-remote-join` 是另一个显式激活、fail-closed 的双向真实 Join suite：
覆盖 App 新设备 + CLI 管理设备、App 管理设备 + CLI 新设备；根导入、永久 revoke 与 MLS
由各自独立 suite 承担，不属于 Join suite 的通过结论。两个方向均使用独立 native Core root、动态
OTP 和最终 Registry oracle；CLI 批准走生产前台 TTY，App 批准及高风险操作要求真实 macOS
user-presence。Join 请求发现必须分别经过 CLI foreground listener 的专用 host event 与
App runtime 的 system-notification 全局审批入口；E2E 不得直接调用 Inbox hydration、
`requestSync()` 或 `refreshJoinInbox()` 代替唤醒。显式 staged-OTP operator 模式只接受固定 SSH argv 与闭合 RFC7807 503，且
只执行 Ali 不可变发布、显式受保护配置并禁止写入 Python bytecode，不证明短信送达。
`multi-device-remote-recovery` 使用两个隔离账号/设备根，覆盖 durable 旧
管理设备通知与真实系统认证取消，以及请求设备真实冷静期、独立二次 OTP 和新 DID 激活；
它明确拒绝 staged SMS error，必须证明产品发码路径成功。远端 rollout/账号前置条件未就绪
时不得声称通过。其他真实
backend/CLI peer/Personal Agent 使用对应 focused/full E2E，并按宿主平台选择本地 config。
`multi-device-remote-mls` 复用同一受审计远端合同，但以真实 App owner 和独立 CLI Core
root 覆盖 Add/Welcome、未来群文本/附件以及精确设备 Remove；实现可执行不代表已经取得
远端 pass 证据。

`multi-device-app-pair` 是独立的单机双进程模式：通过通用 Debug 构建脚本生成稳定且不同
bundle ID、独立 Flutter build root 与独立 native Core state root 的管理端/加入端 App，
再由两个 driver 并发操作真实 UI。loopback coordinator 只交换生命周期 checkpoint，并在
内存中比较 SAS；不得调用产品 API、触发 inbox/sync 或持久化秘密。当前该模式仅注册
`DEVICE-JOIN-E2E-004`，不能外推为其他 E2E 已具备 App↔App 覆盖。独立的
`multi-device-app-pair-functional` 只在 integration-test provider override 中自动确认
user presence，用真实双 App、Daemon、Agent Inventory、CLI peer 和远端消息链路验证
Daemon/Codex/Claude Agent 跨设备收敛、普通 P3 消息的双向 sender-side sync 及双端入站消息；它不修改生产授权实现，也不提供 LocalAuthentication 安全 attestation。
其 Account State operator 固定为 Mac→`ssh ali` 的 managed-release argv，
不得把本机误建模为 `/home/ecs-user/...` 服务主机。

⚡触发器：App 目录职责、SDK/App 边界、tenant/state/vault 归属、测试结构或平台支持变化时同步更新本文件。
