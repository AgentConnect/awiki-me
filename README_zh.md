# AWiki Me Flutter 应用

AWiki Me 是一个纯 Dart/Flutter 消息客户端，基于 ANP Dart SDK 构建。账号创建、
DID-WBA 认证、User Service 调用、IM 与消息 proof 生成都由 Dart 侧完成。

## 环境要求

- Flutter 3.24.0 或更高版本，并包含 Dart 3.8.0 或更高版本

## 快速开始

```bash
PUB_HOSTED_URL=https://mirrors.tuna.tsinghua.edu.cn/dart-pub flutter pub get
dart analyze
flutter test tests/unit_test
flutter run
```

## 在 macOS / Xcode 中编译

打开 Xcode 前先生成 CocoaPods 支持文件：

```bash
scripts/bootstrap_macos.sh
open macos/Runner.xcworkspace
```

请打开 `Runner.xcworkspace`，不要直接打开 `Runner.xcodeproj`。如果 Xcode
提示类似 `Unable to load contents of file list: '/Target Support Files/Pods-Runner/...'`，
说明 `macos/Pods` 生成文件缺失或 `pod` 不在 `PATH`，重新运行上面的
bootstrap 脚本即可。

开发版 macOS 构建通常是 ad-hoc 签名。为避免后端注册成功后因 Keychain
写入失败而表现为“注册失败”，debug/profile 构建会把账号凭证写入应用支持目录下的
`awiki_me_credentials.json`；release 构建仍使用平台安全存储。

im-core 身份 vault root key 和 device id 在普通运行中仍写入 macOS 登录钥匙串。
AWiki 原生 Keychain 桥只在创建新项目时设置当前 App 可执行文件的访问控制；普通读取
和更新不会反复改写 Keychain 项目的访问许可，避免 Xcode 本地调试时频繁出现“更改访问
许可/所有者”的系统授权弹窗。真实用户通常只应在首次访问、旧存储迁移，或本地重新编译
后的可执行文件身份与旧钥匙串项目不匹配时看到授权提示；稳定签名的 release 版本不应每
次启动都弹。

## 打包

客户端安装包的统一入口是：

```bash
scripts/package_app.sh
```

打包配置都放在 `scripts/package_app.config`。脚本不接受命令行参数，也不通过
环境变量读取打包配置。日常打包通常只需要修改 `AWIKI_BASE_URL`；当前这种
可正常安装使用、但不是应用商店正式签名的安装包，保留 `PACKAGE_CHANNEL="test"`
即可。渠道只用于隔离输出目录、文件名和 `latest.json`，不代表应用商店发布状态，
也不控制代码签名。

脚本固定使用 release 模式，并固定输出 Android arm64、macOS arm64 和 macOS
x64 三个平台产物。打包前也会固定重新构建原生 SDK 产物。

当前提交的配置用于线上测试环境可安装包：

```text
PACKAGE_CHANNEL="test"
AWIKI_BASE_URL="https://anpclaw.com"
```

如果后续要切到稳定分发轨道，修改同一个配置文件即可，例如：

```text
PACKAGE_CHANNEL="stable"
AWIKI_BASE_URL="https://awiki.info"
```

产物和 `latest.json` 会输出到：

```text
dist/<channel>/<version>/
dist/<channel>/latest.json
```

## 项目结构

- `lib/`：应用、领域、数据与界面源码
- `assets/`：品牌与 UI 资源
- `tests/unit_test/`：Dart 单元测试、组件测试、provider 与 harness 单元测试
- `tests/integration_test/`：Flutter App/native/platform 冒烟集成测试
- `tests/e2e_test/`：端到端 harness、配置、场景与 Maestro flows
- `android/`、`ios/`、`macos/`、`web/`：平台工程

## 重新生成应用图标

```bash
dart run flutter_launcher_icons
```

图标源文件位于 `assets/branding/awiki-me-logo.png`。
