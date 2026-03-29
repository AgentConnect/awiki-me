# AWiki Me

AWiki Me 是一个独立整理出来的 Flutter 客户端仓库，基于上游项目 [AgentConnect/awiki-agent-id-message](https://github.com/AgentConnect/awiki-agent-id-message) 的 Flutter 客户端部分演化而来。

这个仓库保留了移动端 / Web 客户端代码本身，同时去掉了原项目里与 Python Skill 运行时、监听器部署和服务端辅助脚本强绑定的开发入口。

## 上游关系

- 上游项目：[AgentConnect/awiki-agent-id-message](https://github.com/AgentConnect/awiki-agent-id-message)
- 当前仓库基于该项目中的 Flutter 客户端代码整理
- 应用仍然面向同一套 AWiki 服务接口和协议能力
- 原项目中的 Python CLI、Skill 打包、监听器模板等内容不再作为本仓库的主要组成部分

## 当前能力范围

AWiki Me 当前包含以下客户端能力：

- DID 会话初始化与会话恢复
- Handle / Profile 拉取与资料编辑
- 通过 RPC API 获取私聊和群聊消息
- Follow / Followers / Following 等关系接口
- 基于 WebSocket 的实时消息更新
- 基于 SQLite 的本地消息和群组缓存
- 凭证 ZIP 导入 / 导出
- 平台侧 DID 注册桥接：
  - Android：原生 `MethodChannel`
  - iOS：Dart 侧注册 facade
- 可插拔的 E2EE 接入面；当前默认实现仍为未启用状态，需接入原生插件后才能真正启用

## 架构说明

项目采用分层结构：

- `lib/src/domain/`
  - 领域实体、仓储接口、服务抽象
- `lib/src/data/`
  - RPC 网关、实时网关、本地缓存、凭证归档、平台桥接
- `lib/src/presentation/`
  - App Shell、登录引导、聊天、资料页、群组、设置页和共享 UI
- `lib/src/app/`
  - 启动装配与依赖注入

应用主装配入口位于 [bootstrap.dart](/Users/tyy/Documents/GitHub/awiki-me/lib/src/app/bootstrap.dart)，在这里完成 gateway、realtime、notification、E2EE facade 和 controller 的创建与注入。

## 关键运行模块

- [awiki_rpc_gateway.dart](/Users/tyy/Documents/GitHub/awiki-me/lib/src/data/gateways/awiki_rpc_gateway.dart)
  - 负责认证、资料、消息、群组、关系等主要 RPC 集成
- [awiki_ws_realtime_gateway.dart](/Users/tyy/Documents/GitHub/awiki-me/lib/src/data/services/awiki_ws_realtime_gateway.dart)
  - 负责 WebSocket 连接与重连逻辑
- [awiki_local_cache.dart](/Users/tyy/Documents/GitHub/awiki-me/lib/src/data/services/awiki_local_cache.dart)
  - 负责线程、消息、群组的 SQLite 本地缓存
- [credential_archive_service.dart](/Users/tyy/Documents/GitHub/awiki-me/lib/src/data/services/credential_archive_service.dart)
  - 负责凭证 ZIP 导入导出格式

## 运行配置

应用会读取以下编译时配置：

- `AWIKI_USER_SERVICE_URL`
- `AWIKI_MESSAGE_SERVICE_URL`
- `AWIKI_WS_URL`
- `AWIKI_CREDENTIALS_DIR`
- `AWIKI_SETUP_IDENTITY_SCRIPT`

如果没有显式覆盖，服务地址默认回退到 `https://awiki.ai`。

## 平台支持

- Android
  - 原生文档选择器通道
  - 原生 DID 注册通道
- iOS
  - 原生文档选择器桥接
  - Dart 侧 DID 注册 facade
- Web
  - 已保留 Flutter Web 工程，但部分面向移动端的平台能力仍可能需要额外适配

## 开发方式

### 环境要求

- Flutter 3.24.0 或更高版本
- Dart 3.5.0 或更高版本

### 常用命令

```bash
flutter pub get
flutter analyze
flutter test
flutter run
```

### 资源生成

重新生成应用图标：

```bash
dart run flutter_launcher_icons
```

重新生成启动图：

```bash
dart run flutter_native_splash:create
```

Logo 源文件：

- `assets/branding/awiki-me-logo.png`

## 仓库结构

- `lib/`：应用源码
- `assets/`：品牌与 SVG 资源
- `test/`：单元测试与组件测试
- `android/`、`ios/`、`web/`：平台工程

## 说明与边界

- 当前仓库聚焦客户端应用，不再覆盖原始 Skill 运行时模型
- 为保持与上游服务接口兼容，部分 `awiki_*` 命名仍然保留在代码中
- E2EE 当前是预留接入面，默认实现仍未启用
