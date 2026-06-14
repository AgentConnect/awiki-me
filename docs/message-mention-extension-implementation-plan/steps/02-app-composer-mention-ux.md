# Step 02：App composer 候选与 draft range

主 Plan：[../plan.md](../plan.md)
Step index：02
状态：draft

## 1. 执行状态

| 字段 | 值 |
|---|---|
| Status | pending |
| Branch | 待定 |
| Started | 待执行 |
| Completed | 待执行 |
| Commit | 待记录 |
| Review evidence | 待记录 |
| Verification evidence | 待记录 |
| Next action | 实现群聊 `@` 候选列表与 draft mention 状态 |

状态取值：`pending`、`in_progress`、`review`、`blocked`、`committed`、`done`。

## 2. 目标

- 结果：用户在 `awiki-me` 群聊 composer 输入 `@` 后，可以选择所有人、所有 agents、所有人类用户或单个成员。
- 用户 / 系统可见行为：候选列表类似微信 / 飞书，选择后插入 mention surface 并维护 draft range。
- 非目标：不在私聊启用 P9 mention；不在 UI 层生成 proof；不逐项远程拉 profile。
- 完成标准：
  - 群聊输入 `@` 弹出候选；私聊不弹。
  - 候选搜索支持 displayName / handle / DID。
  - 编辑 mention surface 会让对应 draft mention 失效。
  - 发送前能输出 P9 range 所需 code point offset。

## 3. 设计方法

- 设计边界：`awiki-me` 负责 UI、draft 和候选体验；协议 validator / DTO 复用 Step 01 的 SDK 能力。
- 核心决策：selector 候选固定置顶；单人候选只使用 active 群成员；unknown subjectType 不静默归类。
- 契约 / API / 数据流：
  - Composer `TextEditingController` → mention trigger detector → `MentionCandidateProvider` → overlay 选择 → `MentionDraft`。
  - `MentionDraft` 发送时转成 P9 `mentions`。
- 兼容性：普通文本 draft 逻辑保持；attachment caption 暂不支持 mention，避免 caption / attachment manifest 混合复杂化。
- 迁移策略：新增 provider / model，不改旧 conversation 数据。
- 风险控制：避免 N+1 profile 请求；避免 IME composing 误触；严格维护 range。

## 4. 实现方法

1. 新增 App 侧 mention draft model，例如 `ChatMentionDraft`、`MentionTargetDraft`、`MentionCandidate`。
2. 扩展 `ChatComposerDraft` 保存 `mentions`，并在 `ChatComposerDraftsController` 中随 text 一起维护。
3. 在 `_ComposerTextField` 或上层 `_ComposerState` 监听 selection / text，识别 active `@query`。
4. 新增候选 provider：固定 selector + `GroupApplicationService.listMembers` + profile cache projection。
5. 新增 overlay：定位在 composer 上方或 caret 附近；支持键盘上下 / Enter、鼠标点击、移动端点击。
6. 选择候选后替换 active range，插入 trailing space，保存 draft mention。
7. 实现 draft range 更新：前置编辑平移、内部编辑删除、发送前重算 code point offsets。

## 5. 路径

| 仓库 / 模块 / 文件 | 计划变更 | 备注 |
|---|---|---|
| `awiki-me/lib/src/domain/entities/` | 新增 mention draft / target / candidate 实体 | App UI 模型，不等同 SDK DTO。 |
| `awiki-me/lib/src/presentation/chat/chat_provider.dart` | 扩展 `ChatComposerDraft` 和 draft controller | 保持普通文本兼容。 |
| `awiki-me/lib/src/presentation/chat/chat_page.dart` | 增加 trigger detector、overlay、选择插入逻辑 | 注意 IME composing。 |
| `awiki-me/lib/src/application/group_application_service.dart` | 如需要，补候选数据聚合方法 | 不逐项远程请求。 |
| `awiki-me/lib/src/domain/entities/group_member_summary.dart` | 补 display/profile/subjectType/status 字段 | 不能从 role 推断 human/agent。 |
| `awiki-me/tests/unit_test/` | 新增 provider / widget tests | 覆盖 range 与 UI。 |

## 6. 依赖

- 前置步骤：Step 01 的 DTO / range 规则决策。
- 外部文档或决策：P9 range 单位为 `unicode_code_point`。
- 环境前提：Flutter widget test 环境可用。

## 7. 验收标准

- [ ] 群聊 composer 输入 `@` 出现四类候选。
- [ ] 选择 selector 后 payload target 可映射到 `all/agents/humans`。
- [ ] 选择单人候选后 target kind 与 DID 来自 profile / roster，不用 displayName 做身份。
- [ ] 中文、emoji、多行文本中的 range 计算正确。
- [ ] IME composing 时不误发 / 不误弹。
- [ ] Review 发现已经修复或明确记录。
- [ ] 本步骤在进入下一步之前已经创建聚焦 commit。

## 8. 验证方式

| 检查项 | 命令 / 方法 | 预期证据 |
|---|---|---|
| Unit | `cd awiki-me && flutter test tests/unit_test --name mention` | trigger、candidate、range 更新测试通过。 |
| Widget | `cd awiki-me && flutter test tests/unit_test --name "chat mention"` | overlay 展示、选择、插入测试通过。 |
| Analyze | `cd awiki-me && dart analyze` | 无静态分析问题。 |
| Manual | macOS / mobile 手动输入中文 `@` | IME、键盘选择、触摸选择体验正常。 |

如果某个命令不能运行，必须记录原因、影响和替代证据。

## 9. Review 环节

- Review 时机：本步骤代码实现完成后、commit 前。
- Review 重点：UI 体验、IME、Unicode range、候选数据源、unknown subjectType 策略、无 N+1 请求。
- Review 结论必须在 commit 前记录；必须修复必要问题，或明确记录剩余风险。

| Review 项 | 结果 | 备注 |
|---|---|---|
| 发现问题 | 待执行 |  |
| 已修复问题 | 待执行 |  |
| 剩余风险 | 待执行 |  |
| 新增或缺失测试 | 待执行 |  |
| 已更新或缺失文档 | 待执行 |  |

## 10. Commit 要求

- Commit 时机：本步骤实现、验证、Review 都完成后。
- Commit 范围：App composer UI / draft / candidate / tests。
- Commit 前状态：记录 `git status`。
- 纳入文件：记录本步骤 commit 包含的文件。
- Commit 后证据：记录 commit hash 和 commit 后 `git status`。
- 建议消息：`feat(app): add group mention composer UX`

## 11. Blocked 处理

| Blocker | 证据 | 已尝试方案 | 影响范围 | 下一步决策 |
|---|---|---|---|---|
| group member 缺少 subjectType | 候选无法区分 human / agent | 读取 profile cache / 补 SDK projection | 单人候选、selector count | 禁用 unknown 单人候选或阻塞 Step 02。 |
| overlay 定位在移动端不稳定 | widget/manual 失败 | 使用 composer 上方固定 panel | App UX | 保持固定 panel MVP。 |

## 12. Plan 变更记录

| 日期 | 变更 | 原因 | 主 Plan 变更记录链接 |
|---|---|---|---|
| 2026-06-14 | 创建 Step 02 | 初始设计 | `../plan.md#16-plan-变更记录` |

## 13. 风险、回滚与后续文档

- 风险：候选体验复杂度高，可能影响 composer 稳定性。
- 回滚 / 回退：保留 draft model，先隐藏 overlay feature flag；普通发送不受影响。
- 后续文档：在 `awiki-me/docs/testing.md` 增加 mention composer 测试说明。
