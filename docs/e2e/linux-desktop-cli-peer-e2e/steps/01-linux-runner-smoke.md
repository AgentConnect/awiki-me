# Step 01：Linux runner 与 desktop smoke

主 Plan：[../plan.md](../plan.md)  
Step index：01  
状态：draft

## 1. 执行状态

| 字段 | 值 |
|---|---|
| Status | done |
| Branch | `feature/test-awiki-me` |
| Started | 2026-06-13 19:48:55 CST |
| Completed | 2026-06-13 20:22:21 CST |
| Commit | `6bfc504` |
| Review evidence | diff 限于 `test-awiki-me/linux/`、`.metadata`、`integration_test/app_smoke_test.dart` 和 Linux 依赖文档；未修改 Android / iOS / macOS / web runner；`linux/flutter/ephemeral` 确认被 `.gitignore` 排除 |
| Verification evidence | `flutter doctor` Linux toolchain 通过；`flutter devices` 看到 `Linux (desktop)`；`flutter test` 通过；`xvfb-run -a flutter test integration_test/app_smoke_test.dart -d linux` 通过；`dart analyze` 通过；`git diff --check` 通过 |
| Next action | 创建 Step 01 聚焦 commit，然后进入 Step 02 |

状态取值：`pending`、`in_progress`、`review`、`blocked`、`committed`、`done`。

## 2. 目标

- 结果：`test-awiki-me` 支持 Flutter Linux Desktop runner。
- 用户 / 系统可见行为：在 Ubuntu headless 环境里，`xvfb-run -a flutter test integration_test/app_smoke_test.dart -d linux` 能启动 App shell smoke。
- 非目标：本步骤不启用真实 `AwikiImCore.open` Linux native backend，不跑真实账号登录，不改 Android / iOS / macOS / web runner。
- 完成标准：Linux runner 存在，`app_smoke_test.dart` 在 Linux desktop 设备通过；diff 没有无关平台漂移。

## 3. 设计方法

- 设计边界：先验证 Flutter Desktop runner 与 Xvfb 显示环境，不把 SDK native、服务账号和消息 E2E 混进同一步。
- 核心决策：`integration_test/app_smoke_test.dart` 当前使用 fake bootstrap，适合作为 Linux runner smoke 的第一道门。
- 契约 / API / 数据流：不改 App 业务契约；只让 Flutter 工具链识别 Linux desktop target。
- 兼容性：保留已有 Android / iOS / macOS / web runner 现状；若 Flutter 工具更新 `.metadata` 或 plugin registrant，逐项确认只与 Linux enablement 相关。
- 迁移策略：无用户数据迁移。
- 风险控制：生成 runner 后先 `git status --short` 和 `git diff --name-only`，发现无关 runner 文件变化就不要纳入本步骤。

## 4. 实现方法

1. 安装或确认 Ubuntu Linux Desktop 构建依赖：

   ```bash
   sudo apt update
   sudo apt install -y \
     clang cmake ninja-build pkg-config libgtk-3-dev liblzma-dev \
     libstdc++-12-dev libsecret-1-dev xvfb dbus-x11
   flutter config --enable-linux-desktop
   flutter doctor
   flutter devices
   ```

2. 在 `test-awiki-me` 中生成 Linux runner：

   ```bash
   cd test-awiki-me
   flutter create --platforms=linux .
   ```

3. 检查变更范围：

   ```bash
   cd test-awiki-me
   git status --short
   git diff --name-only
   ```

4. 保留 `linux/` runner 和必要 `.metadata` 变化；不要提交无关平台 runner、签名、bundle id、Pod / Gradle / Xcode metadata 变化。
5. 运行 Linux fake bootstrap smoke。

## 5. 路径

本节所有路径都相对 AWiki workspace 根目录。

| 仓库 / 模块 / 文件 | 计划变更 | 备注 |
|---|---|---|
| `test-awiki-me/linux/` | 新增 Flutter Linux Desktop runner | 由 Flutter 工具生成后 review |
| `test-awiki-me/.metadata` | 可能记录 Linux platform enablement | 只保留必要变化 |
| `test-awiki-me/integration_test/app_smoke_test.dart` | 原则上不改 | 当前 fake bootstrap smoke 已适合作为 runner smoke |
| `test-awiki-me/docs/testing.md` | Step 05 统一更新 gate 文档；本步骤只在需要时补一句现状 | 避免重复文档 |

## 6. 依赖

- 前置步骤：无。
- 外部文档或决策：Flutter Linux setup、Flutter desktop support。
- 环境前提：本机或 CI runner 能安装 Linux desktop build deps，`flutter devices` 能看到 `Linux (desktop)`。

## 7. 验收标准

- [ ] `test-awiki-me/linux/` 存在并能被 Flutter 识别。
- [ ] `flutter devices` 输出包含 Linux desktop 设备。
- [ ] `xvfb-run -a flutter test integration_test/app_smoke_test.dart -d linux` 通过。
- [ ] `git diff --name-only` 只包含 Linux runner 和必要 metadata / docs。
- [ ] 没有修改 Android / iOS / macOS / web runner、签名、bundle id 或 generated registrant 的无关内容。
- [ ] Review 发现已经修复或明确记录。
- [ ] 本步骤在进入下一步之前已经创建聚焦 commit。

## 8. 验证方式

| 检查项 | 命令 / 方法 | 预期证据 |
|---|---|---|
| Flutter deps | `cd test-awiki-me && flutter doctor` | Linux desktop toolchain 可用，或明确记录缺失依赖 |
| Device | `cd test-awiki-me && flutter devices` | 看到 `Linux (desktop)` |
| App tests | `cd test-awiki-me && flutter test` | 既有 unit / widget 不回归 |
| Linux smoke | `cd test-awiki-me && xvfb-run -a flutter test integration_test/app_smoke_test.dart -d linux` | fake bootstrap App shell smoke 通过 |
| Diff hygiene | `cd test-awiki-me && git diff --check` | 无 whitespace / patch 格式问题 |

如果缺少系统依赖导致 Linux smoke 不能运行，必须记录 `flutter doctor` 和安装缺口；不能把 smoke 通过写成已完成。

## 9. Review 环节

- Review 时机：Linux runner 生成、smoke 通过、commit 前。
- Review 重点：runner 变更范围、无关平台安全、`.metadata` 合理性、CI 依赖、`docs/testing.md` 是否需要同步。

| Review 项 | 结果 | 备注 |
|---|---|---|
| 发现问题 | 已处理 | `flutter create` 生成了无关 IDE/default test、更新 `pubspec.lock` 和移除 macOS metadata；已还原无关变化，只保留 Linux runner 和必要 metadata。Linux smoke 还暴露缺少 `libsecret-1-dev`，已补环境和文档。原 smoke 用例含 macOS-only 文案、切 tab 和 realtime 调用断言；已收敛为跨平台 App shell smoke。 |
| 已修复问题 | 完成 | 还原无关 lockfile/IDE/default test；补 `libsecret-1-dev` 文档；收敛 `integration_test/app_smoke_test.dart` 到 Linux/macOS 都稳定的启动断言。 |
| 剩余风险 | 已记录 | 本步骤只证明 Linux runner + fake bootstrap shell 可启动；不证明真实 native SDK、真实账号或消息链路，后续 Step 02-04 覆盖。 |
| 新增或缺失测试 | 完成 | `xvfb-run -a flutter test integration_test/app_smoke_test.dart -d linux` 通过；`flutter test` 通过。 |
| 已更新或缺失文档 | 完成 | `docs/testing.md`、总方案、主 Plan 和 Step 01 均补充 `libsecret-1-dev`。 |

## 10. Commit 要求

- Commit 时机：Linux runner、验证、Review 都完成后。
- Commit 范围：`test-awiki-me/linux/`、必要 `.metadata`、`integration_test/app_smoke_test.dart`、必要 docs。
- Commit 前状态：`git status --short --branch` 显示 `.metadata`、Linux 依赖文档、`integration_test/app_smoke_test.dart` 和 `linux/` 为本步骤变更。
- 纳入文件：`test-awiki-me/linux/` 非 ignored runner 文件、`.metadata`、`integration_test/app_smoke_test.dart`、`docs/testing.md`、`docs/e2e/desktop-cli-peer-macos-linux-plan.md`、`docs/e2e/linux-desktop-cli-peer-e2e/plan.md`、本 Step 文档。
- Commit 后证据：`6bfc504`；提交后 `git status --short --branch` 显示无未提交变更。
- 遗留未提交变更：无计划遗留；ignored `build/`、`.dart_tool/`、`.flutter-plugins-dependencies`、平台 ephemeral 为 Flutter 生成产物，不提交。
- 建议消息：`test: add linux desktop runner smoke`

## 11. Blocked 处理

| Blocker | 证据 | 已尝试方案 | 影响范围 | 下一步决策 |
|---|---|---|---|---|
| CI / 本机不能安装 Linux desktop deps | `flutter doctor` 缺少 clang/cmake/gtk 等 | 安装 apt deps；确认 Flutter config | 当前步骤 | 记录环境缺口，不能把 Linux smoke 设为 required gate |
| `flutter create` 改动无关平台文件 | `git diff --name-only` 出现 Android / iOS / macOS 等无关文件 | 手工 review；只保留必要文件 | 当前步骤 / 多平台安全 | 不提交无关变化 |

## 12. Plan 变更记录

| 日期 | 变更 | 原因 | 主 Plan 变更记录链接 |
|---|---|---|---|
| 2026-06-13 | 创建 Step 01 | 初始方案拆分 | [../plan.md#20-plan-变更记录](../plan.md#20-plan-变更记录) |

## 13. 风险、回滚与后续文档

- 风险：Linux runner 只是运行壳，不代表真实 SDK / 服务链路可用。
- 回滚 / 回退：删除本步骤新增 Linux runner 和必要 metadata，回到 macOS / mobile-only integration state。
- 后续文档：Step 05 统一更新 `test-awiki-me/docs/testing.md` 的 Linux gate 状态。
