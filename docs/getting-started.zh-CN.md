# 开始使用 AWiki Me

[English](getting-started.md) | [简体中文](getting-started.zh-CN.md)

本文面向两类读者：

- 希望安装并体验 AWiki Me 的早期用户；
- 需要从源码运行客户端的开发者。

## 1. 当前可用范围

当前发布与验证重点：

- macOS arm64 / x64；
- Android arm64。

iOS 可用于开发构建，但当前默认打包流程不生成 iOS 发布包。Web 目前不可用，因为 `awiki_im_core` Web 入口是运行时 stub。

## 2. 安装发布版

仓库当前具备生成 macOS DMG 和 Android arm64 APK 的打包脚本，但对外 README 必须只链接已验证、可长期访问且签名状态明确的官方产物。

发布负责人补充链接时，建议使用以下结构：

```markdown
- [下载 macOS Apple Silicon 版](<official-url>)
- [下载 macOS Intel 版](<official-url>)
- [下载 Android arm64 APK](<official-url>)
- [查看版本说明](<release-notes-url>)
```

不要链接：

- 临时 GitHub Actions artifact；
- 未签名或 ad-hoc 签名的 macOS Release 包；
- 开发测试 APK；
- 内部域名或需要组织权限的地址。

## 3. 从源码运行

### 3.1 依赖

- Flutter 3.41.0 或更高；
- Dart 3.8.0 或更高；
- 与当前 App 版本兼容的 `awiki-cli-rs2` sibling checkout；
- iOS 与 macOS 开发需要 CocoaPods；
- Android 开发需要 Android SDK 与可用设备/模拟器；
- Linux 桌面/E2E runner 需要系统 SQLite 与桌面依赖，但 Linux 当前不是 AWiki Me 对外产品目标。

先检查环境：

```bash
flutter doctor -v
dart --version
```

### 3.2 目录布局

```text
workspace/
├── awiki-cli-rs2/
└── awiki-me/
```

`awiki-me/pubspec.yaml` 通过以下相对路径读取 SDK：

```text
../awiki-cli-rs2/packages/awiki_im_core
```

因此两个仓库不能随意放在无关目录，也不能使用不兼容的分支或 commit。

### 3.3 macOS

```bash
cd awiki-cli-rs2
scripts/flutter/build-sdk-native.sh --macos-only

cd ../awiki-me
flutter pub get
dart analyze
dart run tests/unit/runner.dart
dart run tests/e2e/runner.dart --case smoke
flutter run --debug -d macos
```

如需使用 Xcode：

```bash
scripts/prepare_macos_build.sh
open macos/Runner.xcworkspace
```

请打开 `Runner.xcworkspace`，不要直接打开 `Runner.xcodeproj`。

### 3.4 Android

```bash
cd awiki-cli-rs2
scripts/flutter/build-sdk-native.sh --android-only

cd ../awiki-me
flutter pub get
flutter devices
flutter run -d <android-device-id>
```

当前发布产物面向 Android arm64。开发者应自行确认设备架构与 Android SDK 配置。

### 3.5 iOS

```bash
cd awiki-cli-rs2
scripts/flutter/build-sdk-native.sh --ios-only

cd ../awiki-me
flutter pub get
cd ios && pod install && cd ..
flutter build ios --simulator --debug
open -a Simulator
flutter devices
flutter run --debug -d <ios-simulator-id>
```

如需使用 Xcode：

```bash
open ios/Runner.xcworkspace
```

请打开 `Runner.xcworkspace`，不要直接打开 `Runner.xcodeproj`。模拟器构建不需要 Apple 开发者签名；真机运行需要在 Xcode 的 Runner target 中选择自己的 Team，并保持自动签名开启。

iOS 当前应描述为开发目标，而不是已验证的公开发布平台。当前工程支持 iOS 13+、iPhone/iPad、`UIScene` 生命周期、Debug/Profile/Release CocoaPods 配置，以及 `awiki_im_core` 的 arm64 真机与 arm64/x86_64 模拟器切片。发布前仍需要补充真机网络、后台行为、安全存储和分发验证。

### 3.6 可选依赖镜像

依赖网络受限时，可使用仓库现有建议：

```bash
PUB_HOSTED_URL=https://mirrors.tuna.tsinghua.edu.cn/dart-pub flutter pub get
```

公共文档应同时保留不依赖特定地区镜像的标准 `flutter pub get` 路径。

## 4. 第一次启动

1. 启动 App；
2. 在登录页使用默认 AWiki 租户，或打开低强调度的租户切换入口；
3. 注册新身份或登录现有身份；
4. 等待 Storage Scope、SecretVault 与 active identity 验证完成；
5. 进入消息页。

Debug/Profile 与已安装 Release App 使用不同的应用身份、本地数据根目录和 Keychain service。开发构建不应读取或修改正式版本数据。

## 5. 第一次有意义的成功

建议使用两个测试身份或一个 App 身份加一个 CLI peer：

1. 在 AWiki Me 中打开联系人页；
2. 输入对方完整 handle 或 DID；
3. 打开 Direct 会话；
4. 发送一条文本消息；
5. 确认发送状态、会话预览与时间线立即更新；
6. 从对端回复；
7. 确认 unread/read 状态与实时/同步恢复正常。

随后可以继续验证：

- 发送文件或图片附件；
- 创建或加入群组；
- 在群消息中使用 `@` Mention；
- 打开 Agent 页面查看 Daemon 或 Agent 状态。

## 6. 自定义租户

每个租户包含：

- 展示名称；
- backend base URL；
- DID host；
- 不可变 `storage_scope_id`。

租户显示名、后端 URL 和 DID host 不是本地安全存储 locator。每个租户的本地路径、SecretVault 和 Core runtime 由不可变 UUID scope 隔离。

重要边界：

- 修改 DID host 应创建新租户与新 scope；
- 已存在本地数据时，不应直接重写后端路由；
- 切换租户前必须完整释放旧 realtime、Core 和 SQLite runtime；
- Agent/Daemon 功能当前只对精确 allowlist realm 启用。

## 7. 常见问题

### 找不到 `awiki_im_core`

确认 sibling 目录存在：

```bash
ls ../awiki-cli-rs2/packages/awiki_im_core/pubspec.yaml
```

并确认两个仓库使用兼容版本。

### macOS CocoaPods 文件缺失

```bash
scripts/prepare_macos_build.sh
open macos/Runner.xcworkspace
```

### Native SDK 未生成

在 `awiki-cli-rs2` 中为当前平台执行：

```bash
scripts/flutter/build-sdk-native.sh --macos-only
# 或 --android-only / --ios-only / --linux-only
```

### App 可以启动但无法使用自托管 Agent 功能

基础租户连接与 Agent/Daemon 功能采用不同边界。当前 Agent realm allowlist 为：

- `awiki.ai`
- `awiki.info`
- `anpclaw.com`

其他域名会 fail closed，不调用 Agent 后端 API。参见 [兼容性文档](compatibility.zh-CN.md)。

### Web 构建能通过但运行失败

当前 `awiki_im_core` 的 Flutter Web 入口是 stub，会抛出 `UnsupportedError`。不要把 Web 构建成功解释为产品可用。
