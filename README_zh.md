# AWiki Me Flutter 应用

AWiki Me 是一个独立发布的 Flutter 消息客户端仓库。

## 环境要求

- Flutter 3.24.0 或更高版本
- Dart 3.5.0 或更高版本

## 快速开始

```bash
flutter pub get
flutter analyze
flutter test
flutter run
```

## 项目结构

- `lib/`：应用源码
- `assets/`：图片与 SVG 资源
- `test/`：单元测试与组件测试
- `android/`、`ios/`、`web/`：平台工程

## 重新生成应用图标

```bash
dart run flutter_launcher_icons
```

图标源文件位于 `assets/branding/awiki-me-logo.png`。

## 重新生成启动图

```bash
dart run flutter_native_splash:create
```

启动图资源同样位于 `assets/branding/awiki-me-logo.png`。
