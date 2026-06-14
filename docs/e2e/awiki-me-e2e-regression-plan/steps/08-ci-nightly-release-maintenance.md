# Step 08：CI/nightly/release gate 与维护机制

主 Plan：[../plan.md](../plan.md)  
Step index：08  
状态：draft

## 1. 执行状态

| 字段 | 值 |
|---|---|
| Status | pending |
| Branch | 待执行时记录 |
| Started | 待记录 |
| Completed | 待记录 |
| Commit | 待记录 |
| Review evidence | 待记录 |
| Verification evidence | 待记录 |
| Next action | 建立自动化 gate、报告、flake 和最终维护机制 |

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

## 5. 路径

| 仓库 / 模块 / 文件 | 计划变更 | 备注 |
|---|---|---|
| `test-awiki-me/.github/workflows/` | 后续更新 CI/nightly workflow | 如存在 |
| `test-awiki-me/docs/testing.md` | 同步最终 gate 命令和策略 | 用户入口文档 |
| `test-awiki-me/tests/e2e_test/README.md` | 同步 E2E runner 和 report 规则 | 测试域文档 |
| `test-awiki-me/docs/e2e/awiki-me-e2e-regression-plan/plan.md` | 回填最终 Review 和执行证据 | 本计划入口 |
| `awiki-system-test/` | 需要时接入服务侧 nightly suite | 跨仓证据 |

## 6. 依赖

- 前置步骤：Step 04、Step 05、Step 06、Step 07。
- 外部文档或决策：CI runner 类型、nightly secret、账号池、设备池、release gate owner。
- 环境前提：CI 或 self-hosted runner 可用。

## 7. 验收标准

- [ ] PR required gate 不依赖真实后端、OTP、设备池、SSH。
- [ ] Nightly/release gate 明确需要哪些 secret 和 local config。
- [ ] Linux headless 命令使用 `xvfb-run`。
- [ ] macOS/Linux/mobile 的报告字段一致。
- [ ] Flake 分类和处理流程明确。
- [ ] `AGENT-SKIP-001` 和 `E2EE-SKIP-001` 保留为 skipped，不被误加入 gate。
- [ ] 最终全局 Review 和整体验证完成并记录。
- [ ] 本步骤在进入最终收口前已经创建聚焦 commit。

## 8. 验证方式

| 检查项 | 命令 / 方法 | 预期证据 |
|---|---|---|
| PR gate | `cd test-awiki-me && dart analyze && flutter test tests/unit_test` | required gate 通过。 |
| Dry-run gate | `cd test-awiki-me && dart run tests/e2e_test/harness/mobile_e2e_runner.dart --config tests/e2e_test/configs/mobile.example.yaml --dry-run` | mobile dry-run 通过。 |
| Desktop dry-run | `cd test-awiki-me && dart run tests/e2e_test/harness/desktop_e2e_runner.dart --platform=linux --dry-run --skip-cli-build --skip-flutter-smoke` | desktop dry-run 通过。 |
| Linux optional | `cd test-awiki-me && AWIKI_SQLITE3_SOURCE_DIR=/tmp/awiki-sqlite3 xvfb-run -a flutter test integration_test/app_smoke_test.dart -d linux` | Linux smoke 通过或记录 runner 不支持。 |
| Nightly/manual | 按 Step 05-07 real run 命令 | 有 pass/fail/skipped 证据和 report path。 |
| Secret | 扫描新增 workflow/docs/report sample | 不包含 secret。 |

## 9. Review 环节

- Review 时机：gate/workflow/docs 调整完成后、commit 前；全部步骤完成后再执行最终全局 Review。
- Review 重点：required gate 是否过重，nightly secret 是否安全，workflow 是否提交 local state，release gate 是否可执行，失败分类是否可操作。
- Review 结论必须在 commit 前记录。

| Review 项 | 结果 | 备注 |
|---|---|---|
| 发现问题 | 待记录 |  |
| 已修复问题 | 待记录 |  |
| 剩余风险 | 待记录 |  |
| 新增或缺失测试 | 待记录 |  |
| 已更新或缺失文档 | 待记录 |  |

## 10. Commit 要求

- Commit 时机：gate/docs/workflow 更新、验证、Review 都完成后。
- Commit 范围：CI/nightly/release gate 和维护文档相关文件。
- Commit 前状态：记录 `git status --short --branch`。
- 纳入文件：记录本步骤 commit 包含的文件。
- Commit 后证据：记录 commit hash 和 commit 后 `git status`。
- 建议消息：`ci: wire e2e regression gates`

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
