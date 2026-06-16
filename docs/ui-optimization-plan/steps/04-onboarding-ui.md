# Step 04：登录页图片和 UI 对齐

主 Plan：[../plan.md](../plan.md)
Step index：04
状态：done

## 1. 执行状态

| 字段 | 值 |
|---|---|
| Status | done |
| Branch | `awiki-me-ui:feature/release-0526/ui-optimization` |
| Started | 2026-06-14 |
| Completed | 2026-06-15 |
| Commit | 用户已要求统一提交、推送并合并到 `release/0526`；不再按 Step 拆分提交 |
| Review evidence | Review 确认移动 / 窄布局 logo 卡片、macOS hero 使用真实 logo，英文文案修正 |
| Verification evidence | `flutter test tests/unit/onboarding_page_test.dart` 已通过；integration app smoke 启动 onboarding 通过 |
| Next action | 无 |

## 2. 目标

- 结果：登录页视觉对齐更接近产品 UI。
- 用户 / 系统可见行为：窄布局 logo 在白色圆角卡片中显示，macOS hero 中心使用真实 `awiki-me-logo.png`，文案为 `Based on awiki.info`。
- 非目标：不改登录 / 注册业务流程。
- 完成标准：logo 和文案有 widget / integration smoke 覆盖。

## 3. 设计方法

- 设计边界：只调整 `onboarding_page.dart` UI。
- 核心决策：复用现有 logo asset，不新增资源。
- 契约 / API / 数据流：不改变 onboarding service 或表单字段。
- 兼容性：logo 加载失败时仍有 fallback 文本。
- 风险控制：控制顶部 spacing，避免窄屏溢出。

## 4. 实现方法

1. 调整窄布局 logo 容器与 spacing。
2. macOS orbit 中心改为 `Image.asset('assets/images/awiki-me-logo.png')`。
3. 修正文案 `Base on awiki.info`。
4. 更新 onboarding widget test。

## 5. 路径

| 仓库 / 模块 / 文件 | 计划变更 | 备注 |
|---|---|---|
| `awiki-me-ui/lib/src/presentation/onboarding/onboarding_page.dart` | logo / hero / 文案调整 | UI |
| `awiki-me-ui/tests/unit/onboarding_page_test.dart` | 登录页回归测试 | Widget |
| `awiki-me-ui/tests/e2e/flutter/app/app_smoke_test.dart` | 启动 onboarding smoke | Integration |

## 6. 依赖

- 前置步骤：无。
- 外部文档或决策：用户要求“完善图片，对齐 UI”。
- 环境前提：Flutter asset bundle 可用。

## 7. 验收标准

- [x] 窄布局 logo 展示在统一卡片中。
- [x] macOS hero 使用真实 logo，不回退为 `AW`。
- [x] 文案修正为 `Based on awiki.info`。
- [x] Review 发现已经修复或明确记录。
- [x] 本步骤纳入统一集成提交；用户已要求推送并合并到 `release/0526`。

## 8. 验证方式

| 检查项 | 命令 / 方法 | 预期证据 |
|---|---|---|
| Widget | `cd awiki-me-ui && flutter test tests/unit/onboarding_page_test.dart` | Onboarding tests 通过 |
| Integration | `cd awiki-me-ui && LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 flutter test integration_test/app_smoke_test.dart -d macos` | onboarding smoke 通过 |
| Analyze | `cd awiki-me-ui && flutter analyze ... onboarding_page.dart ...` | No issues found |

## 9. Review 环节

| Review 项 | 结果 | 备注 |
|---|---|---|
| 发现问题 | 无阻断 | 文案拼写已修正 |
| 已修复问题 | logo 统一与顶部留白收敛 | 已补测试 |
| 剩余风险 | 具体像素仍需设计验收 | 当前自动测试覆盖结构 |
| 新增或缺失测试 | 已更新 onboarding test / app smoke | 无缺失 |
| 已更新或缺失文档 | 已更新 `docs/testing.md` | 无缺失 |

## 10. Commit 要求

- Commit 时机：用户已确认，纳入统一集成提交。
- Commit 范围：onboarding UI、测试与文档。
- 建议消息：`fix(app): align onboarding logo layout`

## 11. Blocked 处理

| Blocker | 证据 | 已尝试方案 | 影响范围 | 下一步决策 |
|---|---|---|---|---|
| 无 | - | - | - | - |

## 12. Plan 变更记录

| 日期 | 变更 | 原因 | 主 Plan 变更记录链接 |
|---|---|---|---|
| 2026-06-15 | 回填实现证据 | 恢复执行后完成审计 | `../plan.md#15-plan-变更记录` |

## 13. 风险、回滚与后续文档

- 风险：设计稿若变更，当前 spacing 需再调。
- 回滚 / 回退：恢复旧 onboarding 布局。
- 后续文档：无。
