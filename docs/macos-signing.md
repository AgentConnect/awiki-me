# macOS 开发签名与 Developer ID 正式发布

本仓库把 macOS 签名分成两条互不耦合的通道。物理构建机器不是应用身份；
Bundle ID、Team ID 和签名证书才共同决定 macOS 看到的代码身份。

## 开发通道

共享 Debug 配置默认使用 ad-hoc 签名，不包含任何开发者 Team ID：

```bash
flutter run --debug -d macos
```

这样所有开发者都可以直接构建。ad-hoc 的 designated requirement 通常绑定
CDHash，二进制变化后，屏幕录制等 TCC 权限可能需要重新授权。

需要在本机保持稳定 TCC 身份的开发者可以启用本地覆盖：

```bash
cp macos/Runner/Configs/LocalSigning.xcconfig.example \
  macos/Runner/Configs/LocalSigning.xcconfig
```

编辑复制后的文件，填写本机 Keychain 中可用的 Apple Development Team 和一个
`ai.awiki.awikime.dev.<suffix>` 形式的开发者专用 Bundle ID。原生 Keychain 桥只接受
生产 ID、基础开发 ID 及该受控开发后缀，不接受其他 Bundle ID。
`LocalSigning.xcconfig` 已被 Git 忽略，不能提交。

```bash
security find-identity -v -p codesigning
flutter run --debug -d macos
codesign -dvvv "build/macos/Build/Products/Debug/AWikiMe.app"
codesign -d -r- "build/macos/Build/Products/Debug/AWikiMe.app"
```

稳定签名应具有预期 `TeamIdentifier`，且 designated requirement 不应只包含
`cdhash`。切换开发 Bundle ID 或签名身份后，需要对新的 Bundle ID 重新授权屏幕录制。

## 正式发布通道

所有发给用户的 macOS DMG 必须同时保持：

- Bundle ID：`ai.awiki.awikime`；
- 应用名称与安装位置：`/Applications/AWikiMe.app`；
- 固定组织 Team ID；
- `Developer ID Application` 签名；
- Hardened Runtime 和安全时间戳；
- 不包含 `get-task-allow` 等开发调试权限；
- 最终 DMG 已签名、经 Apple 公证并附加有效票据；
- 挂载后的真实 App 通过 Gatekeeper assessment。

`Apple Development`、`Apple Distribution`、ad-hoc 和 Profile 构建均不得用于官网分发。
公证是自动安全检查，不是 App Store 人工审核。

## GitHub Actions 凭证

标准发布入口仍是：

```bash
scripts/package_app.sh
```

该脚本只校验源码、触发 GitHub Actions、等待唯一 request ID 并下载聚合产物；它不会在
本机读取 P12、API Key 或编译平台安装包。macOS 凭证只保存在受保护的
`app-packaging` GitHub Environment：

| Secret | 内容 |
| --- | --- |
| `AWIKI_MACOS_P12_BASE64` | 组织 Developer ID identity 的加密 P12 |
| `AWIKI_MACOS_P12_PASSWORD` | P12 强密码 |
| `AWIKI_MACOS_SIGNING_IDENTITY` | 完整 `Developer ID Application: ...` identity |
| `AWIKI_MACOS_DEVELOPMENT_TEAM` | 匹配的 10 位组织 Team ID |
| `AWIKI_MACOS_NOTARY_KEY_BASE64` | App Store Connect Team API `.p8` |
| `AWIKI_MACOS_NOTARY_KEY_ID` | Team API Key ID |
| `AWIKI_MACOS_NOTARY_ISSUER_ID` | Team API Issuer ID |

CI 将 P12 和 `.p8` 写入 owner-only 临时文件，导入独立临时 Keychain，并在编译前使用
`notarytool history` 验证 API 鉴权。平台 worker 生成并签名 DMG 后，通过 `notarytool submit
--wait` 等待自动公证；只有状态为 `Accepted`、staple 成功且最终验证全部通过时才上传平台
artifact。失败诊断在删除临时凭证后单独上传，未公证 DMG 不进入聚合任务。

## 本机公证配置

本机只在运行签名 Gate 或直接诊断 macOS worker 时需要组织 Developer ID identity。先将
加密 P12 导入登录 Keychain，再把 App Store Connect Team API Key 存为 Keychain profile：

```bash
xcrun notarytool store-credentials awiki-macos-notary \
  --key /secure/path/AuthKey_REPLACE.p8 \
  --key-id REPLACE_KEY_ID \
  --issuer REPLACE_ISSUER_ID
```

直接运行 worker 时使用 `AWIKI_MACOS_NOTARY_PROFILE=awiki-macos-notary`，不能同时再传
`.p8` 路径。CI 不使用本机 profile，而是从 Environment Secret 建立一次性文件。普通
`flutter run --debug -d macos` 不读取这些正式发布凭证。

独立运行 macOS worker 还需要 Python 3.10+ 和 `dmgbuild 1.6.7`。CI 在临时 venv 中按
`scripts/requirements-macos-dmg.txt` 安装精确版本并校验 wheel SHA-256；`dmgbuild` 只生成
Finder 布局，不参与 App 签名或公证。

正式包使用 Flutter Release 模式和 production Keychain channel。构建会依次验证 App 严格
签名、Bundle ID、Team ID、Developer ID authority、Hardened Runtime、时间戳、entitlements、
DMG 签名、公证票据和 Gatekeeper；任一项不符合都不会生成最终 artifact。Android-only
打包不依赖 macOS 凭证。

发布版本必须先写入并提交 `pubspec.yaml`，打包脚本不会再自动递增版本。脚本要求
AWiki Me 与 sibling `awiki-cli-rs2` 都是 clean Git worktree，并把二者完整 40 位 commit
SHA 与编译期主租户域名写入 package manifest、latest manifest 和签名 App 的
`Info.plist`。DMG 生成前会读取 `AWikiAppSourceRef`、`AWikiImCoreSourceRef` 与
`AWikiPrimaryTenantDomain` 并与本次构建输入逐字校验；因此发布 artifact 可以证明其
App/Core 源码来源和 fresh registry 的主租户目标，但该能力不能反向补齐未嵌入这些字段的
历史 artifact。用于 `awiki.info` 双版本门禁的新 artifact 必须显式使用
`--primary-tenant-domain awiki.info` 打包。

`package_app.local.config` 只允许覆盖目标和发布域名，不接受签名材料。`.p12`、`.p8` 和
`.pfx` 即使已被 Git 忽略也不得放在仓库中；真实私钥只能保存在 Keychain、企业加密密码库
或受保护的 CI Secret 中。`.gitignore` 不是凭证存储机制。

## 跨机器发布

发布不依赖某一台固定 Mac。同一份加密 P12 可以导入少量受控发布 Mac，CI 则临时导入
独立 Keychain。获得 P12 私钥的人可以代表组织签名，获得 `.p8` 的人可以提交组织公证，
因此二者都只能授权给发布维护者，并在疑似泄露时立即撤销和轮换。

首次从个人 Team 切换到组织 Team 时必须用上一正式版本执行覆盖升级 Gate，验证 production
Keychain、本地身份与数据连续性，并预期屏幕录制等 TCC 权限需要对新 Team 重新授权。组织
版本公开发布后，正式包不得再回退到个人 Team，否则会再次破坏代码身份连续性。
