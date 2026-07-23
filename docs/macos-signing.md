# macOS 开发与试用发布签名

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

## 试用发布通道

所有发给用户的 macOS 试用包必须同时保持：

- Bundle ID：`ai.awiki.awikime`
- 应用名称与安装位置：`/Applications/AWikiMe.app`
- 固定 Team ID
- 非 ad-hoc 签名

先将包含证书和私钥的 `.p12` 导入发布 Mac 的 Keychain。`.p12` 只用于安全转移
和备份，导入后应删除临时副本；不得放在仓库中，即使文件已被 Git 忽略。

复制发布配置模板：

```bash
cp scripts/package_app.local.config.example scripts/package_app.local.config
```

填写 `security find-identity -v -p codesigning` 显示的完整 identity 名称及匹配的
10 位 Team ID，然后执行：

```bash
scripts/package_app.sh
```

也可以在 CI 中通过同名 Secret / 环境变量注入：

```bash
AWIKI_MACOS_SIGNING_IDENTITY="Apple Development: ..." \
AWIKI_MACOS_DEVELOPMENT_TEAM="ABCDEFGHIJ" \
scripts/package_app.sh
```

独立运行 macOS 平台 worker 时还需要 Python 3.10+ 和 `dmgbuild 1.6.7`。CI 会在临时
venv 中按 `scripts/requirements-macos-dmg.txt` 安装精确版本并校验所有 wheel 的
SHA-256；本地可以使用同一 requirements 文件创建 venv，再通过 `DMGBUILD_PYTHON`
传入该 venv 的 Python。该工具直接生成 Finder 布局元数据，不启动 Finder，也不参与
APP 编译和代码签名。

只要本次目标包含 macOS，脚本就会在构建之前检查 identity 是否存在。
用户试用包使用 Flutter Release 模式和 production Keychain channel；Profile 仍属于开发通道，
不能用来生成用户安装包。
构建完成后还会强制验证严格签名、Bundle ID、Team ID、非 ad-hoc 状态及稳定
designated requirement；任何一项不符合都不会生成最终 DMG。Android-only 打包不依赖
macOS 签名配置。

发布版本必须先写入并提交 `pubspec.yaml`，打包脚本不会再自动递增版本。脚本要求
AWiki Me 与 sibling `awiki-cli-rs2` 都是 clean Git worktree，并把二者完整 40 位 commit
SHA 与编译期主租户域名写入 package manifest、latest manifest 和签名 App 的
`Info.plist`。DMG 生成前会读取 `AWikiAppSourceRef`、`AWikiImCoreSourceRef` 与
`AWikiPrimaryTenantDomain` 并与本次构建输入逐字校验；因此发布 artifact 可以证明其
App/Core 源码来源和 fresh registry 的主租户目标，但该能力不能反向补齐未嵌入这些字段的
历史 artifact。用于 `awiki.info` 双版本门禁的新 artifact 必须显式使用
`--primary-tenant-domain awiki.info` 打包。

`package_app.local.config`、`.p12` 和 `.pfx` 均已被 Git 忽略，但真实私钥仍应只保存在
Keychain、加密密码库或 CI Secret 中。`.gitignore` 不是凭证存储机制。

## 跨机器发布

发布不依赖某一台固定 Mac。同一份加密 `.p12` 可以导入多台受控发布 Mac，或者由
CI 临时导入独立 Keychain。获得私钥的人可以代表项目签名，因此只应授权给少数发布者，
并在疑似泄露时撤销和轮换证书。

Apple Development 签名适合当前试用分发，但不能替代 Developer ID 和 notarization。
面向普通用户正式分发时，应切换到 `Developer ID Application`、Hardened Runtime 和
Apple notarization；开发通道不需要随之改变。
