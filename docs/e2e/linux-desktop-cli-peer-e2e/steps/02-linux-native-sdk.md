# Step 02：`awiki_im_core` Linux native SDK

主 Plan：[../plan.md](../plan.md)  
Step index：02  
状态：draft

## 1. 执行状态

| 字段 | 值 |
|---|---|
| Status | review |
| Branch | `feature/test-awiki-me` / `awiki-cli-rs2` 当前工作分支 |
| Started | 2026-06-13 20:30:28 CST |
| Completed | - |
| Commit | - |
| Review evidence | Linux plugin declaration、CMake bundled library、loader、build script、docs 与 App smoke 变更已检查；默认 native build 保持 Apple/Android，Linux 通过 `--linux-only` 显式构建；生成的 `.so` 被 `.gitignore` 排除；未纳入 `awiki-cli-rs2` 既有 daemon 脏改 |
| Verification evidence | `scripts/flutter/build-sdk-native.sh --linux-only --dry-run` 通过；`scripts/flutter/build-sdk-native.sh --dry-run` 通过且默认不跑 Linux；`scripts/flutter/codegen-check.sh` 通过；`cargo test -p im-core-dart --locked` 通过；`scripts/flutter/build-sdk-native.sh --linux-only` 通过；`cd packages/awiki_im_core && flutter test` 通过；`xvfb-run -a flutter test integration_test/im_core_open_smoke_test.dart -d linux` 通过；App bundle 含 `build/linux/x64/debug/bundle/lib/libawiki_im_core.so`；`dart analyze` 和 `flutter test` 通过；两个 repo `git diff --check` 通过 |
| Next action | 创建 Step 02 聚焦 commit，然后进入 Step 03 |

状态取值：`pending`、`in_progress`、`review`、`blocked`、`committed`、`done`。

## 2. 目标

- 结果：`awiki-cli-rs2/packages/awiki_im_core` 支持 Flutter Linux native FFI plugin，`test-awiki-me` 在 Linux Desktop 上能打开真实 `AwikiImCore`。
- 用户 / 系统可见行为：`integration_test/im_core_open_smoke_test.dart` 可在 Linux 下运行并通过，不再因 Linux unsupported loader 失败。
- 非目标：本步骤不做 App+CLI peer 真实消息 E2E，不改变 SDK public DTO 语义，不重构 Android / iOS / macOS 打包。
- 完成标准：Linux `.so` 可构建、可被 Flutter Linux bundle 打包、loader 可加载、native open smoke 通过。

## 3. 设计方法

- 设计边界：只扩展 `awiki_im_core` 的 Linux native backend，不把 App UI / CLI peer / 服务账号编排混进 SDK step。
- 核心决策：短期按现有 Flutter 3.24+ 项目约束使用 legacy FFI plugin / CMake 打包思路；未来 Flutter baseline 提升后再评估 native assets。
- 契约 / API / 数据流：Dart public API 不变，仍由 `AwikiImCore.open(config, paths)` 打开 Rust facade；Linux 只是新增 native library loading branch。
- 兼容性：Android `libawiki_im_core.so`、Apple static XCFramework、macOS `DynamicLibrary.process()` 现状不回归。
- 迁移策略：无用户数据迁移；只是新增平台产物。
- 风险控制：不要提交本地 build cache、`.dart_tool/`、`build/` 或 target artifacts，除非项目已经约定提交某类 native artifacts；artifact commit 策略要跟现有 Android / Apple 保持一致。

## 4. 实现方法

1. 在 SDK package 声明 Linux platform：

   - `awiki-cli-rs2/packages/awiki_im_core/pubspec.yaml` 的 `flutter.plugin.platforms` 增加 `linux`。
   - 根据 Flutter FFI plugin 约定补 `linux/CMakeLists.txt`、plugin registration 需要的最小文件或 bundled library 配置。

2. 新增 Linux native build：

   ```bash
   cd awiki-cli-rs2
   cargo build \
     -p im-core-dart \
     --release \
     --target x86_64-unknown-linux-gnu \
     --no-default-features \
     --features blocking,sqlite,http
   ```

3. 将 `target/x86_64-unknown-linux-gnu/release/libawiki_im_core.so` 或本机 target 等价路径复制 / 打包到 Flutter Linux plugin 期望位置。
4. 更新 `awiki-cli-rs2/scripts/flutter/build-sdk-native.sh`：

   - 增加 `--linux-only`；
   - 默认 build 是否包含 Linux 需要明确：如果 Linux build 只能在 Linux host 运行，默认脚本可以按 host OS 选择或要求显式 `--linux-only`；
   - `--dry-run` 必须打印 Linux build plan。

5. 更新 `awiki-cli-rs2/packages/awiki_im_core/lib/src/native_library_loader.dart`：

   - `Platform.isLinux` 时加载 `libawiki_im_core.so`；
   - 如果实际 bundle 路径需要 executable-relative fallback，按 Flutter Linux 运行时验证结果实现；
   - 保持 Windows unsupported。

6. 更新 SDK 文档：

   - `awiki-cli-rs2/docs/flutter-sdk/awiki-im-core-flutter-sdk.md` 支持平台从 Android / iOS / macOS 扩展到 Linux；
   - 记录 Linux build prerequisites 和 build command；
   - 记录 Linux 常见加载错误排查。

7. 更新 App native smoke：

   - 让 `test-awiki-me/integration_test/im_core_open_smoke_test.dart` 在 Linux 可运行；
   - skip 条件从 macOS-only 改为 macOS 或 Linux；
   - 如果 Linux 与 macOS loader 行为不同，断言保持为 `open` + `validatePaths()` 的最小 smoke。

## 5. 路径

本节所有路径都相对 AWiki workspace 根目录。

| 仓库 / 模块 / 文件 | 计划变更 | 备注 |
|---|---|---|
| `awiki-cli-rs2/packages/awiki_im_core/pubspec.yaml` | 增加 Linux plugin declaration | 不改 public package identity |
| `awiki-cli-rs2/packages/awiki_im_core/lib/src/native_library_loader.dart` | 增加 Linux loader branch | 保持 Android / Apple 现状 |
| `awiki-cli-rs2/packages/awiki_im_core/linux/` | 新增 Linux plugin / CMake 打包文件 | 以 Flutter FFI plugin 约定为准 |
| `awiki-cli-rs2/scripts/flutter/build-sdk-native.sh` | 增加 Linux build path / `--linux-only` | 保持 `--dry-run` |
| `awiki-cli-rs2/scripts/flutter/build-linux.sh` | 可选新增 | 如果主脚本过长，独立脚本更清晰 |
| `awiki-cli-rs2/docs/flutter-sdk/awiki-im-core-flutter-sdk.md` | 更新支持平台和命令 | SDK 文档权威 |
| `awiki-cli-rs2/packages/awiki_im_core/README.md` | 同步 Linux 支持摘要 | 保持简短 |
| `test-awiki-me/integration_test/im_core_open_smoke_test.dart` | 放开 Linux native smoke | 仍保持最小 smoke |

## 6. 依赖

- 前置步骤：可与 Step 01 并行做 SDK 分析；完整验证依赖 Step 01 的 Linux runner。
- 外部文档或决策：Flutter legacy FFI plugin、Flutter pubspec plugin options、当前 Flutter 3.24+ baseline。
- 环境前提：Linux host 有 Rust target `x86_64-unknown-linux-gnu` 和 Flutter Linux desktop deps。

## 7. 验收标准

- [ ] `awiki_im_core` `pubspec.yaml` 声明 Linux plugin。
- [ ] `native_library_loader.dart` 在 Linux 不抛 unsupported，能定位 `libawiki_im_core.so`。
- [ ] Linux native build 脚本可以 dry-run，也可以在 Linux host 生成 `.so`。
- [ ] Flutter Linux plugin bundle 中包含 native `.so` 或能通过运行时搜索路径加载。
- [ ] `cd awiki-cli-rs2 && cargo test -p im-core-dart --locked` 通过。
- [ ] `cd awiki-cli-rs2 && scripts/flutter/codegen-check.sh` 通过或明确不受本步骤影响。
- [ ] `cd test-awiki-me && xvfb-run -a flutter test integration_test/im_core_open_smoke_test.dart -d linux` 通过。
- [ ] Android / iOS / macOS loader 行为不回归。
- [ ] Review 发现已经修复或明确记录。
- [ ] 本步骤在进入下一步之前已经创建聚焦 commit。

## 8. 验证方式

| 检查项 | 命令 / 方法 | 预期证据 |
|---|---|---|
| Rust facade tests | `cd awiki-cli-rs2 && cargo test -p im-core-dart --locked` | facade tests 通过 |
| Codegen | `cd awiki-cli-rs2 && scripts/flutter/codegen-check.sh` | generated Rust / Dart bridge 无漂移 |
| Linux build dry-run | `cd awiki-cli-rs2 && scripts/flutter/build-sdk-native.sh --linux-only --dry-run` | 输出 Linux build plan |
| Linux build | `cd awiki-cli-rs2 && scripts/flutter/build-sdk-native.sh --linux-only` | 生成 Linux `.so` 或按约定打包 |
| SDK package tests | `cd awiki-cli-rs2/packages/awiki_im_core && flutter test` | Dart package tests 通过 |
| App native smoke | `cd test-awiki-me && xvfb-run -a flutter test integration_test/im_core_open_smoke_test.dart -d linux` | `AwikiImCore.open` + path validation 通过 |
| Diff hygiene | `git diff --check` in changed repos | 无 whitespace / patch 格式问题 |

如果 Linux `.so` 构建通过但 Flutter bundle 找不到，必须记录 loader 错误、bundle 内容和 CMake 配置，不要跳过 native smoke。

## 9. Review 环节

- Review 时机：SDK Linux build、loader、smoke 都完成后，commit 前。
- Review 重点：library name、bundle path、`DynamicLibrary.open` 行为、CMake install path、现有平台不回归、文档是否更新、安全输出是否脱敏。

| Review 项 | 结果 | 备注 |
|---|---|---|
| 发现问题 | 已处理 | 初始 Linux CMake 使用 missing `.so` fatal 会阻断普通 Linux fake smoke；已改为 warning + 空 bundled libraries，让真正调用 `AwikiImCore.open` 的 native smoke 负责失败。初始默认 `build-sdk-native.sh` 包含 Linux 会改变原 Apple/Android 默认行为；已收敛为 `--linux-only` 显式构建。 |
| 已修复问题 | 完成 | 修正 CMake missing artifact 行为、主 build 脚本默认行为和 SDK 文档表述。 |
| 剩余风险 | 已记录 | Linux `.so` 是本机构建 artifact，不提交；新 checkout 跑 native smoke 前必须先执行 `scripts/flutter/build-sdk-native.sh --linux-only`。 |
| 新增或缺失测试 | 完成 | `xvfb-run -a flutter test integration_test/im_core_open_smoke_test.dart -d linux` 通过，证明 Flutter Linux bundle 能加载真实 native backend。 |
| 已更新或缺失文档 | 完成 | `awiki-cli-rs2/docs/flutter-sdk/awiki-im-core-flutter-sdk.md` 和 `awiki-cli-rs2/packages/awiki_im_core/README.md` 已记录 Linux 支持和构建方式。 |

## 10. Commit 要求

- Commit 时机：SDK Linux support、验证、Review 都完成后。
- Commit 范围：优先在 `awiki-cli-rs2` 建一个 SDK focused commit；`test-awiki-me` native smoke skip 调整可单独 commit。
- Commit 前状态：`awiki-cli-rs2` 仍有既有 daemon / `Cargo.lock` 脏改；本步骤只纳入 SDK 相关文件。`test-awiki-me` 只包含 Plan、native smoke 和 Linux generated plugin CMake 变化。
- 纳入文件：`awiki-cli-rs2/.gitignore`、`awiki-cli-rs2/crates/im-core-dart/Cargo.toml`、`awiki-cli-rs2/docs/flutter-sdk/awiki-im-core-flutter-sdk.md`、`awiki-cli-rs2/packages/awiki_im_core/README.md`、`awiki-cli-rs2/packages/awiki_im_core/lib/src/native_library_loader.dart`、`awiki-cli-rs2/packages/awiki_im_core/pubspec.yaml`、`awiki-cli-rs2/packages/awiki_im_core/linux/`、`awiki-cli-rs2/scripts/flutter/build-linux.sh`、`awiki-cli-rs2/scripts/flutter/build-sdk-native.sh`；`test-awiki-me/integration_test/im_core_open_smoke_test.dart`、`test-awiki-me/linux/flutter/generated_plugins.cmake`、本 Plan 和 Step 文档。
- Commit 后证据：提交后回填 commit hash 和 commit 后 `git status --short --branch`。
- 遗留未提交变更：`awiki-cli-rs2` 的 daemon 相关脏改与本步骤无关，保留不动；生成的 `packages/awiki_im_core/linux/lib/libawiki_im_core.so` 被 `.gitignore` 排除。
- 建议消息：`sdk: add awiki im core linux native support`

## 11. Blocked 处理

| Blocker | 证据 | 已尝试方案 | 影响范围 | 下一步决策 |
|---|---|---|---|---|
| Flutter Linux bundle 找不到 `.so` | `AwikiImCore.open` 抛 dynamic library load error | 检查 CMake install、bundle lib dir、loader fallback | 当前步骤 / E2E | 修正 plugin packaging；不进入 Step 04 |
| Rust Linux build 缺系统库 | cargo build linker error | 安装 Linux deps；检查 `rusqlite` / OpenSSL 等 native deps | 当前步骤 | 记录依赖并更新 docs |
| Flutter baseline 与 native assets 文档冲突 | 当前项目 Flutter 3.24+，native assets 需更高版本 | 使用 legacy FFI plugin | 当前步骤 | 记录未来迁移，不升级 Flutter baseline |

## 12. Plan 变更记录

| 日期 | 变更 | 原因 | 主 Plan 变更记录链接 |
|---|---|---|---|
| 2026-06-13 | 创建 Step 02 | 初始方案拆分 | [../plan.md#20-plan-变更记录](../plan.md#20-plan-变更记录) |

## 13. 风险、回滚与后续文档

- 风险：`.so` 构建成功不代表 Flutter 能加载；必须用 Desktop integration smoke 证明 bundle / loader。
- 回滚 / 回退：移除 Linux plugin declaration、loader branch、Linux build script 和 App Linux native smoke，恢复 macOS-only native support。
- 后续文档：SDK 文档和 `test-awiki-me/docs/testing.md` 在 Step 05 汇总到 gate 策略。
