# AWiki Me 测试框架方案与当前落地状态

状态：baseline implemented
日期：2026-06-13
范围：AWiki Me / Avatar Me 的测试代码组织、桌面 E2E 复用架构、当前迁移边界。

## 1. 目标

AWiki Me 的测试代码按三个**并行目录**组织：

```text
tests/unit_test/          # 单元测试：Dart unit、widget、provider、纯内存 fake
tests/integration_test/   # 集成测试：Flutter engine/native/plugin/platform smoke
tests/e2e_test/           # 端到端测试：真实 App + CLI peer + 后端服务 + 报告/harness
```

目标不是立刻补充大量测试用例，而是先把测试框架、目录边界和 E2E 复用架构搭起来。

## 2. 当前已落地的结构

```text
tests/unit_test/
  application/
  data/
  agents/
  im_core/
  support/
  e2e_harness/
  test_support.dart

tests/integration_test/
  app/
    app_smoke_test.dart
  native/
    im_core_open_smoke_test.dart
  support/

tests/e2e_test/
  harness/
    desktop_e2e_runner.dart
    mobile_e2e_runner.dart
    src/
  configs/
    mobile.example.yaml
  mobile/maestro/
    login.yaml
    open_chat_and_send.yaml
    open_chat_and_wait.yaml
  scenarios/
```

兼容 wrapper / shim 仍然保留：

```text
tool/e2e_runner.dart              # 转发到 tests/e2e_test/harness/mobile_e2e_runner.dart
tool/macos_e2e_runner.dart        # 转发到 tests/e2e_test/harness/desktop_e2e_runner.dart --platform=macos
integration_test/*.dart           # Flutter integration_test 工具入口 shim，真正实现仍在 tests/integration_test/
```

这样旧命令不会马上失效，新框架也已经建立起来。

## 3. 三个测试域的边界

### 3.1 `tests/unit_test/`

职责：快速、确定、无真实后端、无真实设备、无真实 CLI 子进程。

包含：

- 纯 Dart 逻辑测试。
- application/data/service 层 fake-backed 测试。
- widget/provider 测试。
- E2E runner/config/命令规划的纯单元测试。

运行：

```bash
flutter test tests/unit_test
```

### 3.2 `tests/integration_test/`

职责：验证 Flutter engine、platform binding、App bootstrap、native plugin smoke。

包含：

- `tests/integration_test/app/`：fake bootstrap App shell smoke。
- `tests/integration_test/native/`：`AwikiImCore.open` native smoke。

不包含：

- 真实 CLI peer。
- 多客户端消息互通。
- 真实远端账号注册/恢复闭环。

macOS 真实 platform smoke 需要通过 Flutter tooling shim 运行：

```bash
flutter test integration_test/app_smoke_test.dart -d macos
flutter test integration_test/im_core_open_smoke_test.dart -d macos
```

Linux 未来目标：

```bash
xvfb-run -a flutter test integration_test/app_smoke_test.dart -d linux
xvfb-run -a flutter test integration_test/im_core_open_smoke_test.dart -d linux
```

当前 Linux 仍依赖后续补齐：

1. `awiki-me/linux/` Flutter Desktop runner。
2. `awiki-cli-rs2/packages/awiki_im_core` Linux plugin 声明。
3. Linux native `.so` 构建/打包。
4. native loader Linux 分支。

### 3.3 `tests/e2e_test/`

职责：真实系统闭环。这里放 E2E harness、configs、mobile flows、未来 scenarios。

桌面 E2E 采用共享 runner：

```bash
dart run tests/e2e_test/harness/desktop_e2e_runner.dart --platform=macos --dry-run
dart run tests/e2e_test/harness/desktop_e2e_runner.dart --platform=linux --dry-run
```

移动 E2E 采用 mobile runner：

```bash
dart run tests/e2e_test/harness/mobile_e2e_runner.dart \
  --config tests/e2e_test/configs/mobile.example.yaml \
  --dry-run
```

## 4. 桌面 E2E 复用架构

桌面 E2E 的设计原则是：除了平台 adapter 不同，其他全部复用。

```text
Desktop E2E Runner
  |
  +-- shared config/env parser
  +-- shared run id / report / log redaction
  +-- shared awiki-cli-rs2 build
  +-- shared CLI peer isolated workspace
  +-- shared CLI config rewrite
  +-- shared CLI commands
  +-- shared App dart-defines
  |
  +-- platform adapter
        +-- macOS: xcrun + flutter test -d macos
        +-- Linux: xvfb-run + flutter test -d linux
```

当前 `tests/e2e_test/harness/desktop_e2e_runner.dart` 已经支持：

- `--platform=macos`
- `--platform=linux`
- `--dry-run`
- `--pub-get`
- `--skip-cli-build`
- `--skip-flutter-smoke`
- generic env：`AWIKI_DESKTOP_E2E_*`
- platform env alias：`AWIKI_MACOS_E2E_*`、`AWIKI_LINUX_E2E_*`

共享部分已经包括：

- CLI repo 定位。
- CLI 编译。
- `.e2e/<platform>/cli-workspaces/<runId>` 隔离 workspace。
- `awiki-cli init/config show/status`。
- CLI config 改写到 `https://awiki.info` / `awiki.info`。
- `.e2e/<platform>/reports/<runId>/timings.json`。
- OTP 只检测是否配置，不输出值。

平台差异只集中在 tooling check 和 Flutter desktop test 命令。

## 5. 迁移映射

| 原路径 | 新路径 |
|---|---|
| `test/` | `tests/unit_test/` |
| `test/support/fake_app_bootstrap.dart` | `tests/integration_test/support/fake_app_bootstrap.dart` |
| `test/tool/e2e_runner_test.dart` | `tests/unit_test/e2e_harness/mobile_e2e_runner_test.dart` |
| `integration_test/app_smoke_test.dart` | `tests/integration_test/app/app_smoke_test.dart` + root shim |
| `integration_test/im_core_open_smoke_test.dart` | `tests/integration_test/native/im_core_open_smoke_test.dart` + root shim |
| `.maestro/*.yaml` | `tests/e2e_test/mobile/maestro/*.yaml` |
| `awiki_e2e.example.yaml` | `tests/e2e_test/configs/mobile.example.yaml` |
| `tool/e2e_runner.dart` | wrapper；主体迁到 `tests/e2e_test/harness/mobile_e2e_runner.dart` |
| `tool/macos_e2e_runner.dart` | wrapper；主体迁到 `tests/e2e_test/harness/desktop_e2e_runner.dart` |

## 6. 推荐 gate

本地 quick gate：

```bash
PUB_HOSTED_URL=https://mirrors.tuna.tsinghua.edu.cn/dart-pub flutter pub get
dart analyze
flutter test tests/unit_test
dart run tests/e2e_test/harness/mobile_e2e_runner.dart \
  --config tests/e2e_test/configs/mobile.example.yaml \
  --dry-run
dart run tests/e2e_test/harness/desktop_e2e_runner.dart --platform=macos --dry-run
```

CI quick gate：

```bash
flutter pub get
dart analyze
flutter test tests/unit_test
dart run tests/e2e_test/harness/mobile_e2e_runner.dart \
  --config tests/e2e_test/configs/mobile.example.yaml \
  --dry-run
```

真实 desktop/mobile E2E 仍建议放 manual/nightly/release gate。

## 7. 后续补充测试用例的位置

后续新增测试时按这个规则放置：

| 测试类型 | 放置位置 |
|---|---|
| 纯业务逻辑 / mapper / config / provider / widget fake-backed | `tests/unit_test/` |
| App shell / native plugin / platform smoke | `tests/integration_test/` |
| App + CLI peer + 真实后端闭环 | `tests/e2e_test/scenarios/` + `tests/e2e_test/harness/` |
| Maestro flow | `tests/e2e_test/mobile/maestro/` |
| E2E 本地配置样例 | `tests/e2e_test/configs/`，只提交 example，不提交 local |

## 8. 当前仍未做的事

本轮只建立框架和迁移现有代码，没有补充新的业务测试用例。后续可以继续做：

1. 把 `tests/unit_test/` 内根级 widget tests 进一步按 feature 归入 `tests/unit_test/presentation/<feature>/`。
2. 把 desktop E2E runner 的公共类拆进 `tests/e2e_test/harness/src/`，让 runner 文件更薄。
3. 添加 Linux Flutter runner 和 `awiki_im_core` Linux native 支持。
4. 在 `tests/e2e_test/scenarios/` 添加 App + CLI peer 双向消息场景。
5. 建立 nightly/release E2E gate。

## 9. Review：是否满足当前预期

| 预期 | 当前状态 | 结论 |
|---|---|---|
| 三个测试域不要放在仓库一级目录 | 测试实现已统一放在 `tests/unit_test/`、`tests/integration_test/`、`tests/e2e_test/`；根级 `integration_test/*.dart` 只保留 Flutter 工具 shim | 满足，附带 Flutter 工具限制 |
| 单元 / 集成 / E2E 是三个并行目录，而不是三层嵌套 | 三个目录在 `tests/` 下并列存在 | 满足 |
| Mac 与 Linux E2E 复用同一套测试脚本和 CLI 交互 | `tests/e2e_test/harness/desktop_e2e_runner.dart` 用 `--platform=macos|linux` 选择平台 adapter，其余配置、CLI build、CLI workspace、CLI config、report 都复用 | 基线满足 |
| 只有平台相关部分分叉 | 当前分叉集中在 desktop tooling check 和 `flutter test -d <platform>` 命令 | 满足 |
| 对端使用 CLI 做桌面 E2E peer | runner 已经集成 `awiki-cli-rs2` 的构建、隔离 workspace 和基础 CLI smoke；真实 App + CLI 双向消息 scenario 仍待补充 | 框架满足，业务用例待补 |
| 当前不补充大量新测试用例 | 本轮主要迁移和搭框架，只保留/修正 smoke 与 runner dry-run | 满足 |
| 快速 CI 不依赖真实设备或后端 | CI 只跑 `dart analyze`、`flutter test tests/unit_test` 和 mobile runner dry-run | 满足 |

需要注意：因为测试实现目录现在统一放在 `tests/` 下，单元测试和 E2E runner 必须显式传入路径，例如 `flutter test tests/unit_test`、`dart run tests/e2e_test/harness/desktop_e2e_runner.dart --platform=macos --dry-run`。Flutter 的 `integration_test` plugin 是例外：真实 device/platform integration 需要从根级 `integration_test/*.dart` shim 启动，否则会退化成普通 widget test 并失去 native/platform smoke 语义。
