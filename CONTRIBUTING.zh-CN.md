# 参与贡献 AWiki Me

[English](CONTRIBUTING.md) | [简体中文](CONTRIBUTING.zh-CN.md)

感谢你帮助改进 AWiki Me。项目同时涉及 Flutter 产品体验、共享 IM Core、平台安全存储和跨客户端消息语义，因此贡献应尽量保持范围明确、行为可验证。

## 开始之前

- 先搜索现有 Issue 和 PR；
- 对较大功能、协议变化或平台元数据改动，先通过 Issue 说明目标、用户价值和边界；
- 不要在一个 PR 中混入无关格式化、Xcode/Gradle 生成文件或 sibling SDK 重构；
- 涉及 `awiki_im_core` / `awiki-im-core` 的行为，应在对应仓库同步设计和测试。

## 环境

```bash
cd ../awiki-cli-rs2
scripts/flutter/build-sdk-native.sh --macos-only

cd ../awiki-me
flutter pub get
```

按目标平台替换 native SDK 构建参数。

## 提交前 Gate

```bash
dart analyze
dart run tests/unit/runner.dart
dart run tests/e2e/runner.dart --case smoke
```

涉及关键状态机或覆盖基线时：

```bash
dart run tests/unit/runner.dart --branch-coverage
dart run tool/test_coverage_gate.dart
```

真实后端、CLI peer、OTP、移动设备或发布签名测试，仅在环境准备完成时运行，并在 PR 中记录配置上下文和结果。

## 测试要求

- Domain、Mapper、Provider、Service 和 Widget 变化优先补 `tests/unit/`；
- App 启动、导航、平台桥或 screenshot-visible UI 变化补 `tests/e2e/` smoke；
- 跨 App/CLI/服务、附件、群组和设备行为补对应 E2E runner 资产；
- 无法完成昂贵 E2E 时，必须记录 case、owner、blocker 和 follow-up，不得把跳过描述为通过。

## 架构规则

- Flutter 层调用高层 `awiki_im_core` API；
- 不在 App 重建 raw RPC、WebSocket、DID proof、可靠 sync checkpoint 或 E2EE 私有状态；
- Core 是消息、会话、read state、outbox、sync 和 identity vault 的事实源；
- App 可以维护短生命周期 pending UI 和产品 overlay，但不得覆盖 Core 的持久化事实；
- 平台 runner、签名、entitlement、Bundle ID 或 Pod/Gradle 元数据只在任务确有需要时修改。

## 安全与隐私

禁止提交：

- 私钥、JWT、bearer token、OTP；
- `.p12`、`.pfx`、签名身份和 Team ID 私有配置；
- 本地 E2E YAML、账号池、报告和生成状态；
- 真实 DID、手机号、邮箱或消息；
- 绝对路径和内部服务地址；
- SecretVault envelope、root key 或 raw secure DTO dump。

安全问题请按 [SECURITY.md](SECURITY.zh-CN.md) 私下报告。

## PR 描述建议

```text
What changed
Why it matters to users
Affected platforms
Affected protocol/core boundaries
Tests run
Screenshots or recordings
Known limitations / follow-up
```

涉及 UI 的 PR 请附真实运行截图，并确认 README 素材是否需要同步更新。
