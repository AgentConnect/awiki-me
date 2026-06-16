# Step 05：附件本机应用打开

主 Plan：[../plan.md](../plan.md)
Step index：05
状态：done

## 1. 执行状态

| 字段 | 值 |
|---|---|
| Status | done |
| Branch | `awiki-me-ui:feature/release-0526/ui-optimization` |
| Started | 2026-06-14 |
| Completed | 2026-06-15 |
| Commit | 用户已要求统一提交、推送并合并到 `release/0526`；不再按 Step 拆分提交 |
| Review evidence | Review 确认附件按钮语义改为查看，localPath 直接打开，否则下载保存后用 external application 打开 |
| Verification evidence | `flutter test tests/unit/chat_page_test.dart` 已通过，包含“查看附件会下载保存后用本机应用打开文件” |
| Next action | 无 |

## 2. 目标

- 结果：聊天中附件文件可调用本机应用查看。
- 用户 / 系统可见行为：附件按钮显示“查看附件”；已有本地路径直接打开，否则下载保存后打开。
- 非目标：不改附件消息协议，不新增平台 runner 能力。
- 完成标准：native open 路径可被测试验证，失败仍通过 UI feedback 提示。

## 3. 设计方法

- 设计边界：只改 `ChatView` 附件动作。
- 核心决策：使用 `url_launcher` 的 `LaunchMode.externalApplication`。
- 契约 / API / 数据流：继续复用 `MessagingService.downloadAttachment` 与 `AttachmentPickerService.saveAttachment`。
- 兼容性：支持已有 scheme URI；普通路径转 `Uri.file`。
- 风险控制：无法打开时抛出错误并显示 toast，不吞掉失败。

## 4. 实现方法

1. 将附件按钮文案 / tooltip / icon 改为查看语义。
2. `_openAttachment` 优先使用 `message.attachment.localPath`。
3. 无 localPath 时下载 bytes，保存后调用 `_launchNativeAttachment`。
4. `_attachmentUri` 兼容已有 scheme 和本地文件路径。
5. 在 chat widget test 中 fake `UrlLauncherPlatform` 验证 external application mode。

## 5. 路径

| 仓库 / 模块 / 文件 | 计划变更 | 备注 |
|---|---|---|
| `awiki-me-ui/lib/src/presentation/chat/chat_page.dart` | 附件查看 / native open | UI |
| `awiki-me-ui/tests/unit/chat_page_test.dart` | fake url launcher 验证本机打开 | Widget test |
| `awiki-me-ui/tests/unit/test_support.dart` | attachment picker fake 已支持保存记录 | Test support |

## 6. 依赖

- 前置步骤：无。
- 外部文档或决策：用户要求“调用本机应用程序浏览文件”。
- 环境前提：平台存在 URL/file handler；测试中使用 fake launcher。

## 7. 验收标准

- [x] 按钮语义为“查看附件”。
- [x] localPath 可直接打开。
- [x] 无 localPath 时下载、保存、打开。
- [x] 使用 external application mode。
- [x] 打开失败有错误提示路径。
- [x] Review 发现已经修复或明确记录。
- [x] 本步骤纳入统一集成提交；用户已要求推送并合并到 `release/0526`。

## 8. 验证方式

| 检查项 | 命令 / 方法 | 预期证据 |
|---|---|---|
| Widget | `cd awiki-me-ui && flutter test tests/unit/chat_page_test.dart` | native attachment open 测试通过 |
| Analyze | `cd awiki-me-ui && flutter analyze ... chat_page.dart chat_page_test.dart ...` | No issues found |
| Integration | `cd awiki-me-ui && LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 flutter test integration_test/app_smoke_test.dart -d macos` | app smoke 不回归 |

## 9. Review 环节

| Review 项 | 结果 | 备注 |
|---|---|---|
| 发现问题 | 初始缺少 native open 专项测试 | 已新增 fake launcher 测试 |
| 已修复问题 | 文档补充 native attachment open path | 已更新 |
| 剩余风险 | 真机上 handler 不存在时会提示错误 | 可接受 |
| 新增或缺失测试 | 已新增 `查看附件会下载保存后用本机应用打开文件` | 无缺失 |
| 已更新或缺失文档 | 已更新 `docs/testing.md` | 无缺失 |

## 10. Commit 要求

- Commit 时机：用户已确认，纳入统一集成提交。
- Commit 范围：附件查看代码、测试与文档。
- 建议消息：`feat(app): open chat attachments with native apps`

## 11. Blocked 处理

| Blocker | 证据 | 已尝试方案 | 影响范围 | 下一步决策 |
|---|---|---|---|---|
| 无 | - | - | - | - |

## 12. Plan 变更记录

| 日期 | 变更 | 原因 | 主 Plan 变更记录链接 |
|---|---|---|---|
| 2026-06-15 | 补充 native open 测试要求 | 完成审计发现需直接验证本机打开调用 | `../plan.md#15-plan-变更记录` |

## 13. 风险、回滚与后续文档

- 风险：macOS sandbox / Windows file URI handler 差异。
- 回滚 / 回退：保留保存文件，移除 launch 调用。
- 后续文档：如增加平台权限配置，需同步平台文档。
