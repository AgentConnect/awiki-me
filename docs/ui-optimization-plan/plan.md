# Plan：awiki-me UI 优化

状态：done（代码、测试、文档、截图验证已完成；用户已要求提交、推送并合并到 `release/0526`）
DOC：`awiki-me-ui/docs/ui-optimization-plan/`
Harness：`awiki-harness/`
创建时间：2026-06-14
最后更新：2026-06-15
恢复指针：所有 Step 已完成；如继续恢复，请从第 17 节最终审计和当前 `git status --short --branch` 开始。

## 1. 目标

- 任务目标：基于 `awiki-me-ui` worktree（`feature/release-0526/ui-optimization`）完成用户列出的 UI / 交互问题。
- 预期行为：
  1. 宿主代理安装 / 创建 Runtime Agent 流程增加 Agent 类型选择；本轮只支持 Hermes。
  2. 消息页会话信息默认关闭，只在用户主动打开时显示。
  3. 用户 / 智能体信息改为弹窗；会话页点击头像或信息入口打开弹窗；身份卡、关注、Agent 收件箱迁移到该弹窗。
  4. Agent 收件箱展示消息时间和最新消息；默认分页大小为最新 20 条，并保留继续拉取旧消息能力。
  5. 身份卡与 Agent 收件箱文字可选择、可复制。
  6. 登录页图片和布局对齐，统一 logo 使用与文案。
  7. 聊天附件查看优先调用本机应用打开文件。
- 非目标：不改服务端协议、不新增 Hermes 以外的 Agent 类型、不修改平台 runner、不引入 production mock。
- 完成标准：每个显式需求均有代码实现、测试或静态证据；`docs/testing.md` 与本计划记录验证命令；final Review 无阻断项。

## 2. Harness 上下文

| 来源 | 作用 |
|---|---|
| `awiki-harness/AGENTS.md` | 确认非平凡 AWiki 任务需要计划、验证、Review 和文档同步。 |
| `awiki-harness/README.md` | 确认 Harness 作为多仓库控制面，只路由不替代目标仓库文档。 |
| `awiki-harness/context/00-context-map.md` | 将本任务路由到 Client Architecture、Message Flow、Agent Runtime Host。 |
| `awiki-harness/context/02-repo-map.md` | 确认本轮主要影响 `awiki-me-ui` Flutter App。 |
| `awiki-harness/context/03-cross-repo-architecture.md` | 确认 App 不直接改 wire / 服务端消息投递语义。 |
| `awiki-harness/context/20-rules-index.md` | 定位文档同步、验证和代码 Review 规则。 |
| `awiki-harness/context/30-tools-env.md` | 确认 Flutter / Dart 验证命令入口。 |
| `awiki-harness/context/40-verification.md` | 将本轮 UI/provider/widget 改动归为 L1 + integration smoke。 |
| `awiki-harness/context/50-task-workflow.md` | 用作执行台账、Review 和恢复协议依据。 |
| `awiki-harness/context/nodes/client-architecture.node.md` | App 只做 UI/provider/service adapter，复用已有 service。 |
| `awiki-harness/context/nodes/message-flow.node.md` | 附件查看属于客户端呈现，不改变消息投递语义。 |
| `awiki-harness/context/nodes/agent-runtime-host.node.md` | Runtime Agent 由 Daemon 管理，App 通过 control payload 查询 Agent 收件箱。 |

## 3. 影响分析

| 领域 / 仓库 / 模块 | 影响 | 权威文档或代码 |
|---|---|---|
| Agent 管理 | 创建 Agent dialog 增加类型选择；宿主安装命令增加 Hermes 类型提示 | `awiki-me-ui/lib/src/presentation/agents/agents_page.dart` |
| Agent 收件箱 | 默认 limit=20；支持 cursor 分页；显示时间和最新预览；文字可选择复制 | `awiki-me-ui/lib/src/presentation/agents/agent_inbox_provider.dart`、`awiki-me-ui/lib/src/presentation/agents/agent_inbox_panel.dart` |
| Agent control command | list/thread 默认 limit 从旧值统一到 20 | `awiki-me-ui/lib/src/domain/entities/agent/agent_command.dart`、`awiki-me-ui/lib/src/application/agent/agent_control_service.dart` |
| 消息会话 | 会话信息默认关闭；直聊资料弹窗迁移；群聊信息侧栏保持 | `awiki-me-ui/lib/src/presentation/conversation_list/conversation_workspace_page.dart`、`awiki-me-ui/lib/src/presentation/chat/chat_page.dart` |
| Profile / 关系 | 用户 / Agent 弹窗中显示身份卡、关注、主页和 DID copy | `awiki-me-ui/lib/src/presentation/chat/chat_page.dart` |
| Onboarding | 登录页 logo 和 hero 对齐，修正文案 | `awiki-me-ui/lib/src/presentation/onboarding/onboarding_page.dart` |
| 附件查看 | 查看附件时调用本机应用打开 local file / saved file | `awiki-me-ui/lib/src/presentation/chat/chat_page.dart` |
| 测试 | 单元 / Widget / integration smoke / screenshot smoke 覆盖本轮行为 | `awiki-me-ui/tests/unit_test/**`、`awiki-me-ui/tests/integration_test/app/app_smoke_test.dart`、`awiki-me-ui/tests/integration_test/app/ui_visual_verification_test.dart` |
| 文档 | 记录 focused checks、UTF-8 macOS integration 命令、截图证据和计划证据 | `awiki-me-ui/docs/testing.md`、`awiki-me-ui/docs/ui-optimization-plan/` |

## 4. 假设与开放问题

### 假设

- 当前 Runtime Agent 类型只有 Hermes；UI 不暴露可用的第二类型。
- Agent 收件箱仍通过既有 Daemon control payload 返回状态，不改后端 schema。
- fake-bootstrap integration smoke 足以验证本轮 UI-only 端到端入口；真实多客户端 / Daemon E2E 不属于本轮必要范围。
- macOS integration 运行环境需要显式 UTF-8 locale。

### 开放问题

- 若未来新增 runtime 类型，需要重新设计类型选择模型与 control payload。
- 若设计稿对登录页精确像素有要求，需要在当前截图 smoke 基础上继续做像素级设计验收。
- 真实 Daemon 收件箱 payload 的时间字段缺失时，当前 UI 隐藏时间标签；后续可补协议约束。

## 5. 总体设计方法

- 设计边界：仅修改 `awiki-me-ui` Flutter/Dart 代码、测试和文档。
- 关键决策：直聊用户 / Agent 信息统一为 popup；会话信息右栏只承载“会话信息”和群信息；Agent 收件箱作为 Agent 信息弹窗内的子面板。
- 兼容性策略：群聊信息入口保持原侧栏逻辑；移动端 Runtime Agent 收件箱全屏入口保持；附件打开失败时保留错误提示。
- 数据、协议、配置或迁移策略：无 schema / config / migration 变更；仅 control query 默认 limit 调整为 20。
- 风险控制：通过 focused widget tests + fake-bootstrap macOS integration smoke + screenshot visual smoke + static analyze + diff check 验证。

## 6. 任务拆分

| Step | 标题 | 依赖 | 产出 | 小 Plan 文档 | Commit gate | 状态 |
|---|---|---|---|---|---|---|
| 01 | Agent 类型选择（Hermes only） | 无 | Hermes 类型选择 UI / 安装提示 / 测试 | [steps/01-agent-type-selector.md](steps/01-agent-type-selector.md) | 统一提交 | done |
| 02 | 会话信息默认关闭与用户 / 智能体信息弹窗 | 无 | 默认关闭、资料弹窗、关注和 Agent 收件箱入口迁移 | [steps/02-conversation-info-peer-popup.md](steps/02-conversation-info-peer-popup.md) | 统一提交 | done |
| 03 | Agent 收件箱增强 | Step 02 | limit=20、分页、排序、时间、SelectionArea | [steps/03-agent-inbox-enhancement.md](steps/03-agent-inbox-enhancement.md) | 统一提交 | done |
| 04 | 登录页图片和 UI 对齐 | 无 | logo / hero / 文案修正 | [steps/04-onboarding-ui.md](steps/04-onboarding-ui.md) | 统一提交 | done |
| 05 | 附件本机应用打开 | 无 | native open path、按钮语义、测试 | [steps/05-native-attachment-open.md](steps/05-native-attachment-open.md) | 统一提交 | done |
| 06 | E2E / 集成验证与文档 | Step 01-05 | integration smoke、docs、final review | [steps/06-integration-docs-review.md](steps/06-integration-docs-review.md) | 统一提交 | done |

## 7. 执行台账

状态取值：`pending`、`in_progress`、`review`、`blocked`、`committed`、`done`。

| Step | 状态 | 分支 | 开始时间 | 完成时间 | Commit | Review 证据 | 验证证据 | 下一步 |
|---|---|---|---|---|---|---|---|---|
| 01 | done | `awiki-me-ui:feature/release-0526/ui-optimization` | 2026-06-14 | 2026-06-15 | 统一提交中 | Hermes-only UI 不改变 create payload | `agents_page_layout_test.dart` 通过；analyze 通过 | 无 |
| 02 | done | `awiki-me-ui:feature/release-0526/ui-optimization` | 2026-06-14 | 2026-06-15 | 统一提交中 | 默认关闭、popup 迁移、群信息侧栏回归已 Review | `conversation_workspace_test.dart` / `chat_page_test.dart` / app smoke 通过 | 无 |
| 03 | done | `awiki-me-ui:feature/release-0526/ui-optimization` | 2026-06-14 | 2026-06-15 | 统一提交中 | limit=20、排序、分页、SelectionArea 已 Review | `agent_inbox_provider_test.dart` 通过；focused unit 通过 | 无 |
| 04 | done | `awiki-me-ui:feature/release-0526/ui-optimization` | 2026-06-14 | 2026-06-15 | 统一提交中 | logo / hero / 文案已 Review | `onboarding_page_test.dart` 与 app smoke 通过 | 无 |
| 05 | done | `awiki-me-ui:feature/release-0526/ui-optimization` | 2026-06-14 | 2026-06-15 | 统一提交中 | native open 路径和失败提示已 Review | `chat_page_test.dart` 新增 native open 测试通过 | 无 |
| 06 | done | `awiki-me-ui:feature/release-0526/ui-optimization` | 2026-06-15 | 2026-06-15 | 统一提交中 | final Review 与截图人工核验已完成，剩余风险已记录 | analyze / unit / integration / screenshot smoke / diff check 通过 | 执行提交、推送并合并到 `release/0526` |

## 8. Codex Goal 执行协议

- 将本 Plan 作为执行进度的唯一事实来源。
- 启动或恢复前，读取本 Plan、当前小 Plan、执行台账和当前 `git status`。
- 同一时间只执行一个步骤，除非本 Plan 明确标记多个步骤彼此独立且可以并行。
- 恢复时，从第一个状态不是 `done` 的步骤继续；当前所有步骤已 done。
- 每个步骤依次执行：标记 `in_progress`、实现、验证、Review、修复 Review 发现、提交或记录未提交原因、记录证据、标记 `done`。
- 改变范围、顺序、验收标准、公开契约、数据模型或验证策略前，先更新本 Plan。

## 8.1 Codex Goal 提示词

```text
请以 `awiki-me-ui/docs/ui-optimization-plan/plan.md` 为唯一规划入口，继续 awiki-me-ui UI 优化任务。

开始前先读取：
- `awiki-me-ui/docs/ui-optimization-plan/plan.md`
- 当前第一个未 done 的 Step 文档（当前均为 done 时读取第 17 节最终审计）
- 主 Plan 的执行台账、验证策略、Blocked 处理和 Plan 变更记录
- 当前 `git status --short --branch`

若发现实现或验证被后续修改破坏，请按对应 Step 小 Plan 修复、验证并回填台账；每次范围变化先更新 Plan 变更记录。
完成前必须确认：Hermes-only 类型选择、会话信息默认关闭、用户/Agent 信息弹窗、Agent 收件箱分页/时间/可复制、登录页 logo 对齐、附件本机打开、integration smoke 和 docs 都仍成立。
```

## 9. 小 Plan 摘要

### Step 01：Agent 类型选择（Hermes only）

- 小 Plan：[steps/01-agent-type-selector.md](steps/01-agent-type-selector.md)
- 目标：创建 Runtime Agent / 安装宿主代理流程展示 Hermes 类型。
- 设计方法：Hermes-only 只读选择卡片，不新增 runtime 类型。
- 实现方法：修改 `agents_page.dart` 和 `agents_page_layout_test.dart`。
- 路径：`awiki-me-ui/lib/src/presentation/agents/agents_page.dart`、`awiki-me-ui/tests/unit_test/agents/agents_page_layout_test.dart`。
- 验证方式：Agent page widget tests + analyze。
- Review 环节：检查是否误导用户可选择其他类型。
- Commit 要求：用户已要求统一提交、推送并合并到 `release/0526`。
- 风险：未来新增类型时需扩展枚举 / payload。

### Step 02：会话信息默认关闭与用户 / 智能体信息弹窗

- 小 Plan：[steps/02-conversation-info-peer-popup.md](steps/02-conversation-info-peer-popup.md)
- 目标：直聊信息默认关闭，资料能力迁移到弹窗。
- 设计方法：workspace 控侧栏，chat 控资料弹窗；群聊保持侧栏。
- 实现方法：修改 `conversation_workspace_page.dart`、`chat_page.dart` 与测试。
- 路径：`awiki-me-ui/lib/src/presentation/conversation_list/conversation_workspace_page.dart`、`awiki-me-ui/lib/src/presentation/chat/chat_page.dart`。
- 验证方式：conversation / chat widget tests + app smoke。
- Review 环节：检查默认关闭、弹窗内容、群聊回归。
- Commit 要求：用户已要求统一提交、推送并合并到 `release/0526`。
- 风险：弹窗内容继续增长可能需后续 tab 化。

### Step 03：Agent 收件箱增强

- 小 Plan：[steps/03-agent-inbox-enhancement.md](steps/03-agent-inbox-enhancement.md)
- 目标：时间、最新预览、limit=20、分页和可复制。
- 设计方法：统一 page size，provider 负责排序 / 去重 / cursor。
- 实现方法：修改 `agent_inbox_provider.dart`、`agent_inbox_panel.dart`、默认 command/service 值和 tests。
- 路径：`awiki-me-ui/lib/src/presentation/agents/agent_inbox_provider.dart`、`awiki-me-ui/lib/src/presentation/agents/agent_inbox_panel.dart`。
- 验证方式：agent inbox provider tests + integration smoke 入口。
- Review 环节：检查排序、分页不丢消息。
- Commit 要求：用户已要求统一提交、推送并合并到 `release/0526`。
- 风险：旧 daemon 缺失时间字段时仅隐藏时间。

### Step 04：登录页图片和 UI 对齐

- 小 Plan：[steps/04-onboarding-ui.md](steps/04-onboarding-ui.md)
- 目标：完善 logo、hero 和文案。
- 设计方法：复用现有 logo asset，不改登录逻辑。
- 实现方法：修改 `onboarding_page.dart` 和 tests。
- 路径：`awiki-me-ui/lib/src/presentation/onboarding/onboarding_page.dart`。
- 验证方式：onboarding widget tests + app smoke。
- Review 环节：检查文案和 fallback。
- Commit 要求：用户已要求统一提交、推送并合并到 `release/0526`。
- 风险：像素级设计验收需后续截图。

### Step 05：附件本机应用打开

- 小 Plan：[steps/05-native-attachment-open.md](steps/05-native-attachment-open.md)
- 目标：附件查看调用本机应用。
- 设计方法：`url_launcher` external application；路径转 file URI。
- 实现方法：修改 `chat_page.dart`，新增 fake url launcher test。
- 路径：`awiki-me-ui/lib/src/presentation/chat/chat_page.dart`、`awiki-me-ui/tests/unit_test/chat_page_test.dart`。
- 验证方式：chat widget test 覆盖下载保存后打开。
- Review 环节：检查失败提示和保存行为不丢失。
- Commit 要求：用户已要求统一提交、推送并合并到 `release/0526`。
- 风险：真实平台 handler 缺失时仍会提示错误。

### Step 06：E2E / 集成验证与文档

- 小 Plan：[steps/06-integration-docs-review.md](steps/06-integration-docs-review.md)
- 目标：补齐 fake-bootstrap integration smoke、screenshot smoke、docs 和最终审计。
- 设计方法：以 app smoke 验证 AppShell 关键 UI 流程，以 screenshot smoke 固化视觉证据。
- 实现方法：修改 `app_smoke_test.dart`、新增 `ui_visual_verification_test.dart`、更新 `docs/testing.md` 与 Plan 文档。
- 路径：`awiki-me-ui/tests/integration_test/app/app_smoke_test.dart`、`awiki-me-ui/tests/integration_test/app/ui_visual_verification_test.dart`、`awiki-me-ui/integration_test/ui_visual_verification_test.dart`、`awiki-me-ui/docs/testing.md`。
- 验证方式：analyze、focused unit、macOS app smoke、macOS screenshot smoke、diff check。
- Review 环节：检查是否覆盖用户目标所有入口。
- Commit 要求：用户已要求统一提交、推送并合并到 `release/0526`。
- 风险：fake smoke 不验证真实 daemon payload。

## 10. Review 策略

- 每步骤 Review：实现完成后检查需求覆盖、回归、测试和文档。
- 全局 Review：检查 Step 01-06 是否与用户需求一一对应，且没有破坏群聊信息、移动端 Agent 收件箱和附件保存行为。
- 契约 / 安全 / 隐私 Review：不新增服务端协议，不暴露 secret；DID copy 只复制公开 DID；附件打开仅使用本地路径或已保存文件 URI。
- 文档 Review：`docs/testing.md` 与本计划必须记录实际验证命令和剩余风险。

## 11. 验证策略

| 层级 | 命令 / 检查 | 预期证据 |
|---|---|---|
| Analyze | `cd awiki-me-ui && flutter analyze lib/src/presentation/chat/chat_page.dart lib/src/presentation/conversation_list/conversation_workspace_page.dart lib/src/presentation/agents/agents_page.dart lib/src/presentation/agents/agent_inbox_provider.dart lib/src/presentation/agents/agent_inbox_panel.dart lib/src/application/agent/agent_control_service.dart lib/src/domain/entities/agent/agent_command.dart lib/src/presentation/onboarding/onboarding_page.dart tests/unit_test/chat_page_test.dart tests/unit_test/conversation_workspace_test.dart tests/unit_test/agents/agent_inbox_provider_test.dart tests/unit_test/agents/agents_page_layout_test.dart tests/unit_test/agents/agent_control_payload_test.dart tests/unit_test/agents/agent_control_service_test.dart tests/unit_test/test_support.dart tests/integration_test/app/app_smoke_test.dart` | No issues found |
| Unit / Widget | `cd awiki-me-ui && flutter test tests/unit_test/agents/agent_inbox_provider_test.dart tests/unit_test/agents/agents_page_layout_test.dart tests/unit_test/agents/agent_control_payload_test.dart tests/unit_test/agents/agent_control_service_test.dart tests/unit_test/conversation_workspace_test.dart tests/unit_test/chat_page_test.dart tests/unit_test/onboarding_page_test.dart` | 151 tests passed |
| Integration smoke | `cd awiki-me-ui && LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 flutter test integration_test/app_smoke_test.dart -d macos` | 4 tests passed |
| Screenshot visual smoke | `cd awiki-me-ui && LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 flutter test integration_test/ui_visual_verification_test.dart -d macos` | 1 test passed；生成 `awiki-me-ui/docs/ui-optimization-plan/screenshots/01-onboarding-login.png` 到 `awiki-me-ui/docs/ui-optimization-plan/screenshots/07-agent-create-agent-type.png` |
| Docs / whitespace | `cd awiki-me-ui && git diff --check` | 通过 |

## 12. 文档更新

- Harness 文档：无全局 Harness 变更。
- 子仓库文档：`awiki-me-ui/docs/testing.md` 已记录 focused UI optimization checks、macOS UTF-8 integration 命令与 screenshot smoke 命令。
- 本次生成的任务文档：`awiki-me-ui/docs/ui-optimization-plan/plan.md`、`awiki-me-ui/docs/ui-optimization-plan/steps/*.md` 与 `awiki-me-ui/docs/ui-optimization-plan/screenshots/*.png`。

## 13. Commit 计划

- 用户已要求对本轮修改统一执行提交、推送，并合并到 `release/0526`。
- 本轮采用一个集成 commit，建议消息：`feat(app): optimize chat and agent ui flows`。
- Commit 前已再次运行第 11 节中的关键验证命令：focused analyze、macOS screenshot smoke、`git diff --check`。

## 14. Blocked 处理

| Blocker | Step | 证据 | 已尝试方案 | 影响范围 | 下一步决策 |
|---|---|---|---|---|---|
| CocoaPods 在非 UTF-8 shell 下失败 | 06 | `Encoding::CompatibilityError` / `ASCII-8BIT` | 设置 `LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8` 后 integration smoke 通过 | macOS integration 命令环境 | 已在 `docs/testing.md` 记录 UTF-8 命令 |

- 只有依赖允许且风险已记录时，才继续另一个 pending 步骤。
- 当前没有阻断项。

## 15. Plan 变更记录

| 日期 | 变更 | 原因 | 影响步骤 | 是否需要 Review |
|---|---|---|---|---|
| 2026-06-14 | 创建主 Plan | 用户要求使用 `$awiki-plan` 制定计划并实现 UI 优化 | 全部 | 是 |
| 2026-06-15 | 补齐 Step 小 Plan 文档、integration smoke 和最终证据 | 恢复执行时发现主 Plan 缺小 Plan，且需要更强 E2E 证据 | 全部 | 是 |
| 2026-06-15 | 新增附件本机打开专项 widget test | 完成审计发现 native open 路径需直接验证 | Step 05 | 是 |
| 2026-06-15 | 记录 macOS integration UTF-8 locale 要求 | 首次运行 app smoke 因 CocoaPods 编码失败，设置 UTF-8 后通过 | Step 06 | 否 |
| 2026-06-15 | 新增 macOS screenshot visual smoke 与截图证据 | 用户要求启动 App 后从 UI / 视觉层面验证本轮修改 | Step 06 | 是 |
| 2026-06-15 | 用户确认提交、推送并合并到 `release/0526` | 用户明确要求“修改的仓库全部操作” | 全部 | 是 |

## 16. 风险与回滚

| 风险 | 缓解措施 | 回滚 / 回退方案 |
|---|---|---|
| 资料弹窗内容过多导致高度不足 | 使用最大高度、滚动和内嵌 Agent 收件箱高度限制 | 恢复右侧身份卡面板或拆为 tab |
| Agent 收件箱真实 payload 缺时间字段 | 时间字段为空时隐藏时间标签，保留 preview | 回滚时间展示，不影响分页 |
| fake integration / screenshot smoke 不等于真实 daemon E2E | provider / widget tests 覆盖 control payload，fake smoke 覆盖 UI 流程和视觉状态 | 后续补真实 daemon E2E |
| 附件本机打开依赖平台 handler | 失败时显示错误，不破坏保存流程 | 移除 launch 调用，仅保留保存文件 |
| 已要求统一提交 | 文档记录本次提交/推送/合并操作 | 如需回滚，可 revert merge 或 revert feature commit |

## 17. 最终全局 Review 与整体验证

- 触发条件：所有步骤实现、Review、测试和文档更新后执行。
- Review 范围：`awiki-me-ui` 代码、tests、`docs/testing.md`、本 Plan / Step 文档、工作区状态。
- 重点关注：用户 7 条显式需求是否均有证据；跨步骤是否冲突；群聊信息和移动端行为是否回归；附件本机打开是否有直接测试；文档是否记录可复现命令。
- 整体验证命令 / 检查：
  - `cd awiki-me-ui && flutter analyze ...`：No issues found。
  - `cd awiki-me-ui && flutter test tests/unit_test/agents/agent_inbox_provider_test.dart tests/unit_test/agents/agents_page_layout_test.dart tests/unit_test/agents/agent_control_payload_test.dart tests/unit_test/agents/agent_control_service_test.dart tests/unit_test/conversation_workspace_test.dart tests/unit_test/chat_page_test.dart tests/unit_test/onboarding_page_test.dart`：151 tests passed。
  - `cd awiki-me-ui && LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 flutter test integration_test/app_smoke_test.dart -d macos`：4 tests passed。
  - `cd awiki-me-ui && LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 flutter test integration_test/ui_visual_verification_test.dart -d macos`：1 test passed；生成 7 张 UI 截图。
  - `cd awiki-me-ui && git diff --check`：通过。
- 截图人工核验：
  - `awiki-me-ui/docs/ui-optimization-plan/screenshots/01-onboarding-login.png`：登录页 logo / hero / 表单布局正常，文案为 `Based on awiki.info`。
  - `awiki-me-ui/docs/ui-optimization-plan/screenshots/02-chat-default-info-closed.png`：会话打开后右侧会话信息默认关闭；附件卡展示眼睛图标查看入口。
  - `awiki-me-ui/docs/ui-optimization-plan/screenshots/03-chat-info-side-panel.png`：用户主动点击后会话信息侧栏正常展开。
  - `awiki-me-ui/docs/ui-optimization-plan/screenshots/04-agent-info-popup.png`：智能体信息弹窗展示 DID copy、Runtime Agent pill、身份卡、关注和 Agent 收件箱入口。
  - `awiki-me-ui/docs/ui-optimization-plan/screenshots/05-agent-inbox-list.png`：Agent 收件箱列表展示时间、未读数、`最新：`预览和加载更多会话。
  - `awiki-me-ui/docs/ui-optimization-plan/screenshots/06-agent-inbox-thread.png`：线程视图展示消息时间、加载更早消息和可读消息气泡。
  - `awiki-me-ui/docs/ui-optimization-plan/screenshots/07-agent-create-agent-type.png`：创建 Agent 弹窗展示 Hermes-only Agent 类型选择卡片。
- Review 发现：
  1. integration smoke 首次未设置 UTF-8 locale 时 CocoaPods 失败；已通过 UTF-8 命令验证并记录文档。
  2. 原 app smoke 的 profile/settings 导航在 macOS rail 下 finder 不够稳；已改为 key / semantics / text 多候选点击。
  3. 附件本机打开路径初始缺专项测试；已新增 fake `UrlLauncherPlatform` test。
  4. 计划文档初版没有小 Plan；已补齐 `steps/*.md`。
  5. 首次截图 smoke 中从弹窗内 Agent 收件箱列表直接 tap 未命中 offscreen row；已在测试中先 `ensureVisible`，重跑通过。
- 已修复问题：见第 15 节与各 Step Review。
- 剩余风险：截图 smoke 使用 fake bootstrap / Flutter render capture，不验证真实 daemon inbox payload，也不等同于真实后端多客户端 E2E；macOS runner 仍打印 `Failed to foreground app; open returned 1`，但测试窗口已构建并通过 render tree 截图。
- 最终证据：analyze、focused unit、macOS integration smoke、macOS screenshot visual smoke、diff check 均通过。
- 最终 `git status`：提交前存在本轮代码 / 测试 / 文档修改与新增 `docs/ui-optimization-plan/`；用户已要求本轮继续提交、推送并合并。
- 如果本阶段修改文件：已经完成 Review 与验证；本轮按用户要求统一提交并合并。
