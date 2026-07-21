# AWiki Me 开发指南

[English](development.md) | [简体中文](development.zh-CN.md)

## 1. 技术栈

- Flutter 3.41+；
- Dart 3.8+；
- Riverpod；
- sibling `awiki_im_core` Flutter/Dart SDK；
- Rust `awiki-im-core` 与 SQLite native bridge；
- Android、iOS、macOS 平台 runner。

## 2. 分层

```text
lib/src/presentation/   页面、Provider、组件、响应式布局和用户反馈
lib/src/application/    用例编排、session、消息、群组、联系人、Agent、附件、租户
lib/src/domain/         实体、repository/port 契约和纯领域逻辑
lib/src/data/           service client、im-core adapter、local/secure storage、平台桥
```

核心规则：

- App 使用高层 `awiki_im_core` API；
- 不在 Dart UI 层重建 DID proof、raw RPC、WebSocket frame、可靠 checkpoint 或 E2EE 内部状态；
- 产品 overlay 可以存在，但不能覆盖 Core 的事实源；
- 行为变化必须有对应测试。

## 3. 环境准备

```bash
cd ../awiki-cli-rs2
scripts/flutter/build-sdk-native.sh --macos-only

cd ../awiki-me
flutter pub get
```

按平台替换：

```bash
scripts/flutter/build-sdk-native.sh --linux-only
scripts/flutter/build-sdk-native.sh --android-only
scripts/flutter/build-sdk-native.sh --ios-only
```

## 4. 高频开发 Gate

```bash
dart analyze
dart run tests/unit/runner.dart
dart run tests/e2e/runner.dart --case smoke
```

分支覆盖与回归底线：

```bash
dart run tests/unit/runner.dart --branch-coverage
dart run tool/test_coverage_gate.dart
```

真实远端 App + CLI peer：

```bash
cp tests/e2e/configs/e2e.example.yaml tests/e2e/configs/e2e.local.yaml
dart run tests/e2e/runner.dart --case full
```

真实配置、OTP、账号、CLI path 和报告不得提交。

## 5. 测试归属

| 目录 | 责任 |
| --- | --- |
| `tests/unit/` | 纯 Dart、Widget、Provider、Mapper、Fake-backed service 与 runner 逻辑 |
| `tests/e2e/` | 桌面用户流、平台 shim、native plugin、CLI peer、后端和设备编排 |
| `integration_test/` | Flutter tooling 发现入口，仅保留 thin import |
| `.e2e/` | 本地报告和状态，必须被 Git 忽略 |

不要把真实业务 E2E 逻辑放在根 `integration_test/`。

## 6. 仓库结构

```text
lib/                  Flutter 应用源码
assets/               品牌、图标和静态资源
android/ ios/ macos/ web/
                      平台 runner
packages/             如存在，仅放 App 内部 package
scripts/              bootstrap、打包、签名和验证脚本
docs/                 产品、架构、安全、测试和实现计划
tests/unit/            快速确定性测试
tests/e2e/             E2E runner 与平台实现
```

## 7. 租户与配置

普通开发使用 App 内租户切换器。不要为每个服务 URL 增加新的 Flutter flag。

唯一的内置主租户编译覆盖：

```bash
flutter build macos --debug \
  --dart-define=AWIKI_PRIMARY_TENANT_DOMAIN=awiki.info
```

该值只影响新 tenant registry 的初始内置租户，不是运行时选择器，也不会重写已有 scope。

## 8. 打包

```bash
scripts/package_app.sh
```

默认产出：

```text
dist/<version>/
dist/latest.json
```

目标由 `scripts/package_app.config` 控制：

```text
android-arm64
macos-arm64
macos-x64
windows-x64
```

默认值仍保持 Android arm64 与 macOS 双架构，Windows 需要显式选择。本地脚本会校验 APP/Core 工作树干净且当前提交已经精确推送，随后触发固定版本的 GitHub Actions 工作流、等待唯一 request ID 并下载聚合产物；它不会修改 `pubspec.yaml`，也不会在 Mac 本机编译安装包。

macOS 试用/正式包必须使用稳定的非 ad-hoc 签名 identity。Android/macOS 签名材料及私有 Core 仓库只读 token 放在受保护的 `app-packaging` GitHub Environment；私钥、`.p12`、`.pfx` 和本地签名配置不得进入仓库。本阶段 Windows 安装器明确不签名。安装器、数据保留和 CI 细节见 [Windows x64 packaging](windows-packaging.md)。

## 9. 变更检查

提交前确认：

- 没有工具生成的无关 Xcode/Gradle/Pod 元数据；
- 没有真实 token、私钥、OTP、本地 YAML、E2E 报告或绝对路径；
- 新 UI 有 Widget/Provider 测试；
- 平台行为有 Smoke E2E；
- 跨 App/CLI/服务行为有可复现的 E2E 记录；
- README、截图和兼容性文档与行为一致。
