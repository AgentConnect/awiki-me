# Step 05：集成验证、性能门禁和文档收口

主 Plan：[../plan.md](../plan.md)  
Step index：05  
状态：done

## 1. 执行状态

| 字段 | 值 |
|---|---|
| Status | done |
| Branch | `awiki-me: feature/perf/message-sync-opt-0627`; `awiki-system-test: release/0526` 如需测试文档；`awiki-cli-rs2: feature/perf/message-sync-opt-0627` 如需 docs 收口 |
| Started | 2026-06-28 21:57:54 CST |
| Completed | 2026-06-28 22:37:02 CST |
| Commit | `awiki-me@ba04e0a` |
| Review evidence | Review 确认 performance flow 在显式 `syncThreadAfter` 前先等待 fast local conversation preview，再通过 `ChatThreadsController.openConversation` + `selectedConversationProvider` 走 App provider open path，并轮询 `chatThreadProvider` 精确匹配 CLI message id；required metrics / hard / soft budgets 已加入默认配置，local YAML 会与默认 budgets 合并；报告只记录耗时、计数、thread kind 和 unread 数，不写 token、私钥、JWT、完整 DID 或消息正文；文档中修正 `timings.json` schema 为顶层 `metrics` map；删除 E2E harness 中未使用 helper 以恢复全局 analyzer gate。 |
| Verification evidence | `uname -s` 为 Linux，使用 Linux 本地 E2E config，未触发 Darwin/macOS config 约束；首次 `dart run tests/e2e/runner.dart --case performance` 因 `awiki-cli-rs2/target/release/awiki-cli` 缺失停在 tooling check，随后 `CARGO_BUILD_JOBS=1 cargo build --release -p awiki-cli --locked` 成功；重跑 `dart run tests/e2e/runner.dart --case performance` 通过，报告 `awiki-me/.e2e/desktop-cli-peer/20260628142733-hjwd9412nn/reports/timings.json`，`message.cli_send_to_app_open_first_paint_ms=450`、`thread.realtime_open_first_paint_ms=348`、`message.cli_send_app_thread_after_ms=135`、`message.cli_send_to_app_history_visible_ms=724`、`message.cli_send_to_conversation_preview_visible_ms=101`、`conversation.full_refresh_during_send_receive_count=0`、`conversation.patch_apply_count=10`、`conversation.patch_repair_count=0`，hard/soft failures 均为空；`flutter test tests/unit/e2e_harness/desktop_e2e_runner_test.dart` 通过 45 个测试；`dart run tests/unit/runner.dart` 通过 `+682: All tests passed!`；`dart analyze` 通过；`git diff --check` 通过；`CARGO_BUILD_JOBS=1 cargo test -p im-core --locked realtime` 通过；`CARGO_BUILD_JOBS=1 cargo test -p im-core --locked` 通过；`awiki-system-test` remote focused suite 15 passed；docs path scan 无本机绝对路径或 workspace 目录名前缀。 |
| Next action | Step 05 已完成；进入主 Plan 最终全局 Review 与整体验证。 |

状态取值：`pending`、`in_progress`、`review`、`blocked`、`committed`、`done`。

## 2. 目标

- 结果：为 P0-P3 建立完整验证闭环，并同步文档。
- 用户 / 系统可见行为：E2E performance 可以证明“CLI 远端发消息 → App 收到 realtime / patch → 点开会话 → 新消息首屏可见”的耗时在预算内。
- 非目标：
  - 不因为 remote 环境未部署而放宽系统测试 contract。
  - 不在 Mac 主机跑 Linux E2E config。
  - 不把测试账号敏感信息、JWT、私钥、完整 DID 写入报告。
- 完成标准：
  - AWiki Me performance E2E 新增或复用指标覆盖新消息点击首屏路径。
  - required metrics / budgets 包含新指标，且 Mac config 下通过或记录明确失败原因。
  - Rust、Dart、系统测试和 docs 证据写入主 Plan 执行台账。
  - 最终全局 Review 前所有步骤 commit 完成。

## 3. 设计方法

- 设计边界：Step 05 是集成和证据层；不再做大规模架构改动，除非 Plan 变更记录批准。
- 核心决策：
  - E2E 指标应测真实用户路径，而不是只手动调用 `messageSync.syncThreadAfter` 后查 local history。
  - 现有 performance flow 中 `message.cli_send_to_app_history_visible_ms` 偏向 service/local history；需要增加例如 `message.cli_send_to_app_open_first_paint_ms` 或 `thread.realtime_open_first_message_visible_ms`，记录点击 / open 后首条新消息可见。
  - 在 Mac 上运行 E2E 时必须使用 `tests/e2e/configs/e2e.codex-macos-allowed.local.yaml` 或其他明确 macOS config；先 `uname -s` 判断。
  - system-test remote focused suite 用于验证服务端 sync/read-state/WS contract；App 性能 E2E 用于验证客户端体验。
- 契约 / API / 数据流：
  - P0-P4 后的完整链路：realtime projection patch → App patch/realtime update → alias memory tail → local-first click → background sync。
- 兼容性：E2E 新指标要加入 budget 时设置合理 hard/soft 门槛，避免因 remote 网络波动导致过度 flaky；首次 budget 可记录 baseline 后收紧。
- 迁移策略：无数据迁移。
- 风险控制：E2E 报告记录环境、config、平台；失败时保留 report 路径和红acted logs。

## 4. 实现方法

1. 在全部受影响仓库执行 `git status --short --branch`，确认 Step 01-04 都已提交。
2. 更新 AWiki Me E2E performance：
   - 阅读 `awiki-me/tests/e2e/runner.dart`。
   - 阅读 `awiki-me/tests/e2e/flutter/desktop_cli_peer/flows/performance_flow.dart`。
   - 在 performance case IDs / required metrics 中加入新指标，例如 `message.cli_send_to_app_open_first_paint_ms` 或 `thread.realtime_open_first_message_visible_ms`。
   - 在 flow 中尽量走真实 App UI / provider open path：CLI 发消息到 App 后，等待 conversation preview / patch，触发打开对应 conversation，再测首条消息 visible。若当前 E2E harness 无 UI click 能力，至少调用与 UI 一致的 provider open path，并记录差异。
   - 记录 counters：patch apply count、full refresh during send/receive、remote history fallback count（如可取得）。
3. 更新 performance budgets：
   - hard budget 初始可参考已有 `thread.open_to_first_message_visible_ms` 8000ms，但新增新消息点击路径目标应更低；建议 hard 3000-5000ms、soft 1000-1500ms，最终按实测 baseline 与稳定性 Review。
   - required metrics 必须包含新指标，避免 E2E 漏测。
4. 更新文档：
   - `awiki-me/docs/performance-tracing.md`：增加 memory tail / local tail / background sync / new realtime open 指标说明。
   - `awiki-me/README.md`：如 Message Sync 段落需要补充“realtime committed projection patch + local-first open”。
   - `awiki-cli-rs2/docs/architecture/im-core-sdk-architecture.md` / Flutter SDK docs：如 Step 01 未更新完整，补齐。
   - `awiki-harness/features/message-sync-reliability.md`：如果跨仓库 feature summary 需要反映新 realtime patch / App first-paint gate，则更新。
5. 运行验证：
   - `awiki-cli-rs2` Rust focused / broader tests。
   - `awiki-me` analyzer / unit。
   - `awiki-me` E2E performance，先 `uname -s`，Darwin 使用 Mac config。
   - `awiki-system-test` remote focused sync/read-state/WS suite。
6. Review：
   - 检查 E2E 不是绕过真实点击路径。
   - 检查 budgets 不过松也不过度 flaky。
   - 检查报告脱敏。
   - 检查 Mac/Linux config 分流。
7. 如果本步骤修改了 E2E/docs，创建聚焦 commit；如果只运行验证，记录“无文件变更，无 commit”。
8. 回填主 Plan 第 17 节最终全局 Review 前的所有证据。

## 5. 路径

| 仓库 / 模块 / 文件 | 计划变更 | 备注 |
|---|---|---|
| `awiki-me/tests/e2e/runner.dart` | 增加 performance required metric / budget / case ID 文案。 | E2E gate。 |
| `awiki-me/tests/e2e/flutter/desktop_cli_peer/flows/performance_flow.dart` | 增加新消息点击首屏测量。 | 应尽量覆盖真实 open path。 |
| `awiki-me/tests/e2e/configs/e2e.codex-macos-allowed.local.yaml` | 原则上不提交修改；只作为 Darwin 执行 config。 | 本地配置可能 ignored。 |
| `awiki-me/docs/performance-tracing.md` | 更新指标解释和解读规则。 | 文档同步。 |
| `awiki-me/README.md` | 必要时更新 Message Sync 段落。 | 文档同步。 |
| `awiki-cli-rs2/docs/architecture/im-core-sdk-architecture.md` | 确认 / 补齐 realtime patch 文档。 | 若 Step 01 未完全覆盖。 |
| `awiki-cli-rs2/docs/flutter-sdk/awiki-im-core-flutter-sdk.md` | 确认 / 补齐 SDK 行为。 | 若 Step 01 未完全覆盖。 |
| `awiki-harness/features/message-sync-reliability.md` | 必要时更新 feature summary。 | 跨仓库行为总结。 |
| `awiki-system-test/docs/message-sync-reliability-system-tests.md` | 如测试证据或 remote gate 文档需要更新才改。 | 不预计改 contract。 |

## 6. 依赖

- 前置步骤：Step 01、Step 02、Step 03、Step 04 全部 done。
- 外部文档或决策：主 Plan 第 11 节验证策略；Mac 平台 E2E 配置规则。
- 环境前提：
  - Flutter / Dart tooling 可运行。
  - E2E config 已配置测试账号和 CLI bin。
  - remote `awiki.info` 可访问；如部署未更新，记录为外部风险。

## 7. 验收标准

- [x] performance E2E 报告包含新消息点击首屏指标。
- [x] required metrics / budgets 覆盖该指标。
- [x] 宿主为 Linux，使用 Linux E2E config；Darwin/macOS config 约束不适用且未误用 Linux config 到 Mac。
- [x] `awiki-me` unit/analyze 通过。
- [x] `awiki-cli-rs2` focused tests 通过。
- [x] `awiki-system-test` remote focused suite 运行并记录通过数量：15 passed。
- [x] 文档与实现一致。
- [x] Review 发现已经修复或明确记录。
- [x] 本步骤修改文件已创建聚焦 commit：`awiki-me@ba04e0a`。

## 8. 验证方式

| 检查项 | 命令 / 方法 | 预期证据 |
|---|---|---|
| 平台确认 | `uname -s` | Darwin 时选择 macOS E2E config；Linux 时才检查 Linux config / `xvfb-run`。 |
| AWiki Me analyze | `cd awiki-me && dart analyze` | 无新增 analyzer 错误。 |
| AWiki Me unit | `cd awiki-me && dart run tests/unit/runner.dart` | 单元测试通过。 |
| AWiki Me performance E2E | `cd awiki-me && dart run tests/e2e/runner.dart --case performance --config tests/e2e/configs/e2e.codex-macos-allowed.local.yaml` | performance case 通过；报告中含新指标和 budgets；记录 report path。 |
| Rust focused | `cd awiki-cli-rs2 && cargo test -p im-core --locked realtime` | P0 相关测试通过。 |
| Rust broader | `cd awiki-cli-rs2 && cargo test -p im-core --locked` | `im-core` 回归通过。 |
| System-test remote | `cd awiki-system-test && AWIKI_SYSTEM_TEST_MODE=remote E2E_DID_DOMAIN=awiki.info E2E_USER_SERVICE_URL=https://awiki.info E2E_MESSAGE_SERVICE_URL=https://awiki.info E2E_MESSAGE_SERVICE_WS_URL=wss://awiki.info/im/ws uv run --no-sync pytest tests_v2/message_service/test_sync_delta_local.py tests_v2/message_service/test_sync_thread_after_local.py tests_v2/message_service/test_ws_notifications.py tests_v2/message_service/test_read_watermark_local.py -q -rs` | focused sync/read-state/WS contract 证据；失败时记录部署状态和失败原因。 |
| Docs path check | 使用脚本扫描 `awiki-me/docs/plan/20260628-chat-open-realtime-tail`、`awiki-me/docs`、`awiki-cli-rs2/docs` 中新增内容，确认没有本机绝对路径或本地 workspace 目录名前缀 | 新增文档不含机器特定绝对路径；如命令扫到历史内容，说明并过滤。 |
| Git hygiene | 各受影响仓库 `git status --short --branch` | 最终 Review 前无未解释修改。 |

如果某个命令不能运行，记录原因、影响和替代证据。

## 9. Review 环节

- Review 时机：本步骤 E2E/docs 修改完成后、commit 前；整体验证后还要触发主 Plan 最终全局 Review。
- Review 重点：
  - 新 E2E 指标是否测真实“收到远端新消息后点开”的路径。
  - budgets 是否有可解释 baseline，不会过度 flaky。
  - Mac 平台是否没有使用 Linux config。
  - docs 是否准确表达 P0-P3 的边界。
  - 测试报告是否脱敏。
  - 不因 remote 环境失败而放宽 contract 或跳过关键验证不记录。

| Review 项 | 结果 | 备注 |
|---|---|---|
| 发现问题 | 2 项 | `timings.json` 文档最初把汇总指标写成 `appProductTimings.metrics`，实际为顶层 `metrics` map；全局 analyzer 原有 `_groupCountFromCliOutput` unused warning 会削弱 Step 05 gate 证据。 |
| 已修复问题 | 已修复 | 文档改为顶层 `metrics` map（由 `appProductTimings` 明细汇总）；删除未使用 helper，`dart analyze` 恢复无 warning。 |
| 剩余风险 | 可接受 | 本次真实 performance E2E 使用本地 Linux config 的小数据集 `conversationCount=10`、`longThreadMessageCount=2`；500/1000 大数据集分页 gate 已由前序 conversation pagination 工作支持，但本 Step 05 未重跑大数据集 gate。 |
| 新增或缺失测试 | 已新增 | 新增 E2E required metrics / budgets 覆盖；新增 unit 覆盖默认 required metrics 和 local YAML 与默认 budgets 合并；真实 performance E2E 覆盖 App + CLI peer + 后端链路。 |
| 已更新或缺失文档 | 已更新 | 更新 `awiki-me/README.md`、`awiki-me/docs/performance-tracing.md`、`awiki-me/tests/e2e/flutter/README.md`、`awiki-me/tests/e2e/configs/e2e.example.yaml`；Step 01 已完成 `awiki-cli-rs2` 相关 SDK docs，本步骤未再改 Harness docs。 |

## 10. Commit 要求

- Commit 时机：本步骤 E2E/docs 修改、验证、Review 都完成后；如果没有文件修改则不创建 commit，但必须记录“无变更”。
- Commit 范围：只包含集成 E2E gate、docs 收口和必要测试支持。
- Commit 前状态：记录所有受影响仓库 `git status --short --branch`。
- 纳入文件：记录本步骤 commit 包含的文件。
- Commit 后证据：记录 commit hash 和 commit 后 `git status`。
- 遗留未提交变更：必须记录原因以及为什么安全。
- 建议消息：`test(app): gate realtime chat open performance`

## 11. Blocked 处理

| Blocker | 证据 | 已尝试方案 | 影响范围 | 下一步决策 |
|---|---|---|---|---|
| 远端 `awiki.info` 未部署最新 sync / ws 能力 | pytest 失败摘要、响应码、日志或服务版本 | 重跑 focused suite、检查环境变量、确认部署状态 | System-test remote gate | 记录为 release/deployment blocker，不放宽测试 |
| E2E config 缺测试账号或 CLI bin | runner 配置错误摘要 | 检查本地 config、dry-run、红acted report | AWiki Me E2E | 请求用户补配置或记录 not-run |
| Mac E2E 误启动 Linux config | `uname -s` 与 runner config 不一致 | 停止错误运行，删除错误临时进程，改用 Mac config | 当前验证 | 重新运行并记录纠正 |

## 12. Plan 变更记录

| 日期 | 变更 | 原因 | 主 Plan 变更记录链接 |
|---|---|---|---|
| 2026-06-28 | 初始 Step 05 计划 | 集成验证 P0-P3 并收口 E2E/docs。 | [../plan.md#15-plan-变更记录](../plan.md#15-plan-变更记录) |

## 13. 风险、回滚与后续文档

- 风险：E2E 指标绕过真实 UI click、budget 不稳定、remote 环境失败造成误判。
- 回滚 / 回退：回滚 E2E/docs commit 不影响 P0-P4 功能；但 release 前必须保留等价验证证据。
- 后续文档：最终全局 Review 后，如架构层总结需要同步 Harness feature doc，必须在本步骤或最终集成 commit 中完成。
