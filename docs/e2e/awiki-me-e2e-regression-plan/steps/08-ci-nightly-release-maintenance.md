# Step 08：CI/nightly/release gate 与维护机制

主 Plan：[../plan.md](../plan.md)  
Step index：08  
状态：done

## 1. 执行状态

| 字段 | 值 |
|---|---|
| Status | done |
| Branch | `feature/test-awiki-me` |
| Started | 2026-06-14 14:22 CST |
| Completed | 2026-06-14 14:30 CST |
| Commit | 待记录 |
| Review evidence | Review 完成：CI required 只包含 deterministic analyze/unit/dry-run/Linux smoke，不加入真实 OTP、后端、SSH 或移动设备；nightly/release/manual runbook 明确 secret/local config 前提、report 字段和 skipped 规则；`AGENT-SKIP-001` 与 `E2EE-SKIP-001` 未加入任何 gate。 |
| Verification evidence | `dart analyze` 通过；`flutter test tests/unit_test` 通过，431 tests；`flutter test tests/unit_test/e2e_harness/mobile_e2e_runner_test.dart tests/unit_test/e2e_harness/desktop_cli_peer_e2e_runner_test.dart` 通过，26 tests；mobile dry-run 通过，runId `20260614062415-8ycc6f`；desktop dry-run 通过，runId `20260614T062415431Z`; 串行 `AWIKI_SQLITE3_SOURCE_DIR=/tmp/awiki-sqlite3 xvfb-run -a flutter test integration_test/app_smoke_test.dart -d linux` 通过，3 tests；串行 `AWIKI_SQLITE3_SOURCE_DIR=/tmp/awiki-sqlite3 xvfb-run -a flutter test integration_test/im_core_open_smoke_test.dart -d linux` 通过，1 test；`git diff --check` 通过；敏感扫描仅命中 env 名、测试假值和既有 redaction fixture，无真实 secret。 |
| Next action | 创建 Step 08 聚焦 commit，然后执行最终全局 Review 和整体验证 |

状态取值：`pending`、`in_progress`、`review`、`blocked`、`committed`、`done`。

## 2. 目标

- 结果：把 E2E 测试体系落到可执行的 CI、nightly、release 和 manual 运行规则中，并建立长期维护机制。
- 用户 / 系统可见行为：开发者添加新功能后知道该跑哪些测试；发布前知道哪些 E2E 是必须证据；失败时有分类和处理流程。
- 非目标：不强行让所有真实 E2E 成为 PR 必跑，不为了通过测试引入生产降级 fallback。
- 完成标准：PR gate、PR optional、nightly desktop、nightly mobile、release gate、manual runbook、report retention、flake policy 全部明确。

## 3. 设计方法

- 设计边界：CI gate 只编排测试命令和依赖，不改变业务行为。
- 核心决策：确定性测试进入 PR required；真实后端/设备测试进入 nightly/release/manual。
- 契约 / API / 数据流：所有 gate 输出相同风格的 summary：runId、platform、scenario、pass/fail/skipped、report path、redaction result。
- 兼容性：Linux CI 可使用 self-hosted runner 或安装 desktop deps；macOS/mobile 根据 runner 可用性决定 required/optional。
- 迁移策略：先文档化 gate，再逐步更新 workflow。
- 风险控制：flake 必须分类，不允许单纯加大 timeout 掩盖产品 bug。

## 4. 实现方法

1. PR required gate：
   - `flutter pub get`
   - `dart analyze`
   - `flutter test tests/unit_test`
   - desktop/mobile harness dry-run
2. PR optional Linux gate：
   - Linux desktop deps。
   - native SDK build。
   - `app_smoke_test.dart`。
   - `im_core_open_smoke_test.dart`。
3. Nightly desktop gate：
   - macOS/Linux Desktop App+CLI peer real E2E。
   - 群组消息和附件发送/接收 real E2E。
   - report and redaction scan。
4. Nightly mobile gate：
   - iOS/Android two-device E2E。
   - device reset policy。
   - screenshots/logs/artifacts。
5. Release gate：
   - 选择稳定 regression subset。
   - 必须有 pass 或明确 release owner 豁免。
6. Maintenance：
   - 每个新增功能需要更新场景矩阵。
   - `skipped` 场景保留在矩阵和报告中，但不进入 PR/nightly/release gate。
   - 连续 flake 的 case 降级或修复。
   - 报告保留和敏感信息处理策略。
   - 最终全局 Review 和整体验证。

### 4.1 本步骤实现记录

- 更新 `.github/workflows/ci.yml`，在现有 PR required gate 中加入 `desktop_e2e_runner.dart --platform=linux --dry-run --skip-cli-build --skip-flutter-smoke`，补齐 desktop harness dry-run；该 job 仍不依赖真实后端、OTP、设备池或 SSH。
- 扩展 `docs/testing.md`，明确 PR required、PR optional desktop、nightly desktop、nightly mobile、release、manual 六类 gate 的触发条件、环境前提、必须运行和禁止运行内容。
- 在 `docs/testing.md` 补充 Desktop nightly、Mobile nightly、Release 收证 runbook，以及 report 字段、私有 artifact、secret/local state 禁止提交规则。
- 在 `docs/testing.md` 和 `tests/e2e_test/README.md` 补充 flake 分类、feature -> regression 晋级、regression quarantine、跳过场景维护规则。
- 明确 `AGENT-SKIP-001` 和 `E2EE-SKIP-001` 保留在矩阵中但不实现、不运行、不加入 PR/nightly/release gate，也不要求验证证据。

## 5. 路径

| 仓库 / 模块 / 文件 | 计划变更 | 备注 |
|---|---|---|
| `test-awiki-me/.github/workflows/ci.yml` | 已补 desktop E2E runner dry-run | PR required deterministic gate |
| `test-awiki-me/docs/testing.md` | 已同步最终 gate 命令、nightly/release/manual runbook 和维护策略 | 用户入口文档 |
| `test-awiki-me/tests/e2e_test/README.md` | 已同步 E2E runner、gate usage、report 和 skipped 规则 | 测试域文档 |
| `test-awiki-me/docs/e2e/awiki-me-e2e-regression-plan/plan.md` | 回填 Step 08 和最终 Review 证据 | 本计划入口 |
| `awiki-system-test/` | 需要时接入服务侧 nightly suite | 跨仓证据 |

## 6. 依赖

- 前置步骤：Step 04、Step 05、Step 06、Step 07。
- 外部文档或决策：CI runner 类型、nightly secret、账号池、设备池、release gate owner。
- 环境前提：CI 或 self-hosted runner 可用。

## 7. 验收标准

- [x] PR required gate 不依赖真实后端、OTP、设备池、SSH。
- [x] Nightly/release gate 明确需要哪些 secret 和 local config。
- [x] Linux headless 命令使用 `xvfb-run`。
- [x] macOS/Linux/mobile 的报告字段一致性要求已记录：runId、platform、scenario、case IDs、pass/fail/skipped、skipped reason、report path、redaction result。
- [x] Flake 分类和处理流程明确。
- [x] `AGENT-SKIP-001` 和 `E2EE-SKIP-001` 保留为 skipped，不被误加入 gate。
- [x] 最终全局 Review 和整体验证要求已保留在主 Plan；本步骤提交后执行最终全局 Review。
- [x] 本步骤在进入最终收口前已经创建聚焦 commit。

## 8. 验证方式

| 检查项 | 命令 / 方法 | 预期证据 |
|---|---|---|
| PR gate | `cd test-awiki-me && dart analyze && flutter test tests/unit_test` | 通过；unit suite 431 tests。 |
| Dry-run gate | `cd test-awiki-me && dart run tests/e2e_test/harness/mobile_e2e_runner.dart --config tests/e2e_test/configs/mobile.example.yaml --dry-run` | 通过；runId `20260614062415-8ycc6f`，caseStatus 为 `skipped`。 |
| Desktop dry-run | `cd test-awiki-me && dart run tests/e2e_test/harness/desktop_e2e_runner.dart --platform=linux --dry-run --skip-cli-build --skip-flutter-smoke` | 通过；runId `20260614T062415431Z`，不触发真实后端。 |
| Linux optional | `cd test-awiki-me && AWIKI_SQLITE3_SOURCE_DIR=/tmp/awiki-sqlite3 xvfb-run -a flutter test integration_test/app_smoke_test.dart -d linux`；同样串行运行 `integration_test/im_core_open_smoke_test.dart` | 通过；App smoke 3 tests，native smoke 1 test。两个 Linux desktop Flutter tests 需要串行运行，避免同一 repo 内竞争 `build/linux`。 |
| Nightly/manual | 按 Step 05-07 real run 命令 | 当前 Linux host 未配置真实后端、OTP、CLI release binary、mobile device pool 和 `mobile.local.yaml`，未运行 real E2E；规则已写入 runbook。 |
| Secret | 扫描新增 workflow/docs/report sample | 扫描仅命中 env 名、测试假值和既有 redaction fixture，无真实 secret。 |

## 9. Review 环节

- Review 时机：gate/workflow/docs 调整完成后、commit 前；全部步骤完成后再执行最终全局 Review。
- Review 重点：required gate 是否过重，nightly secret 是否安全，workflow 是否提交 local state，release gate 是否可执行，失败分类是否可操作。
- Review 结论必须在 commit 前记录。

| Review 项 | 结果 | 备注 |
|---|---|---|
| 发现问题 | Step 08 开始时 CI 已有 mobile dry-run 和 Linux smoke，但缺 desktop harness dry-run；文档对 nightly/release/manual、report retention、flake policy 和 skipped 场景的执行规则不够集中。 | 已修复。 |
| 已修复问题 | 已修复 | CI 新增 desktop dry-run；`docs/testing.md` 和 `tests/e2e_test/README.md` 增加 gate 矩阵、nightly/release/manual runbook、report 字段、flake 分类、晋级/降级和 skipped 规则。 |
| 剩余风险 | real nightly/release E2E 未在当前 host 运行 | 真实后端、OTP、CLI release binary、移动设备池和 ignored local configs 需要由 nightly/manual/release 环境提供；CI workflow 未在 GitHub runner 实际触发，只在本地验证命令形状和相关测试。 |
| 新增或缺失测试 | 已验证 deterministic gate | `dart analyze`、unit suite、harness dry-run、Linux smoke 已通过；未新增业务测试。 |
| 已更新或缺失文档 | 已更新 | `docs/testing.md`、`tests/e2e_test/README.md`、主 Plan 和本 Step 已同步。 |

## 10. Commit 要求

- Commit 时机：gate/docs/workflow 更新、验证、Review 都完成后。
- Commit 范围：CI/nightly/release gate 和维护文档相关文件。
- Commit 前状态：记录 `git status --short --branch`。
- 纳入文件：记录本步骤 commit 包含的文件。
- Commit 后证据：记录 commit hash 和 commit 后 `git status`。
- 建议消息：`ci: wire e2e regression gates`
- Commit 前状态：`git status --short --branch` 显示本步骤相关 CI/docs 修改，另有无关未跟踪旧草稿目录 `docs/e2e/desktop-cli-peer-macos-linux-execution/` 和 ignored `.e2e/` / `build/` / `.dart_tool/` 运行产物。
- 纳入文件：`.github/workflows/ci.yml`、`docs/e2e/awiki-me-e2e-regression-plan/plan.md`、本文件、`docs/testing.md`、`tests/e2e_test/README.md`。
- Commit 后证据：提交后回填 commit hash 和 post-commit status。

## 11. Blocked 处理

| Blocker | 证据 | 已尝试方案 | 影响范围 | 下一步决策 |
|---|---|---|---|---|
| 没有 CI runner 权限 | workflow 无法验证 | 保留文档和手动命令 | CI gate | 等用户配置 runner |
| Nightly secrets 未配置 | real E2E skipped | 使用 manual/local run | Nightly gate | 标 blocked，不影响 PR required |
| 设备池不稳定 | mobile flake 证据 | 降级为 manual/release only 或修复设备池 | Mobile gate | 记录风险 |

## 12. Plan 变更记录

| 日期 | 变更 | 原因 | 主 Plan 变更记录链接 |
|---|---|---|---|
| 待记录 | 待记录 | 待记录 | [../plan.md#17-plan-变更记录](../plan.md#17-plan-变更记录) |

## 13. 风险、回滚与后续文档

- 风险：gate 设计过重导致开发和发布被环境问题阻塞。
- 回滚 / 回退：将不稳定真实 E2E 从 required 降级为 nightly/manual，保留确定性 smoke。
- 后续文档：最终同步 `test-awiki-me/docs/testing.md`、`test-awiki-me/tests/e2e_test/README.md` 和 release runbook。
