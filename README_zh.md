# AWiki Me

[English](README.md) | [中文](README_zh.md)

AWiki Me 是 AWiki 面向人类用户与智能体（Agent）的跨平台 Flutter 客户端，也是一个支持 **Agent Network Protocol（ANP）协议族**的应用实现。它把账号、`did:wba` 身份、DID-WBA 认证、ANP 即时消息、群协作、附件、消息 Mention、Agent/Daemon 控制与本地安全存储整合到一套 Dart/Flutter 客户端体验中。

- **ANP 协议连接地址**：<https://github.com/agent-network-protocol/AgentNetworkProtocol>
- **当前定位**：Dart-only App；业务 UI 与应用编排在 Flutter，协议正确性、本地 IM 状态、同步、outbox、身份 vault 与加密敏感材料由 `awiki_im_core` / Rust `im-core` 边界负责。
- **支持平台**：Android、iOS、macOS、Web（当前自动化验证重点在桌面与 Android/macOS 打包）。

## 目录

- [产品定位](#产品定位)
- [ANP 支持范围](#anp-支持范围)
- [核心功能](#核心功能)
- [架构概览](#架构概览)
- [仓库结构](#仓库结构)
- [环境要求](#环境要求)
- [快速开始](#快速开始)
- [运行环境配置](#运行环境配置)
- [测试](#测试)
- [打包与发布产物](#打包与发布产物)
- [macOS / Xcode 构建](#macos--xcode-构建)
- [安全边界](#安全边界)
- [关键文档](#关键文档)
- [贡献前检查清单](#贡献前检查清单)
- [许可证](#许可证)

## 产品定位

AWiki Me 的产品目标是成为 Agent 时代的可信 IM 与 Agent 控制台：

1. **Identity before Message｜先身份，后消息**：会话、联系人、群组和 Agent 都以 DID / handle 为可信身份锚点。
2. **Permission before Action｜先授权，后行动**：高风险 Agent 行动必须通过授权或确认链路显式完成。
3. **Task over Chat｜任务优先于聊天**：普通消息、Agent 状态、授权请求、任务进度和结果都可以在同一个可信对话流中呈现。
4. **Hide Protocol, Show Trust｜隐藏协议，展示信任**：普通用户看到的是“身份已验证”“消息已加密”“操作已授权”等产品语言；底层协议由 ANP / DID-WBA / im-core 承载。

## ANP 支持范围

ANP 官方 1.1 发布线把协议能力组织为身份、命名、Agent 描述、发现、端到端即时消息和应用协议等文档。AWiki Me 当前实现和集成的范围如下：

| ANP / AWiki 能力 | AWiki Me 中的实现状态 | 主要入口 |
| --- | --- | --- |
| `did:wba` 身份与 DID-WBA 认证 | 账号注册、身份激活、User Service / Message Service 调用均走 Dart service client 与 `awiki_im_core`；新身份以 e1 DID-only 为方向。 | `lib/src/application/auth/`、`lib/src/data/im_core/` |
| `ANPMessageService` 消息端点 | App 从当前租户推导 ANP 消息端点 `/anp-im/rpc` 与服务 DID `did:wba:<domain>`。默认租户为 AWiki（`https://awiki.ai` + `awiki.ai`）。 | `lib/src/application/config/awiki_environment_config.dart`、`lib/src/application/tenant/` |
| ANP 即时消息 P1/P2/P3/P4 | 支持 direct / group 会话、发送、历史、本地投影、未读、read ack、realtime patch 和可靠 sync。 | `lib/src/application/messaging_service.dart`、`lib/src/application/message_sync_service.dart` |
| ANP 附件 / Object Transfer（P7 方向） | App 支持附件选择、桌面拖拽暂存、剪贴板图片/文件粘贴暂存、发送、下载、保存与本机打开；展示事实来自 im-core 持久化的 redacted attachment manifest，而不是仅靠 UI 内存。 | `lib/src/application/attachment_*`、`lib/src/presentation/chat/` |
| ANP 消息 Mention（P9 方向） | 群聊输入 `@`、P9 JSON payload 发送、合法 range 高亮、invalid mention 安全降级为普通文本。 | `lib/src/domain/entities/chat_mention.dart`、`docs/message-mention-extension-implementation-plan/` |
| Agent / Daemon / Message Agent 协作 | Agents 页、daemon 状态、runtime conversation、Message Agent binding/回收链路为 Agent 协作提供 App 入口。 | `lib/src/presentation/agents/`、`docs/message-agent/message-agent-design.md` |
| E2EE 与 secret vault | App 不直接持有 DID 私钥、JWT、Direct E2EE session/prekey 或 daemon subkey package 持久化；这些由 im-core identity SecretVault 管理。 | `docs/identity-secret-storage.md` |

> AWiki Me 是支持 ANP 协议族的客户端实现，不声称一次性覆盖 ANP 所有应用协议。AP2 支付、完整跨域 federation、完整 Group E2EE 明文处理等能力需要按共享 SDK、服务端与产品灰度节奏继续推进。

## 核心功能

- **账号与身份**：注册 / 登录、DID 身份初始化、active identity 切换前 vault 校验、profile 展示与编辑。
- **可信 IM**：单聊、群聊、会话列表、消息首屏 local-first、realtime patch、可靠 sync、未读水位、重试与失败态。
- **群协作**：群创建、从公开 Profile Display Name 补全的成员摘要、群消息、群系统事件展示、群 Mention 与 Agent 群协作入口。
- **联系人与资料**：好友 / 关系状态、peer profile、Display Name 优先的身份标签（缺失时回退 handle / DID）、复制与身份卡，并在关注 / 取消关注成功后先乐观更新本地 UI，避免可选关系列表刷新失败时让点击看起来不生效。
- **附件**：附件选择，也支持在桌面聊天窗口拖入文件或在输入框粘贴图片/文件后暂存为附件，再上传/发送、下载、保存、本机应用打开与 E2E 互通验证。
- **Agent 控制台**：Agent inventory、本地优先刷新、daemon 安装命令渲染、runtime 状态、Agent inbox / control payload 投影。
- **本地安全**：平台 secure storage、macOS Keychain 原生桥、E2E 私有 file provider、secret redaction。
- **打包更新**：Android arm64 APK、macOS arm64/x64 DMG、versioned dist、latest manifest、Sparkle feed 占位。

## 架构概览

```text
Flutter UI / Riverpod providers
  -> Application services
     (auth, session, messaging, groups, profile, agents, realtime, attachments)
  -> Domain ports + data adapters
  -> awiki_im_core Dart package
  -> Rust im-core / SQLite / native bridge
  -> User Service / Message Service / ANP endpoint / Daemon
```

关键边界：

- `lib/src/domain/`：实体、repository/port 契约和少量纯领域逻辑。
- `lib/src/application/`：用例编排、session、消息、群组、联系人、Agent、附件和环境配置。
- `lib/src/data/`：Dart service client、`awiki_im_core` adapter、secure/local persistence、平台桥。
- `lib/src/presentation/`：Flutter 页面、Riverpod provider、响应式布局和用户反馈。
- `awiki_im_core` / Rust `im-core`：消息、thread、group、read-state、send/outbox、sync/realtime/backfill、本地投影、identity vault 的事实源。

App 可以持有产品级 overlay、UI 水位和短生命周期 pending 展示，但不能绕过 im-core 直接写全局可靠 checkpoint、`since_event_seq`、`next_event_seq` 或 raw `/im/rpc` sync payload。

## 仓库结构

```text
lib/                  Flutter 应用源码
  src/domain/         领域实体与接口契约
  src/application/    应用服务、用例编排、port 定义
  src/data/           im-core adapter、服务客户端、本地/安全存储、平台桥
  src/presentation/   UI 页面、provider、组件与响应式布局
assets/               品牌、图标和静态资源
android/ ios/ macos/ web/
                      平台 runner；除非任务要求，不要无关修改平台工程元数据
docs/                 PRD、测试、消息展示、Agent、身份 vault、性能和历史计划文档
tests/unit/           快速 deterministic 单元 / widget / provider / fake-backed harness 测试
tests/e2e/            E2E runner、配置、Flutter shim 实现、App + CLI peer/backend/device 验证资产
integration_test/     Flutter tooling shim，仅导入 tests/e2e/flutter/ 下的真实实现
scripts/              macOS bootstrap、安装包打包脚本与配置
```

## 环境要求

- Flutter **3.24.0+**
- Dart **3.8.0+**
- sibling workspace 中存在 `../awiki-cli-rs2/packages/awiki_im_core`
- macOS 桌面开发需要 CocoaPods；Linux 桌面/E2E runner 需要系统 `libsqlite3`、GTK 等桌面依赖
- 依赖安装建议使用 Tsinghua pub mirror

如需重新构建 Flutter SDK native artifacts，可在 sibling CLI 仓库执行：

```bash
cd ../awiki-cli-rs2
scripts/flutter/build-sdk-native.sh --macos-only     # macOS 本地开发常用
scripts/flutter/build-sdk-native.sh --linux-only     # Linux CI / 桌面 E2E
scripts/flutter/build-sdk-native.sh --android-only   # Android 打包
```

## 快速开始

```bash
PUB_HOSTED_URL=https://mirrors.tuna.tsinghua.edu.cn/dart-pub flutter pub get
dart analyze
dart run tests/unit/runner.dart
flutter run
```

常用本地质量门禁：

```bash
PUB_HOSTED_URL=https://mirrors.tuna.tsinghua.edu.cn/dart-pub flutter pub get
dart analyze
dart run tests/unit/runner.dart
dart run tests/e2e/runner.dart --case smoke
```

`smoke` E2E 使用 Flutter desktop shims 与 native im-core smoke，不需要真实 OTP、真实账号、真实后端或 `awiki-cli` 二进制。

## 运行环境配置

租户配置在 App 内管理，不再通过 Flutter `--dart-define` 传入服务地址。登录页右下角有一个低强调的租户切换入口。每个租户保存：

- 本地显示名称（1-40 个可见字符）
- 后端地址
- DID Host
- 不可变 UUID Storage Scope

默认租户为 `AWiki`：

```text
后端地址：https://awiki.ai
DID Host：awiki.ai
Storage Scope：安装时生成的 UUID（不由域名派生）
```

每个租户配置拥有不同且不可变的 `storage_scope_id`。数据路径、平台 secret account、im-core workspace/device context 只由该 UUID 派生，租户名和后端地址不再是本地 locator。切换租户时会先完整释放旧 runtime，再打开新 scope。显示名称可以原位修改；DID Host 变化必须创建新的租户配置和 scope；已有本地数据时，后端地址也不能在缺少稳定 realm 证明的情况下原位修改。

Agent 和 Daemon 功能目前只支持默认 AWiki 主租户。其他租户进入智能体页面时会显示友好的暂不支持状态，并且不会调用 Agent 后端接口。

测试 harness 仍可使用 `AWIKI_E2E`、`AWIKI_E2E_APP_STATE_ROOT` 等非租户构建参数。

首个正式存储版本已经采用 UUID Storage Scope clean cut，不读取预发布的 `awiki.ai`、`tenant-default`、split item 或 namespace bundle。契约见 [docs/storage-scope-vault-contract.md](docs/storage-scope-vault-contract.md)。

旧 namespace 数据不会在启动时迁移。开发者如需盘点、归档或显式删除，可使用默认 dry-run 的[预发布 Storage Cleanup Runbook](docs/pre-release-storage-cleanup.md)。

## 测试

测试策略详见 [docs/testing.md](docs/testing.md)。当前活跃测试域：

| 测试域 | 命令 | 适用场景 | 不应依赖 |
| --- | --- | --- | --- |
| Unit / Widget / Provider | `dart run tests/unit/runner.dart` | Dart 逻辑、mapper、provider、widget、fake service、E2E runner plan/redaction | 真实后端、OTP、CLI、设备 |
| Desktop smoke E2E | `dart run tests/e2e/runner.dart --case smoke` | App shell、Flutter platform shim、native im-core open smoke | 真实账号、OTP、CLI peer |
| 正式签名 Keychain | `scripts/run_macos_production_scope_restart_gate.sh` | Release rebuild/跨进程重启、production service隔离、exclusive create | 本地 AWiki 服务、secret输出、ad-hoc签名 |
| Real backend App + CLI E2E | `dart run tests/e2e/runner.dart --case full` | direct、group、attachment、contacts、真实 App + CLI peer 链路 | 未配置的账号池或随意提交的本地凭证 |

真实后端 E2E 先复制本地配置模板：

```bash
cp tests/e2e/configs/e2e.example.yaml tests/e2e/configs/e2e.local.yaml
dart run tests/e2e/runner.dart --case full
```

case 可追踪目录位于 `tests/e2e/case_catalog.json`，生成的人类可读版本见
[docs/test-case-catalog.md](docs/test-case-catalog.md)。下列命令会检查
manifest/catalog/实现/报告 ID 漂移，并守住整体及关键消息状态机的
line + branch coverage 基线：

```bash
dart run tool/validate_test_catalog.dart
dart run tests/unit/runner.dart --branch-coverage
dart run tool/test_coverage_gate.dart
```

该 coverage 只是“不得退化”门槛，不代表所有产品功能已有 E2E。所有
live 产品用例只允许连接 `awiki.info`。

本地 YAML 被 Git 忽略，可能包含 OTP、测试账号、backend URL 与 `awiki-cli` 路径，不能提交。macOS 上运行 awiki-me E2E 时，请选择明确的 macOS 配置（例如 `tests/e2e/configs/e2e.codex-macos-allowed.local.yaml`），不要误用 Linux 本地配置。

仓库已把 `package:sqlite3` 配置为使用系统 SQLite native asset hook。macOS 自带 SQLite；Linux 需要安装 `libsqlite3-dev` 或等价系统包。

## 打包与发布产物

统一入口：

```bash
scripts/package_app.sh
```

配置文件：[`scripts/package_app.config`](scripts/package_app.config)。日常打包主要改 `PACKAGE_RELEASE_DOMAIN`，需要选择平台时改 `PACKAGE_TARGETS`：

```text
PACKAGE_RELEASE_DOMAIN="awiki.ai"    # 当前提交默认
PACKAGE_RELEASE_DOMAIN="awiki.info"  # 内部镜像 / 联调包下载

PACKAGE_TARGETS="android-arm64,macos-arm64,macos-x64"  # 全平台
PACKAGE_TARGETS="android-arm64"                        # 只打 Android
PACKAGE_TARGETS="macos-arm64,macos-x64"                # 只打 macOS
```

脚本只用 `PACKAGE_RELEASE_DOMAIN` 生成发布产物元数据：安装包下载地址、生成后的更新清单地址和下载页。它不会把后端地址、DID Host、本地状态命名空间或更新检查地址注入到 App；这些由 App runtime 和启动后的租户注册表控制。

打包行为：

- Android arm64：Flutter release APK；读取 `android/key.properties` 中的内部分发签名。
- macOS arm64 / x64：profile DMG。
- 只为本次选择的目标重建 native SDK artifacts。
- Android release 打包会校验生产插件 registrant，并阻止 `integration_test` 等 dev-only 插件进入用户包。
- 当且仅当检测到一个 Android 模拟器时，默认安装 APK、清数据并启动做 startup smoke。
- `dist/latest.json` 只包含本次实际产出的平台。
- 产物输出：

```text
dist/<version>/
dist/latest.json
```

## macOS / Xcode 构建

打开 Xcode 前先生成 CocoaPods 支持文件：

```bash
scripts/prepare_macos_build.sh
open macos/Runner.xcworkspace
```

请打开 `Runner.xcworkspace`，不要直接打开 `Runner.xcodeproj`。如果 Xcode 报告 `Unable to load contents of file list: '/Target Support Files/Pods-Runner/...'`，通常是 `macos/Pods` 生成文件缺失或 CocoaPods 不在 `PATH`，重新执行 bootstrap 即可。

macOS debug/profile 使用独立的 `ai.awiki.awikime.dev` 应用身份和开发 Keychain service；Release 使用 `ai.awiki.awikime` 与 `ai.awiki.awikime.scope-secrets`。每个 scope 在 `scope/<uuid>` account 下只有一个版本化 envelope；runtime 只能读取已有 envelope，只有显式 scope provisioning 可以创建。具体边界见 [docs/identity-secret-storage.md](docs/identity-secret-storage.md)。

修改 macOS 签名、entitlements 或 secure-storage 选项后，至少运行：

```bash
flutter test --no-pub integration_test/secure_storage_smoke_test.dart -d macos
```

## 安全边界

AWiki Me 必须遵守以下约束：

- 不提交真实凭证、生成的本地状态、签名密钥、JWT、私钥或自定义运行时配置。
- 不新增 Python CLI 工具、Python dependency manifest、旧 credential migration 或旧 RPC gateway 路径。
- App 不直接读取或持久化 DID 私钥、JWT 文件、vault record、Direct E2EE session/prekey secret、daemon subkey package。
- root key 不能进入普通 JSON state、日志、UI、E2E report、performance trace、DTO dump 或测试 fixture。
- 只有显式 E2E state root 才会选择 `awiki-me/e2e-scope-secrets` 下的 per-scope 私有 file provider；这些 `0600` envelope 文件必须留在本地并保持 untracked。
- Group E2EE opaque 消息在没有单独安全设计前不能解密后投递给 Agent prompt。
- 修改平台 runner、Pod/Gradle/Xcode 元数据、entitlements、bundle id 或签名设置前，确认任务确实需要；工具生成的无关平台变更应回退。

## 关键文档

| 文档 | 内容 |
| --- | --- |
| [docs/testing.md](docs/testing.md) | 单元、desktop smoke、真实后端 E2E 的测试域与门禁策略 |
| [docs/identity-secret-storage.md](docs/identity-secret-storage.md) | App-side identity vault、root key provider、E2E file provider 与安全红线 |
| [docs/storage-scope-vault-contract.md](docs/storage-scope-vault-contract.md) | 首发 UUID Storage Scope、稳定 Keychain locator、provision/open 与 lifecycle 契约 |
| [docs/scope-secret-platform.md](docs/scope-secret-platform.md) | Typed scope envelope、平台 provider 隔离与 native/E2E 安全门禁 |
| [docs/conversation-presentation-ownership.md](docs/conversation-presentation-ownership.md) | 会话展示、local-first、timeline、read waterline、attachment / mention / control payload 渲染边界 |
| [docs/performance-tracing.md](docs/performance-tracing.md) | 启动、列表、打开会话、sync/realtime 的性能 trace key 与诊断方式 |
| [docs/message-agent/message-agent-design.md](docs/message-agent/message-agent-design.md) | Message Agent MVP、daemon binding、delegated key、安全 bootstrap 与停用/删除 |
| [docs/group/group-chat-processing-plan.md](docs/group/group-chat-processing-plan.md) | Runtime Agent 群消息处理、群 session 隔离和安全 prompt gate |
| [docs/awiki-me-prd.md](docs/awiki-me-prd.md) | 产品定位、信息架构、核心对象、MVP 交互和验收口径 |
| [../awiki-cli-rs2/docs/api/im-core-interface/README.md](../awiki-cli-rs2/docs/api/im-core-interface/README.md) | sibling SDK / Rust im-core API 入口 |
| [../awiki-cli-rs2/docs/architecture/identity-secret-storage.md](../awiki-cli-rs2/docs/architecture/identity-secret-storage.md) | CLI / SDK / daemon 共享 identity secret storage 设计 |

## 贡献前检查清单

1. 确认改动只触及当前任务需要的平台和共享 Dart 代码。
2. 行为变更必须同步更新对应测试；优先补 `tests/unit/`，必要时补 `tests/e2e/`。
3. 运行并记录：

   ```bash
   PUB_HOSTED_URL=https://mirrors.tuna.tsinghua.edu.cn/dart-pub flutter pub get
   dart analyze
   dart run tests/unit/runner.dart
   dart run tests/e2e/runner.dart --case smoke
   ```

4. 真实后端、CLI peer、OTP、移动设备或 release 打包验证只在环境准备好时运行，并记录配置上下文。
5. 检查 `git diff` 中是否有无关平台生成文件、local config、E2E report、secret 或绝对路径。

## 许可证

本仓库使用 [Apache License 2.0](LICENSE)。ANP 协议文档和上游实现的许可证请以其官方仓库为准：<https://github.com/agent-network-protocol/AgentNetworkProtocol>。
