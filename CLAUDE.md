# awiki-me/

> Repository context | Parent workspace: [../CLAUDE.md](../CLAUDE.md) | Local rules: [AGENTS.md](AGENTS.md)

1. **地位**：AWiki 跨平台 Flutter App，面向人类用户和 Agent，承载身份 onboarding、tenant 管理、会话/群组/附件/Mention、Agent/Daemon 控制和产品 UI。
2. **边界**：App 拥有 UI、导航、application orchestration、平台适配、短期交互状态和 presentation overlay；消息、conversation、read-state、sync/outbox、identity vault 与密码正确性由 sibling `../awiki-cli-rs2/packages/awiki_im_core` / Rust `im-core` 提供。
3. **约束**：
   - 不直接拼 message-service wire、读 raw SQLite、写 reliable checkpoint 或持有 DID/E2EE 私钥。
   - `ProductLocalStore` 只保存 App overlay，不建立第二套 durable message truth。
   - tenant 切换必须先释放旧 runtime，并按不可变 Storage Scope 隔离 identity、conversation、cache 与 vault。
   - Agent/Daemon 能力按 App 内置 realm 白名单 fail-closed；仅当 HTTPS backend host 与 DID Host 相同且命中 `awiki.ai`、`awiki.info`、`anpclaw.com` 时启用。
   - 行为和 UI 变化同时更新 `tests/unit/`；真实 backend、CLI peer、平台或设备流程变化同步更新 `tests/e2e/`。
   - 平台 runner 变更只触及任务明确要求的平台，避免提交无关生成文件。

## 主要目录

| 路径 | 职责 |
|---|---|
| `lib/src/domain/` | Domain entities、ports 和纯业务约束 |
| `lib/src/application/` | auth/session/messaging/groups/profile/agents/attachments/tenant 等用例编排 |
| `lib/src/data/` | `awiki_im_core` adapters、service clients、local/secure storage 与 platform bridge |
| `lib/src/data/storage/` | UUID Storage Scope registry/manifest/layout、provision/recovery、strict envelope、platform/E2E secret provider及统一root解析；runtime只可openExisting |
| `lib/src/presentation/` | Flutter 页面、Riverpod providers、组件、响应式布局和反馈 |
| `tests/unit/` | 快速确定性 unit/widget/provider/fake-backed tests；line/branch baseline 由 `tests/quality/coverage_baseline.json` 约束 |
| `tests/e2e/` | audited suite manifest + case catalog/checker、killable runner、schema-v2 case/assertion attestation、首失败脱敏诊断、configs、Flutter implementations、真实远端 `awiki.info` App+CLI/backend/device flows与资源台账 |
| `integration_test/` | Flutter tooling 薄 shim； durable scenario 在 `tests/e2e/flutter/` |
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
```

真实 backend/CLI peer/Personal Agent 使用对应 focused/full E2E，并按宿主平台选择本地 config。

⚡触发器：App 目录职责、SDK/App 边界、tenant/state/vault 归属、测试结构或平台支持变化时同步更新本文件。
