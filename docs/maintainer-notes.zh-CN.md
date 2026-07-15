# AWiki Me README 上线前维护说明

[English](maintainer-notes.md) | [简体中文](maintainer-notes.zh-CN.md)

本文不面向最终用户。合并 README 提案前，请逐项处理。

## 1. 建议 GitHub About

**Description**

```text
Agent-native cross-platform messenger and control console for people and AI agents, built on ANP and DID-WBA.
```

**Topics**

```text
agent, messaging, flutter, dart, anp, did, im, cross-platform
```

## 2. 文件命名

中文 README 已统一为：

```text
README.zh-CN.md
```

英文 README 顶部的语言切换链接也已同步。

## 3. 发布链接

README 有意没有写入未经验证的下载地址。发布前确认：

- macOS arm64 DMG；
- macOS x64 DMG；
- Android arm64 APK；
- Release Notes；
- 签名、公证或安装风险说明；
- 公开下载页是否与 `dist/latest.json` 一致。

仓库默认打包配置将下载页指向 `https://<release-domain>/#download`，但 README 只能写实际在线且公开验证通过的 URL。

## 4. 状态确认

当前提案使用 `Developer Preview`，原因：

- App 版本仍处于 0.1 系列；
- 平台验证重点不覆盖所有声明目录；
- Web Core 是运行时 stub；
- 自托管 Agent realm 存在固定 allowlist；
- Group E2EE 和跨域能力不能笼统视为完整。

如要改为 Beta/Stable，需要同时补齐版本策略、升级契约、支持平台、兼容矩阵和真实发布 Gate。

## 5. 必须保留的事实边界

- Web 当前不可用；
- iOS 不应与 macOS/Android 使用同等发布措辞；
- Agent/Daemon realm allowlist 是 `awiki.ai`、`awiki.info`、`anpclaw.com`；
- AWiki Open Server 无 E2EE；
- App 不直接拥有私钥/JWT/SecretVault root key；
- Debug 与 Release 数据和 Keychain service 隔离；
- README 不宣称覆盖所有 ANP 应用协议。

## 6. 截图

添加 `docs/assets/readme/` 并按 `screenshot-plan.zh-CN.md` 拍摄。首屏至少需要一张真实产品图；没有截图时不建议正式发布新版 README。

## 7. 默认分支

审阅基线是 `release/0710`，但仓库默认分支是 `main`。新版 README 最终必须进入 `main`，否则普通访客仍会看到旧版首页。

## 8. 建议删除或下沉的旧 README 内容

新版 README 只保留摘要并链接到现有专项文档：

- 完整 ANP Support Scope；
- 所有 Storage Scope 细节；
- 打包配置变量；
- macOS 签名与 Xcode 排障；
- 完整测试矩阵；
- Contributor Checklist。

这些内容不应丢失，但不应阻塞首次访问者理解产品。
