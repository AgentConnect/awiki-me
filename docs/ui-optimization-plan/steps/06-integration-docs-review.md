# Step 06：E2E / 集成验证与文档

主 Plan：[../plan.md](../plan.md)
Step index：06
状态：done

## 1. 执行状态

| 字段 | 值 |
|---|---|
| Status | done |
| Branch | `awiki-me-ui:feature/release-0526/ui-optimization` |
| Started | 2026-06-15 |
| Completed | 2026-06-15 |
| Commit | 用户已要求统一提交、推送并合并到 `release/0526`；不再按 Step 拆分提交 |
| Review evidence | Review 确认 integration smoke 覆盖 AppShell → 消息页 → 默认关闭 → 会话信息 → 智能体信息弹窗 → Agent 收件箱入口；screenshot smoke 覆盖关键 UI 视觉状态 |
| Verification evidence | `flutter analyze ...`、focused unit 151 passed、`LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 flutter test integration_test/app_smoke_test.dart -d macos` 4 passed、`LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 flutter test integration_test/ui_visual_verification_test.dart -d macos` 1 passed、`git diff --check` 通过 |
| Next action | 无 |

## 2. 目标

- 结果：为本轮 UI 优化补齐集成 smoke、screenshot visual smoke、文档和最终审计证据。
- 用户 / 系统可见行为：可通过 fake-bootstrap app smoke 端到端走到关键 UI 入口，并通过 PNG 截图审阅视觉结果。
- 非目标：不跑真实后端多客户端 E2E；本轮 UI-only smoke 使用 fake bootstrap。
- 完成标准：计划文档、`docs/testing.md`、analyze、unit、integration smoke、screenshot smoke、diff check 均有证据。

## 3. 设计方法

- 设计边界：集成测试只验证 App 内 UI 流程；screenshot smoke 使用确定性 fake bootstrap 数据，不模拟真实 daemon inbox payload。
- 核心决策：复用 `integration_test/app_smoke_test.dart` / `integration_test/ui_visual_verification_test.dart` shims 和 `tests/e2e/flutter/support/fake_app_bootstrap.dart`。
- 契约 / API / 数据流：使用 fake `ConversationListController` 固定会话，避免 AppRuntime refresh race。
- 兼容性：保留原 app smoke 的 onboarding / authenticated shell / settings 测试。
- 风险控制：macOS CocoaPods 需要 UTF-8 locale，文档记录 `LANG` / `LC_ALL`。

## 4. 实现方法

1. 在 app smoke 中新增 UI optimization smoke。
2. 修复原 app smoke 在 macOS rail / phone nav 下的点击兼容问题。
3. 新增 screenshot smoke：启动 `AwikiMeApp`，采集登录页、聊天页、会话信息侧栏、智能体信息弹窗、Agent 收件箱列表 / 线程、Hermes 类型选择弹窗截图。
4. 更新 `docs/testing.md` 的 focused unit、integration 与 screenshot 命令。
5. 补齐主 Plan 和 Step 文档，记录最终 Review 与验证证据。

## 5. 路径

| 仓库 / 模块 / 文件 | 计划变更 | 备注 |
|---|---|---|
| `awiki-me-ui/tests/e2e/flutter/app/app_smoke_test.dart` | 新增 UI optimization smoke | Integration |
| `awiki-me-ui/tests/e2e/flutter/app/ui_visual_verification_test.dart` | 新增 screenshot visual smoke | Integration / Visual |
| `awiki-me-ui/integration_test/ui_visual_verification_test.dart` | Flutter tooling root shim | Integration / Visual |
| `awiki-me-ui/docs/testing.md` | 记录 focused checks 和 UTF-8 macOS 命令 | Docs |
| `awiki-me-ui/docs/ui-optimization-plan/plan.md` | 主 Plan / 台账 / 最终审计 | Docs |
| `awiki-me-ui/docs/ui-optimization-plan/steps/*.md` | 小 Plan 文档 | Docs |
| `awiki-me-ui/docs/ui-optimization-plan/screenshots/*.png` | UI 视觉验证截图 | Evidence |

## 6. 依赖

- 前置步骤：Step 01-05。
- 外部文档或决策：`awiki-plan` 要求文档化计划、Review 和验证。
- 环境前提：macOS Flutter desktop runner。

## 7. 验收标准

- [x] integration smoke 覆盖关键 UI 入口。
- [x] screenshot smoke 生成并人工核验关键 UI 截图。
- [x] `docs/testing.md` 记录本轮测试命令。
- [x] 主 Plan 与小 Plan 台账回填。
- [x] analyze / unit / integration / diff check 通过。
- [x] Review 发现已经修复或明确记录。
- [x] 本步骤纳入统一集成提交；用户已要求推送并合并到 `release/0526`。

## 8. 验证方式

| 检查项 | 命令 / 方法 | 预期证据 |
|---|---|---|
| Analyze | `cd awiki-me-ui && flutter analyze ...` | No issues found |
| Unit | `cd awiki-me-ui && flutter test tests/unit/agents/agent_inbox_provider_test.dart tests/unit/agents/agents_page_layout_test.dart tests/unit/agents/agent_control_payload_test.dart tests/unit/agents/agent_control_service_test.dart tests/unit/conversation_workspace_test.dart tests/unit/chat_page_test.dart tests/unit/onboarding_page_test.dart` | 151 passed |
| Integration | `cd awiki-me-ui && LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 flutter test integration_test/app_smoke_test.dart -d macos` | 4 passed |
| Screenshot visual | `cd awiki-me-ui && LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 flutter test integration_test/ui_visual_verification_test.dart -d macos` | 1 passed；生成 `awiki-me-ui/docs/ui-optimization-plan/screenshots/01-onboarding-login.png` 到 `awiki-me-ui/docs/ui-optimization-plan/screenshots/07-agent-create-agent-type.png` |
| Docs / whitespace | `cd awiki-me-ui && git diff --check` | 通过 |

## 9. Review 环节

| Review 项 | 结果 | 备注 |
|---|---|---|
| 发现问题 | `flutter test integration_test/app_smoke_test.dart -d macos` 首次因 CocoaPods ASCII-8BIT 失败；原 app smoke 点击在 macOS rail 不稳定；附件本机打开缺专项测试；screenshot smoke 首次直接 tap offscreen 收件箱行未命中 | 已修复并记录 UTF-8 命令；screenshot smoke 改为 `ensureVisible` 后通过 |
| 已修复问题 | app smoke 导航 finder 兼容；新增 UI smoke；新增 attachment native open test；新增 screenshot smoke 与截图证据 | 已验证通过 |
| 剩余风险 | screenshot smoke 使用 fake bootstrap / render capture；不验证真实 daemon payload 或真实后端多客户端 E2E | 当前不阻塞 |
| 新增或缺失测试 | 已新增 integration smoke、screenshot smoke 与附件 native open unit | 无缺失 |
| 已更新或缺失文档 | 已更新 `docs/testing.md` 与 plan docs | 无缺失 |

## 10. Commit 要求

- Commit 时机：用户已确认，纳入统一集成提交。
- Commit 范围：本轮 UI 优化代码、测试、文档、截图证据。
- 建议消息：`test(app): add ui optimization smoke coverage`

## 11. Blocked 处理

| Blocker | 证据 | 已尝试方案 | 影响范围 | 下一步决策 |
|---|---|---|---|---|
| CocoaPods 非 UTF-8 环境失败 | ASCII-8BIT `Encoding::CompatibilityError` | 设置 `LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8` 后通过 | integration 命令环境 | 文档记录 UTF-8 命令 |

## 12. Plan 变更记录

| 日期 | 变更 | 原因 | 主 Plan 变更记录链接 |
|---|---|---|---|
| 2026-06-15 | 增加 final integration step 证据 | 完成审计与恢复执行 | `../plan.md#15-plan-变更记录` |
| 2026-06-15 | 增加 screenshot visual smoke 和截图证据 | 用户要求启动 App 后做 UI / 视觉层验证 | `../plan.md#15-plan-变更记录` |

## 13. 风险、回滚与后续文档

- 风险：fake-bootstrap smoke / screenshot smoke 不验证真实 daemon inbox payload；macOS runner 可能打印 `Failed to foreground app; open returned 1`，但 render tree 截图和测试断言仍可通过。
- 回滚 / 回退：保留 unit 覆盖，移除新增 app smoke / screenshot smoke case 与截图证据。
- 后续文档：若新增 CI gate，需把 UTF-8 环境变量写入 workflow；若需要像素级验收，需引入 golden 或设计基准图。
