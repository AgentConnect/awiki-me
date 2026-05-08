# AWiki Me Flutter 应用

AWiki Me 是一个纯 Dart/Flutter 消息客户端，基于 ANP Dart SDK 构建。账号创建、
DID-WBA 认证、User Service 调用、IM 与消息 proof 生成都由 Dart 侧完成。

## 环境要求

- Flutter 3.24.0 或更高版本，并包含 Dart 3.8.0 或更高版本

## 快速开始

```bash
PUB_HOSTED_URL=https://mirrors.tuna.tsinghua.edu.cn/dart-pub flutter pub get
dart analyze
flutter test
flutter run
```

## 项目结构

- `lib/`：应用、领域、数据与界面源码
- `assets/`：品牌与 UI 资源
- `test/`：Dart 单元测试与组件测试
- `android/`、`ios/`、`macos/`、`web/`：平台工程

## 重新生成应用图标

```bash
dart run flutter_launcher_icons
```

图标源文件位于 `assets/branding/awiki-me-logo.png`。
