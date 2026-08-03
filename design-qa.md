# AWiki Me 核心七屏视觉验收

## 验收范围

- 设计基准：Ardot 页面 `AWiki Me Android · Quiet List v2`（节点 `17:1`）
- 实现视口：Flutter compact `393 × 852`，像素密度 `1.0`
- 真机：P0110，物理截图 `1264 × 2800`
- 页面：登录/注册、消息、会话详情、智能体、联系人、我、设置
- 对照方式：每页将设计基准与实现截图归一到 `393 × 852`，同屏逐项比较；聊天气泡、个人页内容和设置行另做局部放大检查

## 证据

### 设计基准

- `/Users/howard/ANP-Workspace/awiki-me-ui-design-draft/ardot-qa/quiet-list-v2/709816693934731/screenshot-17_18-20260801_085005870.png`
- `/Users/howard/ANP-Workspace/awiki-me-ui-design-draft/ardot-qa/quiet-list-v2/709816693934731/screenshot-17_59-20260801_085005871.png`
- `/Users/howard/ANP-Workspace/awiki-me-ui-design-draft/ardot-qa/quiet-list-v2/709816693934731/screenshot-17_114-20260801_085005871.png`
- `/Users/howard/ANP-Workspace/awiki-me-ui-design-draft/ardot-qa/quiet-list-v2/709816693934731/screenshot-17_174-20260801_085005871.png`
- `/Users/howard/ANP-Workspace/awiki-me-ui-design-draft/ardot-qa/quiet-list-v2/709816693934731/screenshot-17_213-20260801_085005871.png`
- `/Users/howard/ANP-Workspace/awiki-me-ui-design-draft/ardot-qa/quiet-list-v2/709816693934731/screenshot-17_282-20260801_085005871.png`
- `/Users/howard/ANP-Workspace/awiki-me-ui-design-draft/ardot-qa/quiet-list-v2/709816693934731/screenshot-17_345-20260801_085005871.png`

### Flutter 实现截图

- `docs/ui-optimization-plan/screenshots/01-compact-onboarding.png`
- `docs/ui-optimization-plan/screenshots/03-compact-messages.png`
- `docs/ui-optimization-plan/screenshots/04-compact-chat.png`
- `docs/ui-optimization-plan/screenshots/06-compact-agents-list.png`
- `docs/ui-optimization-plan/screenshots/09-compact-contacts.png`
- `docs/ui-optimization-plan/screenshots/10-compact-profile.png`
- `docs/ui-optimization-plan/screenshots/11-compact-settings.png`

### 同屏与局部对照

- `.design-references/comparisons/compare-01-onboarding.png` 至 `.design-references/comparisons/compare-07-settings.png`
- `.design-references/comparisons/focus-03-chat-bubbles.png`
- `.design-references/comparisons/focus-06-profile-content.png`
- `.design-references/comparisons/focus-07-settings-rows.png`

### P0110 真机

- `.design-references/p0110-messages.png`
- `.design-references/p0110-chat-stable.png`
- `.design-references/p0110-agents-stable.png`
- `.design-references/p0110-contacts-stable.png`
- `.design-references/p0110-profile-final.png`
- `.design-references/p0110-settings-stable.png`

## 问题闭环

| 等级 | 初检问题 | 处理结果 |
| --- | --- | --- |
| P2 | 会话气泡尾部存在明显竖边，右侧消息缺少用户头像 | 改为曲线填充尾部并遮蔽接缝，双方头像均显示；局部与真机复核通过 |
| P2 | 个人页身份详情占据首屏，窄屏编辑按钮产生异常纵向空白 | 移动端默认收起详情，并调整窄屏尾随控件阈值；P0110 复核通过 |
| P2 | 设置页危险操作过早进入首屏，语言值垂直未对齐 | 危险操作移至下方保留功能，语言值与箭头居中；P0110 复核通过 |
| P2 | 登录页品牌、标题和主按钮与基准层级偏差较大 | 使用仓库正式 Logo，收敛标题与满宽主按钮；视觉快照通过 |

## 最终检查

- 信息层级：通过。七屏保持白色平面、蓝色品牌强调与统一留白。
- 导航：通过。底部固定为“消息、联系人、智能体、我”，选中态使用蓝色图标、文字和底部指示条。
- 状态表达：通过。未读数使用红色角标；空状态与列表状态均保留。
- 聊天：通过。双方头像、左右气泡、曲线尾部、输入区和附件能力均保留。
- 可用性：通过。联系人搜索/进入会话/关注、身份卡、设置入口、语言与设备等原有操作路径仍可用。
- 回归：`flutter analyze` 无问题；核心相关测试 `256/256` 通过；视觉快照 `7/7` 通过。
- 真机：最新 `.dev` 构建已安装并冷启动，六个登录后核心页面完成实际设备复核；未清除现有数据，正式包未改动。

## 可接受差异

- 登录页保留真实产品现有 Handle 输入和服务端配置支持的登录方式，没有照抄纯展示稿中的本地身份卡与第三种认证方式。
- 会话数量、联系人、Handle、DID、版本号等来自真机实时数据，与静态设计稿占位内容不同。
- 差异属于功能合同或动态数据，不构成视觉阻塞；未发现剩余 P0、P1 或 P2 问题。

final result: passed

---

## Ardot 设计目标全量状态对齐（2026-08-03）

> 本轮以 Ardot `AWiki Me · Core Seven UI · PR Review` 页面为索引，逐张核对当前 Flutter 实现、已提交视觉基线、P0110 既有证据与可安全复查的真机状态；只在证据能够闭环时把画面标为“当前 APP”。未使用 Superpowers 技能。

### 状态结果

- 24 张画面最终收敛为：22 张“当前 APP”、2 张“设计目标”、0 张“历史版本”。可证实已落地的 01、05、10、11、12、16、17、18、19、20 已同步为“当前 APP”，并同时更新画面 Frame 名称。
- 16“智能体详情”最初误标为历史版本；Ardot 画面、已提交 `20-compact-agent-peer-info.png`、当前 `chat_peer_info_part.dart` 与 P0110 证据显示它仍是当前紧凑智能体信息页，因此已纠正为“当前 APP”。
- 06“聊天信息”与 24“删除会话确认”保持“设计目标”。06 目标稿包含“清空聊天记录”，24 目标稿要求可勾选“同时清空历史消息”；当前 APP 只能把会话移出最近列表，不能永久清空单会话历史。
- 标签文字、标签颜色、画面命名、分区截图与布局结构均已复查。布局扫描只报告背景/控件、头像/文字和多状态叠层等预期覆盖关系，没有发现本轮标签更新造成的裁切、错位或溢出。

### 代码与能力边界

- 候选代码由 `6cd5c51` 与 `8373bcb` 两笔提交组成；后者已收口消息列表左滑删除、紧凑确认框、禁用的历史清理勾选项及对应测试/文档。
- 组合回归覆盖开屏、会话详情、联系人、个人页与会话工作区，共 `207/207` 通过；`flutter analyze` 为 `No issues found`；`git diff --check` 通过。
- Core/SDK 当前没有按 canonical conversationId 永久清空单会话历史的公开契约，也没有防止重启、同步或回填重新恢复旧消息的 clear watermark/tombstone。UI 层没有伪造成功状态，也没有把 `clearConversationSnapshot()` 误当作消息清理能力。

### P0110 与独立复审

- 本轮 P0110 安全复查覆盖消息列表、会话详情、三点入口和聊天信息页；两项偏好开关在验证后恢复原值，未执行删除，未清除 APP 数据，未出现白屏、崩溃或视觉 P0。
- 联系人四 Tab、群组返回路径、我页三个互斥展开态、开屏与资料页继续使用本文前述同一候选版本的已记录 P0110 截图/XML 与通过结论；本轮没有再次执行会改变业务数据的关注、发送或删除操作。
- 独立设计复审在纠正 16 与 06 的分类后给出 `PASS`，剩余 `P0/P1/P2 = 0/0/0`。

### UNVERIFIED

- 06/24 所描述的真实永久清理、重启持久性、同步防复活和失败回滚仍为 **UNVERIFIED**，必须先补齐 Core 契约再实施与验收。
- 深色模式、最大动态字体、TalkBack/VoiceOver 实际朗读、横屏、其他 Android 尺寸、iOS 真机与正式签名发布仍为 **UNVERIFIED**。
- `.design-references/` 继续作为未跟踪的本地验收证据保留，没有纳入本轮提交。

final result: passed

---

## Ardot 设计目标首轮代码对齐：左滑删除与危险确认（2026-08-03）

> 本轮以 Ardot `AWiki Me · Core Seven UI · PR Review` 的 22 / 23 / 24 号设计目标为唯一视觉基准，完成现有 Flutter App 的第一段 image-to-code 对齐。未改 Ardot，未使用 Superpowers 技能。

### 设计目标与实现

- 设计目标节点：`104:2113`（会话左滑删除）、`104:2178`（删除会话确认）、`104:1503`（退出并删除凭证确认）。源截图保存在本轮临时对比目录 `/tmp/awiki-targets.xFQ5cG/709816693934731/`。
- 手机会话行现在跟手左滑，露出 84dp 的红色删除操作；操作包含系统垃圾桶图标、文字标签和完整语义按钮，保留长按作为非手势替代入口。
- 删除操作只在滑动或展开状态进入渲染与语义树；点击后先收回操作区再打开确认框。取消后会话仍在，隐藏操作不会继续被读屏发现。
- 手机确认框改为居中卡片、20dp 圆角、40% 黑色遮罩、主次双按钮和实心危险按钮。会话确认文案精简为“从最近列表移除该会话”；设置危险确认精简为“退出 {credential} 并删除本机凭证 / 不会注销身份或影响其他设备”，均不使用句号。
- Ardot 目标中的“同时清空历史消息”需要 Core 提供单会话持久历史删除 API。当前 Core 只有隐藏最近会话和清除可丢弃 conversation snapshot 的能力；Flutter 不伪造历史已清理，因此该复选项明确禁用并标注能力边界。真实持久清理保持 `UNVERIFIED / BLOCKED_BY_CORE_API`。

### 视觉证据

- 可复现视觉基线：`docs/ui-optimization-plan/screenshots/23-compact-conversation-swipe-delete.png`、`24-compact-conversation-delete-confirmation.png`、`22-compact-settings-delete-credential-confirmation.png`。
- 与 Ardot 同尺寸对比后，会话确认框的左右边距、圆角、遮罩、按钮层级和纵向节奏已对齐；设置危险确认框使用更宽的 24dp 外边距和更舒展的标题/说明/按钮间距，匹配独立目标画面。
- P0110 真机证据：`.design-references/design-target-alignment-20260803/device/04-swipe-delete.png`、`05-delete-dialog.png`、`12-settings-danger-dialog.png`；取消后的语义与状态证据为 `09-retest-after-cancel.xml`、`13-settings-after-cancel.xml`。

### 验证与边界

- `flutter analyze`：No issues found；会话工作区测试 `52/52` 通过；会话与设置联合回归 `75/75` 通过；两个视觉基线流程分别 `1/1` 通过；`git diff --check` 通过。
- P0110 保留数据覆盖安装成功：`ai.awiki.awikime.dev` / `0.1.13+23`，`firstInstallTime` 保持 `2026-07-30 15:58:45`，`lastUpdateTime` 为 `2026-08-03 15:12:28`。APK SHA-256：`462366620ef06e7bfad3d428a57533b705a362bab015c9e2b41e3b6e481aaca4`。
- 真机只执行左滑、打开确认和取消；未确认删除会话，未退出登录，未删除凭证，未改变关注关系或发送消息。最终停留在设置页。
- 深色模式、最大动态字体、TalkBack 实际朗读、横屏、其他 Android 尺寸、iOS 真机、正式签名发布以及单会话持久历史清理保持 **UNVERIFIED**。

final result: passed

---

## 会话三点入口、聊天信息页与头像资料导航复验（2026-08-02）

> 用户选定 ImageGen 第 1 版“身份优先聊天信息”方向。本轮先用内置 ImageGen 固定视觉真值，再反推 Flutter 界面和交互；未使用 Superpowers 技能。

### ImageGen 真值与视觉对照

- 选定稿：`.design-references/chat-information-redesign-20260802/imagegen/01-identity-first-chat-information.png`，原始像素 `853 × 1844`，SHA-256 为 `2dac2e05a6ce972c6788b7024a32a6aaf00e3bf3d5ab513f4b26cb21c3b25eda`。方向为 64dp 紧凑顶栏、身份首行、单行搜索、两个系统开关与一个低复杂度危险操作行。
- Flutter 视觉基线：`docs/ui-optimization-plan/screenshots/21-compact-chat-information.png`，视口 `393 × 852 @1x`。同视口对照：`.design-references/chat-information-redesign-20260802/qa/02-reference-vs-flutter-final-393x852.png`。
- P0110 最终截图：`.design-references/chat-information-redesign-20260802/device/27-chat-information-final.png`，真实视口 `1264 × 2800 / 560dpi`。顶栏、身份层级、分组间距、开关尺寸、红色操作行和系统手势区均无溢出或遮挡。
- Widget 截图中“消息免打扰”有两个字形缺失，仅是仓库黄金图 CJK 字体覆盖不全；P0110 真机已完整渲染，不是产品 UI 缺陷。

### 信息架构与真实能力

- 会话详情页右上角改为水平三点，点击进入独立“聊天信息”页；标题保持居中。用户头像点击进入独立“用户信息”页，不再以弹窗承载资料。
- “查找聊天记录”使用当前真实会话消息进行本地过滤；“消息免打扰”和“置顶聊天”写入会话 overlay，免打扰同时接入已提交消息的通知展示门禁。
- 源码核对后确认当前 Core/App 没有“清空单个会话持久记录”接口；现有 `deleteConversation` 只会从最近消息列表隐藏会话。为避免伪功能，最终将 ImageGen 参考中的“清空聊天记录”校正为真实可执行的“移出消息列表”，并在确认弹窗明示“记录保留，重新打开或收到新消息会恢复”。
- 紧凑消息工作区的聊天信息和用户信息改为 root Navigator 页面，防止外层 `PopScope` 在 Android 系统返回时跳过中间层级。新增自动化用例直接验证“用户信息 → 聊天信息 → 会话详情”逐层系统返回。

### 自动化与 P0110 闭环

- `flutter analyze`：8 个相关实现/测试文件 `No issues found`；聊天页与消息通知回归 `147/147` 通过；Android 系统返逐层导航用例 `1/1` 通过；Widget 视觉基线更新与非更新比对均 `8/8` 通过；`git diff --check` 通过。
- `-d macos` 的原生集成宿主因当前 worktree 缺失 AwikiImCore macOS XCFramework slice 无法启动；本轮使用不依赖该原生切片的 Widget 视觉宿主完成像素对比。macOS 原生宿主本轮保持 **UNVERIFIED**。
- P0110 冷启动 `LaunchState: COLD`，`TotalTime: 1008ms`。真机验证三点入口、头像资料页、逐层系统返回、聊天记录搜索 `222`、免打扰/置顶开关的开启与恢复，以及“移出消息列表”确认文案。
- 两个开关最终恢复为 `false`；移出操作只打开确认弹窗后取消，没有移出会话、清除数据、发送消息或改变关系。APP 最终停留在聊天信息页。
- 保留数据覆盖安装成功；包名与版本为 `ai.awiki.awikime.dev` / `0.1.14+25`，`firstInstallTime` 保持 `2026-07-30 15:58:45`，`lastUpdateTime` 为 `2026-08-02 14:46:44`。最终 APK SHA-256：`9fdf3bd5a9b419bb05ea323f1becbee7b08efd2cdf507a14aaa3fe44ee0de9ce`。
- 深色模式、最大动态字体、TalkBack/VoiceOver 实际朗读、横屏、其他 Android 尺寸、iOS 真机与正式签名发布保持 **UNVERIFIED**。
- 未提交、未推送、未合并、未发布；未使用任何 Superpowers 技能。

final result: passed

## “我”Tab 通栏精简列表增量复验（2026-08-01）

### 设计与实现

- ImageGen 最终真值：`.design-references/me-tab-redesign-20260801/05-full-width-minimal-rows.png`。
- 用户要求闭环：“身份卡 / 设置”删除副标题，列表改为页面全宽白底分隔行，无圆角、外框、阴影和图标底盒。
- 折叠态为 `52 + 1 + 52 = 105px`；每行全宽可点，真机约 `56.6dp`，超过 44dp 触控下限。
- 空 profile 展开态增加 28px 低对比“暂无资料”行，箭头向下；再次点击恢复折叠。非空 profile 保留原身份文档内容。
- 展开态同屏对照：`.design-references/me-tab-redesign-20260801/compare-05-vs-p0110-expanded.png`。

### 自动化与真机

- `dart analyze`：No issues found。
- `tests/unit/profile_page_test.dart`：12/12 通过，包含通栏尺寸、无副标题、空态展开/收起、箭头状态和长 DID 回归。
- 联系人 → 我 → 设置视觉用例已更新基线并通过。
- P0110 折叠态：`.design-references/p0110-me-redesign-20260801/16-full-width-collapsed.png`。
- P0110 空资料展开态：`.design-references/p0110-me-redesign-20260801/17-full-width-expanded-empty.png`。
- 独立增量验收：PASS，BLOCKER=0，P0=0，P1=0，P2=0。通栏宽度、可点区、空态反馈、收起、设置跳转/返回、长 DID、四 Tab、顶部标题和无 Logo 均通过。

### 安装与边界

- 最终 APK SHA-256：`b2bf71b78d6d27155f3ce7faea9165fa9a61a5eafdaafe6a47f05b28ffe3450e`。
- 包名与版本保持 `ai.awiki.awikime.dev` / `0.1.14+25`；原生 Core SHA-256 保持 `197725f7b77e55e53cabe5208c0c1edc74ca8ae1e23741b6216792cd15e8fd62`。
- 使用保留数据的覆盖安装；`firstInstallTime` 仍为 `2026-07-30 15:58:45`，账号、会话和资料均保留。
- 未提交、未推送、未合并、未发布；未使用任何 Superpowers 技能。

final result: passed

---

## “我”Tab 居中轻量档案复验（2026-08-01）

### 对照基准

- 设计真值：`.design-references/me-tab-redesign-20260801/03-centered-compact-list.png`
- Flutter 实现：`docs/ui-optimization-plan/screenshots/10-compact-profile.png`
- 视口与状态：compact `393 × 852`、亮色、身份卡默认折叠、底部“我”选中。
- 设计源像素：`852 × 1846`；归一为 `393 × 852`。实现像素与 CSS 视口均为 `393 × 852`，`devicePixelRatio = 1`。
- 全屏同屏证据：`.design-references/me-tab-redesign-20260801/compare-source-vs-flutter-pass3.png`
- 局部证据：`.design-references/me-tab-redesign-20260801/focus-header-identity-pass3.png`、`.design-references/me-tab-redesign-20260801/focus-metadata-navigation-pass3.png`

### 比较历史

1. 第一轮发现 P1：实现顶栏 52px、头像 `y = 80`，相较候选整体提前约 24px；列表仍为 117px。修复为 64px 顶栏、头像 `y ≈ 104`，并把列表压到约 95px。
2. 第二轮发现 P2：统计下缺少分隔线，DID/主页顶部留白不足，列表提前约 25px。补齐分隔线，将两块元数据各调整为 92px、顶部留白 20px，并把列表锚定到 `y ≈ 568`。
3. 第三轮同屏未发现 P0、P1 或 P2；独立设计评审 PASS。

### 最终检查

- 字体与排版：通过。标题 16，Handle 保持单行省略；列表标题/副标题密度与候选一致，动态账号内容差异可接受。
- 间距与布局：通过。64px 顶栏、104px 居中头像、元数据两段 92px、紧凑双行列表约 95px，首屏节奏与候选一致。
- 色彩与令牌：通过。暖白背景、深色正文、蓝色交互和中性分隔线均沿用现有 AWiki Me 令牌。
- 图像与图标：通过。头像使用现有 `AvatarBadge`，操作使用仓库现有 Cupertino/Material 图标，无伪造 Logo、插画或装饰资产。
- 文案与功能：通过。DID、主页、身份卡、设置与四个底部 Tab 全部保留；静态截图内容不同属于运行数据。
- 自动化：Profile Widget `11/11` 通过；联系人 → 我 → 设置视觉流程通过并更新基线。
- 剩余边界：深色模式、动态字体和读屏顺序尚未由本次静态视觉对照证明；真机点击、复制、跳转和触控行为留待 P0110 验收。

final result: passed

---

## Unified Mobile v3 核心七屏复验（2026-08-01）

### 范围与构建

- 隔离工作树：`/Users/howard/ANP-Workspace/Feature/awiki-me-core-seven-ui`
- 分支：`Feature/core-seven-mobile-ui`
- 设计真值：Ardot 核心七屏节点 `23:11`、`23:66`、`23:140`、`23:214`、`23:308`、`23:385`、`23:448`
- 最终安装包：`ai.awiki.awikime.dev`，`0.1.14+25`
- APK：`build/app/outputs/flutter-apk/app-debug.apk`
- APK SHA-256：`eb9ec58f78fafbb74dd469e204d8cae5e90fa07d4d9fa3c51430b8cfb554e477`
- 原生 Core 与已知良好 0.1.14 基线的 arm64 `libawiki_im_core.so` SHA-256 一致：`197725f7b77e55e53cabe5208c0c1edc74ca8ae1e23741b6216792cd15e8fd62`

### 设计与实现门禁

- 独立 UI/UX 评审：PASS，可进入构建与真机阶段。
- 消息：小号居中标题、搜索区、文字列分隔线和四入口顺序通过。
- 会话：双方头像、左右气泡、曲线尾部、输入区和 Agent 信息入口通过。
- 联系人：群组卡、线性图标、搜索和联系人操作通过。
- 智能体：紧凑 Daemon/Runtime 树、主干/分支、状态点和安装入口的静态 fixture 通过。
- 我：身份信息卡、默认折叠、编辑 PenLine 图标和设置入口通过。
- 设置：分组卡片、语言值垂直居中、危险操作下移通过。
- 智能体资料：头像、关注按钮、标签、DID/主页分隔和身份卡通过。

### 自动化证据

- `tests/unit/conversation_workspace_test.dart`：49/49 通过，包含 Android 系统返回回归。
- `tests/unit/navigation_provider_test.dart`：11/11 通过。
- `tests/unit/profile_page_test.dart`：11/11 通过。
- 相关全量套件：聊天 111/111、联系人 19/19、智能体 44/44、设置 22/22 通过。
- Unified Mobile v3 视觉回归：4/4 通过。
- `dart analyze`：No issues found。
- `git diff --check`：通过。
- 全仓 runner 仍有未修改的 `application/app_session_service_test.dart` 基线失败；与本次 UI 文件和 Android Back 修复无关，不作为 UI 通过证据。

### P0110 真机矩阵

| 编号 | 页面/流程 | 结果 | 证据与结论 |
| --- | --- | --- | --- |
| R01 | 冷启动与消息 | PASS | `R01-cold-start-messages.png/xml`；SafeArea、消息头部与四 Tab 顺序正常 |
| R02 | 消息列表 | PASS / 未读角标 UNVERIFIED | 当前账号无未读会话，列表与搜索正常；红色未读角标由静态测试覆盖 |
| R03 | 私聊与返回 | PASS | 初检发现系统 Back 退到 Launcher；增加 compact 导航 `PopScope` 后，`R03c-before-system-back.png` → `R03c-android-back-fixed-PASS.png` 证明系统 Back 回消息列表；`R03d-before-header-back.png` → `R03d-header-back-regression-PASS.png` 证明页头返回无回归 |
| R04 | 智能体聊天 | PASS（视觉） | `R04-agent-chat.png/xml`；头像、气泡、输入区与安全区正常 |
| R05 | 智能体资料 | PASS | `R05-agent-info.png/xml`；信息层级、截断、按钮和卡片无重叠 |
| R06 | 联系人 | PASS | `R06-contacts.png/xml`；群组卡、联系人行、关注按钮和底栏正常 |
| R07 | 智能体树 | UNVERIFIED（填充态） | `R07-agents-tree.png/xml`；空态与安装入口正常；账号无 Daemon/Runtime，未安装 Daemon |
| R08 | 我 | PASS | `R08-me.png/xml`；身份卡默认折叠、资料和设置入口正常 |
| R09 | 设置 | PASS | `R09-settings-top.*`、`R09b-settings-bottom.*`、`R09c-settings-back-to-me.*`；滚动、分组、语言对齐和返回正常 |
| R10 | 语言 Sheet | PASS | `R10-language-sheet.png/xml`；打开/关闭正常，未选择语言 |

### 数据与边界

- 使用 `adb install -r` 覆盖安装，首次安装时间仍为 `2026-07-30 15:58:45`，证明未卸载。
- 全程未发送消息、关注/取关、安装 Daemon、删除/导出凭证、退出账号或清除数据。
- 原有消息、联系人、智能体会话和个人资料均保留。
- 真机未验证：无未读数据时的红色角标、Daemon/Runtime 填充树与实时状态、为保护现有账号而未进入的登录/注册页、实时智能体处理中状态。
- 未合并、未推送、未发布、未提交。
- 未使用任何 Superpowers 技能。

### 四主 Tab 顶部标题统一复验

- “消息、联系人、智能体、我”顶部标题统一使用 `16 / w600 / 1.25`，复用共享 compact top-bar typography token。
- 顶栏仍保持 64 高和居中布局；未修改底部 Tab 标签字体或业务导航；后续 Logo 移除见下一节。
- 四个相关 Widget 套件通过：消息 49/49、联系人 19/19、智能体 44/44、我 11/11；视觉回归 3/3，`dart analyze` 无问题。
- 独立设计评审 PASS；单字“我”的视觉重量差异来自字形本身，不构成字号或对齐偏差。
- P0110 真机证据：`.design-references/p0110-title-16-20260801/01-messages-title-16.png` 至 `04-me-title-16.png`。
- 标题统一版已使用 `adb install -r` 保留数据覆盖安装到 P0110。

final result: passed

### 四主 Tab 左上角 Logo 移除复验

- “消息、联系人、智能体、我”四个主页面的左上角品牌 Logo 已全部移除，标题继续使用 `16 / w600 / 1.25` 并保持几何居中。
- 消息页原 Logo 设置入口同步移除，避免留下不可见点击区域；设置继续通过“我 → 设置”进入，跨断点导航回归已覆盖。
- 右侧操作区保持不变：消息保留新建会话，联系人保留添加，智能体保留更多与安装，我页不新增占位操作。
- 独立 UI 评审 PASS：四页左侧留白自然，无残留轮廓、占位或不可见按钮暗示；标题未被右侧操作区拉偏。
- 四个相关 Widget 套件合计 `123/123` 通过；视觉回归 `3/3` 通过；`dart analyze` 无问题；`git diff --check` 通过。
- P0110 真机证据：`.design-references/p0110-no-header-logo-20260801/01-messages.png` 至 `04-me.png`；四页左上角均为空白，标题与右侧按钮无位移。
- 使用同版本 `0.1.14+25` 保留数据覆盖安装；`firstInstallTime` 仍为 `2026-07-30 15:58:45`，未卸载或清除数据。

final result: passed

---

## “我”Tab 身份卡真实资料增量复验（2026-08-01）

### 设计与实现

- ImageGen 最终真值：`.design-references/me-tab-redesign-20260801/06-identity-card-real-data.png`；归一稿：`06-identity-card-real-data-393x852.png`。
- 移动端身份卡展开后始终显示真实头像、昵称、完整 Handle、DID 与主页，不再以 `bio/profileMarkdown` 是否为空决定基础身份信息是否可见。
- 可选简介、正文与标签只在清洗后确有内容时追加；仅包含机器生成 Handle/DID 元数据的资料不会再渲染空白大卡，也不会出现“暂无资料”。
- 全宽通栏、`52 / 60 / 44 / 44 / 52px` 行高、44px 操作热区和固定底部四 Tab 均保持选定设计。

### 自动化与评审

- `flutter analyze lib/src/presentation/profile/profile_page.dart tests/unit/profile_page_test.dart`：No issues found。
- `tests/unit/profile_page_test.dart`：13/13 通过；元数据-only 回归覆盖真实身份摘要、DID 复制、主页、收起及“无空白扩展卡”。
- 联系人 → 我 → 身份卡展开 → 设置视觉用例：1/1 通过；截图 `docs/ui-optimization-plan/screenshots/10b-compact-profile-identity-expanded.png`。
- 独立视觉评审：PASS，P0=0、P1=0、P2=0；未发现过度设计或新增伪资料。
- TFD 独立真机 QA 复核：PASS，BLOCKER=0、P0=0、P1=0、P2=0；确认最终截图无“暂无资料”或空白大卡，复制反馈可见。

### P0110 真机闭环

- 展开并滚动后的最终截图：`.design-references/p0110-me-redesign-20260801/26-identity-card-real-data-final.png`；空白身份卡已消失，真实身份摘要、DID、主页与设置完整可见。
- DID 复制反馈：`.design-references/p0110-me-redesign-20260801/27-identity-copy-did-final.png`，显示“DID 已复制”。
- 设置入口可进入并显示当前版本 `0.1.14`，系统返回后回到“我”；未打开外部主页，主页真实外跳保持 UNVERIFIED。
- 最终 APK SHA-256：`ee25655e83127d07c8805874ded0ff8b1a187b032fde9bfaed353b9695811611`。
- 包名与版本保持 `ai.awiki.awikime.dev` / `0.1.14+25`；原生 Core SHA-256 保持 `197725f7b77e55e53cabe5208c0c1edc74ca8ae1e23741b6216792cd15e8fd62`。
- 使用保留数据的覆盖安装；`firstInstallTime` 仍为 `2026-07-30 15:58:45`，`lastUpdateTime` 为 `2026-08-01 22:46:07`。
- 未提交、未推送、未合并、未发布；未使用任何 Superpowers 技能。

final result: passed

---

## “我”Tab 身份卡回退为简约空态复验（2026-08-01）

> 本节按用户最新反馈取代上一节“真实资料展开态”：身份信息已在上方展示，身份卡不得重复头像、Handle、DID 或主页。

### 设计真值与实现

- ImageGen 最终真值：`.design-references/me-tab-redesign-20260801/07-identity-card-empty-state-390x844.png`。
- Flutter 实现：`docs/ui-optimization-plan/screenshots/10b-compact-profile-identity-expanded.png`。
- 同屏证据：`.design-references/me-tab-redesign-20260801/compare-07-vs-flutter-expanded.png`，视口归一为 `393 × 852`；动态账号、未读数和 OS 状态栏差异不作为实现偏差。
- 空资料展开态为全宽 `52px` 身份卡行、`28px` 低强调“暂无资料”行、`1px` 分隔线和 `52px` 设置行；折叠态仍为 `105px`。
- 有独立简介、正文或标签时继续显示既有 `IdentityDocumentCard`；仅机器生成 Handle/DID 元数据时只显示紧凑空态。

### 自动化与独立评审

- `flutter analyze`：No issues found。
- `tests/unit/profile_page_test.dart`：12/12 通过，覆盖 metadata-only 空态、无重复字段、再次收起、非空资料卡、桌面和长字段回归。
- 联系人 → 我 → 身份卡展开 → 收起 → 设置视觉流程：1/1 通过。
- TFD 独立设计评审：PASS，P0=0、P1=0、P2=0；字体、间距、色彩、图标和文案保持简约实用。
- TFD 独立真机 QA：PASS，BLOCKER=0、P0=0、P1=0、P2=0；未滚动时设置入口可识别，轻微上滑可完整到达，不构成固定 Tab 遮挡。

### P0110 真机闭环

- 未滚动展开态：`.design-references/p0110-me-redesign-20260801/28-identity-card-empty-state-final.png`；“暂无资料”立即可见，重复身份区已移除。
- 轻微上滑后的完整态：`.design-references/p0110-me-redesign-20260801/29-identity-card-empty-state-scrolled-final.png`；身份卡、空态与设置行完整显示，底部 Tab 无遮挡。
- 已验证展开、再次收起、进入设置、系统返回；当前版本显示 `0.1.14`。
- 最终 APK SHA-256：`e1e96d1061ba93bf9f27442dae9e9d19d9ed4eb47dbd946a4b545eab5cd58a19`。
- 包名与版本保持 `ai.awiki.awikime.dev` / `0.1.14+25`；原生 Core SHA-256 保持 `197725f7b77e55e53cabe5208c0c1edc74ca8ae1e23741b6216792cd15e8fd62`。
- 覆盖安装保留数据；`firstInstallTime` 仍为 `2026-07-30 15:58:45`，`lastUpdateTime` 为 `2026-08-01 23:11:02`。
- 深色模式、最大动态字体、TalkBack/VoiceOver、横屏与正式签名发布保持 UNVERIFIED。
- 未提交、未推送、未合并、未发布；未使用任何 Superpowers 技能。

final result: passed

---

## “我”Tab DID / 主页折叠选项复验（2026-08-01）

> 本节按用户最新要求取代此前移动端顶部常显 DID / 主页的布局：DID、主页与身份卡现在统一为默认收起、单开互斥的全宽选项；设置仍直接进入页面。

### ImageGen 真值与实现

- 初版 ImageGen 候选：`.design-references/me-tab-redesign-20260801/08-did-homepage-accordion-390x844.png`，确定四个 `52px` 全宽入口和单开手风琴结构。
- P0110 初验发现真实长 DID 在 `64px` 详情区出现省略号后，先重新生成最终 ImageGen 真值 `.design-references/me-tab-redesign-20260801/09-did-long-value-three-line-390x844.png`，再按真值把 DID 详情区调整为 `84px`、正文 `12px / 16px`、最多四行；最终长 DID 完整显示。
- 最终同屏证据：`.design-references/me-tab-redesign-20260801/compare-09-vs-p0110-did-full.png`。ImageGen 原图为 `390 × 844`，P0110 原图为 `1264 × 2800`；同屏比较将两者归一为 `390 × 844`，真实尺寸和触控判断仍以原图与 XML 为准。
- 四个入口均为全宽平面列表：`DID / 主页 / 身份卡 / 设置`；主行高 `52px`，DID 详情 `84px`，主页详情 `64px`，身份空态 `28px`。无圆角卡片、阴影、重复说明或额外装饰。
- DID、主页和身份卡共用单一 `_CompactProfileSection` 状态，因此任一入口展开时都会关闭其他两个；再次点击当前入口会收起。设置直接导航，不参与展开状态。
- DID 继续复用 `CopyableDidLine`，完整值与复制按钮均可达；主页继续复用既有 URL 打开能力；身份只有机器生成元数据时保持“暂无资料”，不重复上方身份信息。
- 桌面布局与行为未改动。

### 自动化与独立评审

- `flutter analyze lib/src/presentation/profile/profile_page.dart tests/unit/profile_page_test.dart tests/e2e/flutter/app/ui_visual_verification_test.dart`：No issues found。
- `tests/unit/profile_page_test.dart`：13/13 通过；覆盖默认收起、DID / 主页 / 身份卡单开互斥、再次收起、DID 复制、主页操作、无主页几何、身份空态、桌面回归和 `360px` 长 DID 无溢出。长值测试额外断言 `RenderParagraph.didExceedMaxLines == false`。
- 联系人 → 我 → DID → 主页 → 身份卡 → 收起 → 设置聚焦视觉流程：1/1 通过；最终截图为 `docs/ui-optimization-plan/screenshots/10a-compact-profile-did-expanded.png`、`10c-compact-profile-homepage-expanded.png`、`10b-compact-profile-identity-expanded.png`。
- 独立设计评审：PASS，P0=0、P1=0、P2=0；确认长 DID 完整、几何与触控约束、单开互斥、底部 Tab 无遮挡且不存在过度设计。
- TFD 真机 UI QA：PASS，BLOCKER=0、P0=0、P1=0、P2=0；确认真实长 DID、复制反馈、主页和身份空态互斥、设置可达性与全宽平面列表质量。
- `git diff --check` 通过；`pubspec.lock` 无变化；未创建 `pubspec_overrides.yaml`。

### P0110 真机闭环

- DID 最终展开：`.design-references/p0110-me-redesign-20260801/33-profile-did-full-final.png`；真实 `did:wba:agent-connect.cn:user:newhandle2:e1_Uqj4oA4H5LkplPTWmHJ20HoTeM_77qYtVgSjmU1Zo-w` 完整显示，无省略号、裁切或底部遮挡。
- 复制反馈：`.design-references/p0110-me-redesign-20260801/34-profile-did-copied-final.png`，语义状态显示“DID 已复制”；复制目标 `154 × 154` physical px，约 `48dp`。
- 主页展开：`.design-references/p0110-me-redesign-20260801/35-profile-homepage-expanded-final.png`；仅主页详情可见，DID 已关闭。
- 身份卡展开：`.design-references/p0110-me-redesign-20260801/36-profile-identity-empty-final.png`；仅显示紧凑“暂无资料”，DID 与主页均关闭。
- 设置入口：`.design-references/p0110-me-redesign-20260801/37-settings-final.png`；版本显示 `0.1.14`，返回后回到“我”且四项全部收起。
- 最终 APK SHA-256：`44a4ce1bf199e26ecfb8d97287b6bb11ec8e8e3a3a089e5e92e126cc0a9c80f8`。
- 包名与版本保持 `ai.awiki.awikime.dev` / `0.1.14+25`；原生 Core SHA-256 保持 `197725f7b77e55e53cabe5208c0c1edc74ca8ae1e23741b6216792cd15e8fd62`。
- 使用保留数据的覆盖安装；`firstInstallTime` 仍为 `2026-07-30 15:58:45`，`lastUpdateTime` 为 `2026-08-01 23:49:07`。
- 已删除 P0110 `/data/local/tmp` 中本次以 `awiki-` 命名的临时验收文件；工作区设计与真机证据保留。
- 主页真实外跳、深色模式、最大动态字体、TalkBack/VoiceOver、横屏及正式签名发布保持 UNVERIFIED。
- 未提交、未推送、未合并、未发布；未使用任何 Superpowers 技能。

final result: passed

---

## 设置页简约全宽重设计复验（2026-08-02）

> 本节按用户最新要求完成设置页的完整设计闭环：先审计真机与现有功能，再经 ImageGen 选型、Ardot 反推、Flutter 实现、P0110 覆盖安装、主验收和两路独立评审收口。设计原则为简约、美观、实用，避免过度设计。

### ImageGen 与 Ardot 设计真值

- 审计证据位于 `.design-references/settings-redesign-20260802/current-audit`；功能范围保持个人资料、设备、个人助理、消息同步、版本、检查更新、语言、凭证导出、退出登录和删除账号。
- 生成三套 ImageGen 候选后，由独立设计评审选择 `.design-references/settings-redesign-20260802/01-quiet-full-width.png`；最终方向为暖灰背景、白色全宽扁平行、24dp 线性图标、无圆角卡片、无图标底板、无阴影和渐变噪点。
- Ardot 文件 `cocraft://localhost/file/709816693934731` 的 `AWiki Me · Unified Mobile v3` 页面新增 Phase 12；总览节点为 `24:2`，ImageGen 参考为 `24:6`，顶部真值为 `24:8`，安全区真值为 `24:10`。
- 顶部同屏对比：`.design-references/settings-redesign-20260802/settings-comparison-imagegen-ardot-p0110.png`；安全区同屏对比：`.design-references/settings-redesign-20260802/settings-security-comparison-ardot-p0110.png`。参考、Ardot 与真机使用同一状态归一比较，未发现需继续修复的可见偏差。

### Flutter 实现与自动化

- 移动端设置页改为全宽扁平列表；内容左右内边距统一为 `20dp`，个人助理保持双行，当前版本为只读状态且无 chevron，长动态值单行省略，桌面分支保持原行为。
- 普通交互行、导出、退出和删除均满足 `>=48dp` 触控高度；退出与删除之间使用 `96dp` 留白，删除账号位于首屏以下并采用独立浅红色危险操作带。
- 既有交互全部保留：个人资料、设备、个人助理、消息同步、检查更新、语言、导出、退出确认和删除确认；检查更新时会禁用重复触发。
- `flutter analyze`：No issues found。
- `tests/unit/settings_page_test.dart`：23/23 通过，覆盖布局几何、长动态值、只读版本、异步状态和确认流程。
- 设置页聚焦视觉流程：1/1 通过；截图更新为 `docs/ui-optimization-plan/screenshots/11-compact-settings.png` 和 `11b-compact-settings-danger.png`。
- `git diff --check` 通过；`pubspec.lock` 与 `pubspec.yaml` 无新增差异，未创建 `pubspec_overrides.yaml`。

### P0110 覆盖安装与真机闭环

- Debug APK 构建成功，SHA-256 为 `520055487a0159caa7591eda73fccc01498a352cc8bbc0ce0d5ad551090d58e5`；包名与版本保持 `ai.awiki.awikime.dev` / `0.1.14+25`。
- 原生 Core `libawiki_im_core.so` SHA-256 保持 `197725f7b77e55e53cabe5208c0c1edc74ca8ae1e23741b6216792cd15e8fd62`；使用保留数据覆盖安装，`firstInstallTime` 仍为 `2026-07-30 15:58:45`，`lastUpdateTime` 为 `2026-08-02 00:43:51`。
- 主验收证据位于 `.design-references/settings-redesign-20260802/device-final`：冷启动和既有会话数据保留；语言面板居中；检查更新返回“已是最新版本”；退出和删除弹窗均完整显示并仅走取消路径；最终 APP 留在设置页顶部。
- 实测普通行约 `54–56dp`、个人助理约 `88dp`、导出约 `68dp`、退出约 `74–80dp`、删除约 `92–93dp`；无横向溢出、裁切、黑角或底部遮挡。
- P0110 `/data/local/tmp` 中本轮 `awiki-settings-*` 临时截图与 XML 已删除，工作区证据仍完整保留；删除的仅为可重建的设备临时文件。

### 独立评审与边界

- TFD 独立设计评审：PASS，P0=0、P1=0、P2=0；确认全宽平面行、24dp 图标、双行个人助理、只读版本、危险区分级和简约方向，无过度设计。
- TFD 独立真机 QA：PASS，BLOCKER=0、P0=0、P1=0、P2=0；独立复验语言面板、更新反馈、退出取消、删除取消、返回资料仍保留及重新进入设置。证据已归档至 `.design-references/settings-redesign-20260802/device-independent-qa`，最终 APP 留在设置页顶部。
- 未确认真正退出登录或删除账号；未执行凭证导出、实际语言切换、更新失败或发现新版本分支，以避免不必要的外部或破坏性副作用。
- 深色模式、最大动态字体、TalkBack/VoiceOver、横屏、其他真机尺寸和正式签名发布保持 UNVERIFIED。
- 未提交、未推送、未合并、未发布；未使用任何 Superpowers 技能。

final result: passed

---

## 设置页图1差距纠正复验（2026-08-02）

> 本节取代上一节中“危险区分级是可接受差异”的结论。用户指出真机设置页与图1仍有差距是正确的；上一轮把自行增加的危险区留白与浅红色分组误判为通过，现已按图1重新收敛。

### 差距与修正

- 修正前 P0110 证据：`.design-references/settings-gap-audit-20260802/01-p0110-current.png`、`02-p0110-top.png`。主要 P1 差距是退出与删除之间存在 `96dp` 大留白、额外“危险操作”标题和浅红危险带，导致删除入口离开首屏；P2 差距包括设备行缺少说明、个人资料行密度不足、个人助理说明换行。
- 最终 ImageGen 真值继续使用用户选择的图1 `.design-references/settings-redesign-20260802/01-quiet-full-width.png`；本轮是对既有真值的忠实纠偏，没有另行生成会改变方向的新候选。
- 移除额外危险区标题、大留白与浅红底；导出、退出、删除恢复为同一连续白色全宽列表，保留红色破坏性文字、图标与确认流程。
- 设备行补回“查看已授权设备并审批新设备”；个人助理说明收敛为单行“配置个人助理的启用、暂停和 Daemon 管理”；个人资料头像与行高按图1放大。
- 使用安全内容高度做短屏自适应：标准 `390×844` 视口使用资料 `104dp`、账户行 `72dp`、应用行 `60dp`、安全行 `68/68/84dp`；P0110 短安全区使用 `88dp`、`64dp`、`52dp`、`60/60/68dp`。短屏仍在首屏显示全部安全操作，所有可点击行保持 `>=48dp`。

### Ardot、Flutter 与真机证据

- Ardot 文件 `cocraft://localhost/file/709816693934731` 的 Phase 12 已更新；最终节点 `24:8`，截图 `.design-references/settings-gap-audit-20260802/ardot-v2/709816693934731/screenshot-24_8-20260802_030831763.png`。旧的独立危险区节点 `24:9`、`24:10` 已隐藏，未作为当前真值。
- Flutter 标准视口基准图：`docs/ui-optimization-plan/screenshots/11-compact-settings.png`。
- P0110 最终真机图：`.design-references/settings-gap-audit-20260802/device-v2/01-p0110-settings-v2.png`；最终 XML：同目录 `01-p0110-settings-v2.xml`。
- 四栏同屏对比：`.design-references/settings-gap-audit-20260802/comparison-figure1-ardot-flutter-p0110-v2.png`，顺序为图1、Ardot、Flutter、P0110。四栏归一为 `390×844` 仅用于视觉比较；触控尺寸以 P0110 原始 `1264×2800`、density `3.5` 的 XML 为准。
- P0110 的系统状态栏与底部手势区属于 Android 系统界面，图1未绘制；应用拥有的标题、资料、分区和列表区域已对齐，不将系统 chrome 计为设计偏差。

### 自动化与 P0110 交互

- `flutter analyze lib/src/presentation/settings/settings_page.dart lib/l10n tests/unit/settings_page_test.dart tests/e2e/flutter/app/ui_visual_verification_test.dart`：No issues found。
- `tests/unit/settings_page_test.dart`：23/23 通过；覆盖标准视口几何、短屏首屏完整性、长值省略、功能与确认流程。
- 设置页聚焦视觉基准：1/1 通过；`integration_test plugin was not detected` 为现有测试目录提示，不影响本次 Widget 视觉断言结果。
- `git diff --check` 通过。
- P0110 上语言面板正常且居中；检查更新仍显示“已是最新版本”；退出登录与删除凭证确认框均完整打开并仅执行取消，未退出、未删除、未切换语言、未导出凭证。
- 真机 XML 实测资料行约 `88dp`，设备/个人助理约 `64dp`，应用行约 `52dp`，导出/退出约 `60dp`，删除约 `68dp`，均满足移动端最小触控目标。
- 使用保留数据的覆盖安装；包名与版本保持 `ai.awiki.awikime.dev` / `0.1.14+25`，`firstInstallTime` 仍为 `2026-07-30 15:58:45`，`lastUpdateTime` 为 `2026-08-02 03:10:50`。
- 最终 APK SHA-256：`d790a939b2821a4754203a78de86c6cf9612bf1ffc25a7ffba328a6a96c0b7c6`；原生 Core SHA-256 保持 `197725f7b77e55e53cabe5208c0c1edc74ca8ae1e23741b6216792cd15e8fd62`。
- 已删除 P0110 `/data/local/tmp` 中本轮明确列出的临时截图与 XML；工作树内验收证据保留。
- 深色模式、最大动态字体、TalkBack/VoiceOver、横屏、其他真机尺寸、正式签名发布和真正的退出/删除保持 UNVERIFIED。
- 未提交、未推送、未合并、未发布；未使用任何 Superpowers 技能。

final result: passed

---

## 消息 / 联系人右上角快捷操作弹出框复验（2026-08-02）

> 本节按用户选定的 ImageGen 方案 01，将移动端快捷操作从底部 Action Sheet 改为类似微信位置关系的右上角锚定弹出框；仅借鉴位置与交互方式，颜色继续使用 AWiki Me 的暖白中性色与品牌蓝。

### 参考、ImageGen 与 Ardot 真值

- P0110 旧版底部弹层审计位于 `.design-references/top-right-menu-redesign-20260802/current`；脱敏后的微信右上角菜单参考为 `.design-references/top-right-menu-redesign-20260802/wechat/04-wechat-plus-menu-reference.png`。
- 用户选定的 ImageGen 真值为 `.design-references/top-right-menu-redesign-20260802/selected/01-warm-paper-pointer.png`：暖白表面、AWiki 蓝线性图标、深灰文字、右上角三角指向触发按钮、无标题与无图标底板。
- Ardot 文件 `cocraft://localhost/file/709816693934731` 的 `AWiki Me · Unified Mobile v3` 页面新增 Phase 13；总览节点 `41:3`，ImageGen 参考 `41:9`，消息弹出态 `41:10`，联系人弹出态 `41:65`。最终总览截图为 `.design-references/top-right-menu-redesign-20260802/ardot-final/709816693934731/screenshot-41_3-20260802_083045411.png`。
- 四栏同屏证据为 `.design-references/top-right-menu-redesign-20260802/comparison-imagegen-ardot-code-device.png`，顺序为 ImageGen、Ardot、Flutter 视觉基线、P0110；归一到 `393 × 852` 只用于可见差异评审，真机触控尺寸以原始 `1264 × 2800`、density `3.5` 的 XML 为准。

### Flutter 实现与视觉规格

- 窄屏消息和联系人统一使用右上角锚定菜单；桌面端原有 `showMenu` 锚定实现保持不变，只有无法解析触发锚点时才回退到原 Action Sheet。
- 菜单宽 `196dp`、右边距 `8dp`、圆角 `12dp`；每行 `52dp`，左右内边距 `16dp`，图标 `20dp`，图文间距 `12dp`，正文 `15sp / Medium`；分隔线从文字列开始。
- 表面为 `#FFFFFF`，图标为 `#0081D3`，文字为 `#2D2B26`，分隔线为 `#E8E7E4`；使用轻量中性阴影和 `6%` 遮罩，无渐变、玻璃效果、深色微信式菜单或额外标题。
- 三角指针按触发按钮中心动态计算并限制在菜单安全边距内；点空白处、系统返回键和 Escape 均可关闭。四个菜单项复用原功能：发起新消息、创建群聊、加入群聊、关注联系人。
- 每行保留 `SemanticsRole.menuItem`，最终 P0110 XML 的 `content-desc` 已去重为单一动作名称；四个触控边界高度均为 `182px / 3.5 = 52dp`。

### 自动化与已知边界

- `flutter analyze`：No issues found。
- 消息窄屏锚定菜单定向组件测试：1/1 通过；联系人窄屏锚定菜单定向组件测试：1/1 通过，覆盖宽度、右边距、行高、品牌色、指针和点外关闭。
- 消息 → 联系人双弹出态视觉用例：1/1 通过；基线为 `docs/ui-optimization-plan/screenshots/15-compact-quick-actions.png` 与 `15b-compact-contacts-quick-actions.png`。
- 消息、联系人、身份入口三个文件的合并回归在 73 项通过后，既有“手机四入口与桌面身份 Dialog 在跨断点时保持有效状态”用例仍因找不到 `profile-display-name` 失败；单独复现同样失败。该路径未打开快捷菜单，不影响本节定向结论，但完整回归绿灯保持 UNVERIFIED。
- 深色模式、最大动态字体、TalkBack/VoiceOver 实际朗读、横屏、其他真机尺寸、iOS 真机与正式签名发布保持 UNVERIFIED。

### P0110 覆盖安装与真机闭环

- 最终消息弹出态：`.design-references/top-right-menu-redesign-20260802/device-final/07-final-messages-menu-open.png`；最终联系人弹出态：同目录 `08-final-contacts-menu-open.png`。两页均从右上角触发，菜单不再从底部出现。
- 真机验证点外关闭、Android 系统返回关闭、再次打开、切换消息/联系人，以及点击“发起新消息”进入既有身份查找流程后返回；未执行关注、建群、加群等会改变业务状态的确认动作。
- 使用保留数据的覆盖安装；包名与版本为 `ai.awiki.awikime.dev` / `0.1.14+25`，`firstInstallTime` 保持 `2026-07-30 15:58:45`，`lastUpdateTime` 为 `2026-08-02 08:37:58`，既有会话与联系人数据仍在。
- 最终 APK SHA-256：`bd0a95c9f17cd238c1b8fb97e9de669a33f2046070fa9faf988fa8d5a59ba4f9`；原生 Core SHA-256 保持 `197725f7b77e55e53cabe5208c0c1edc74ca8ae1e23741b6216792cd15e8fd62`。
- 已删除 P0110 `/data/local/tmp` 中本轮明确列出的 `awiki-menu-*`、`awiki-install.xml` 与 `awiki-final-install.xml` 可重建临时文件；工作树证据保留。最终 APP 已恢复到消息页正常状态。
- 未提交、未推送、未合并、未发布；未使用任何 Superpowers 技能。

final result: passed

---

## 消息 / 联系人右上角图标一致性复验（2026-08-02）

> 本轮不重新生成新的 ImageGen 方案：用户要求的是消息页精确复用联系人页既有图标，直接使用已选定设计真值能避免引入新的形状偏差。

### Ardot 与 Flutter 同步

- 消息页右上角图标由编辑图标改为与联系人页完全相同的蓝色圆形加号；两页继续共用 `154 × 154px / 3.5 = 44dp` 触控边界与“更多操作”语义。
- Ardot 核心消息屏 `23:11` 与 Phase 13 消息弹出态 `41:10` 已复制联系人页的圆形加号节点；对应联系人真值为 `23:308` 与 `41:65`。
- Ardot 复验截图位于 `.design-references/top-right-menu-redesign-20260802/icon-consistency-ardot`；普通态和弹出态均未发现位置、尺寸、颜色或对齐偏差。
- Flutter 消息页显式使用 `CupertinoIcons.add_circled`；联系人页原实现保持不变，并新增消息页定向断言防止图标回退。
- `flutter analyze`：No issues found；消息、联系人聚焦组件测试各 1/1 通过；双页快捷菜单视觉基线 1/1 通过。

### P0110 真机闭环

- P0110 消息页证据为 `.design-references/top-right-menu-redesign-20260802/icon-consistency-device/messages.png`；联系人页最终证据为同目录 `contacts-2.png`。
- 两页触发按钮的语义边界均为 `[1080,175][1234,329]`；从该区域裁出的 PNG SHA-256 完全相同：`8771d824452c981c02ac20e3b91127bd5c3c44fa1f56d047f7bbf1c10847c507`。
- 使用保留数据覆盖安装；包名与版本为 `ai.awiki.awikime.dev` / `0.1.14+25`，`firstInstallTime` 保持 `2026-07-30 15:58:45`，`lastUpdateTime` 为 `2026-08-02 08:50:40`。
- APK SHA-256：`39f32072be5b852b10ff20de018c1d948308b221a87bf10b54e131fcbd574be3`。验收结束后 APP 已恢复到消息页正常状态，本轮设备临时截图/XML 已按明确文件名删除。
- 未提交、未推送、未合并、未发布；未使用任何 Superpowers 技能。

final result: passed

---

## 联系人四 Tab 重组复验（2026-08-02）

> 联系人移动端页面已按“全部、关注、粉丝、群组”四个一级 Tab 重组；遵循先 ImageGen、再 Ardot 反推、最后 Flutter 与 P0110 真机闭环的流程。桌面端既有概览与分栏行为保持不变。

### ImageGen 与 Ardot 真值

- 内置 ImageGen 选定稿：`.design-references/contacts-four-tabs-20260802/imagegen/01-four-tabs-clean-list.png`。提示方向为：保留 AWiki Me 既有顶栏、右上角圆形加号和四入口底栏；新增等宽四 Tab，选中“全部”使用品牌蓝文字与短下划线；联系人/群组使用扁平全宽列表，不使用卡片、胶囊、渐变或重阴影。
- Ardot 文件 `cocraft://localhost/file/709816693934731` 的 `AWiki Me · Unified Mobile v3` 页面已同步；核心联系人屏为 `23:308`，更名为 `Screen 05 · Contacts · Four Tabs`。四个 Tab 为 `41:198` 至 `41:201`，选中线 `41:202`，底部分隔线 `41:203`。
- Phase 14 总览节点为 `41:204`；ImageGen 参考 `41:208`，最终可编辑 Ardot 真值 `41:265`。最终核心截图：`.design-references/contacts-four-tabs-20260802/ardot-final-v2/709816693934731/screenshot-23_308-20260802_090440775.png`。
- 四栏对比证据：`.design-references/contacts-four-tabs-20260802/comparison-imagegen-ardot-flutter-p0110.png`，顺序为 ImageGen、Ardot、Flutter、P0110。

### Flutter 行为与自动化

- 窄屏联系人页使用四个等宽 Tab；“全部”合并关注与粉丝并按规范化 DID/Handle 去重，“关注”“粉丝”分别保留消息/关注/取消关注动作，“群组”在当前页显示扁平群组列表并可进入群聊。
- 搜索限定在当前 Tab；联系人页提示“搜索联系人”，群组页提示“搜索群组”。打开联系人资料或跨紧凑/桌面断点返回时，当前 Tab 选择保持稳定。
- Tab 触控边界为 `97.5 × 55dp`；操作按钮高度 `44dp`，均满足移动端最小触控目标。选中态同时使用蓝色文字与 `40 × 3dp` 下划线，不只依赖颜色。
- `flutter analyze`：No issues found；`tests/unit/friends_workspace_test.dart` 20/20 通过；联系人/资料/设置视觉用例 1/1 通过；右上角快捷操作视觉用例 1/1 通过。

### P0110 真机闭环

- 使用保留数据覆盖安装；包名与版本为 `ai.awiki.awikime.dev` / `0.1.14+25`，`firstInstallTime` 保持 `2026-07-30 15:58:45`，`lastUpdateTime` 为 `2026-08-02 09:18:03`。
- 四种真机状态位于 `.design-references/contacts-four-tabs-20260802/device`：`01-all.png`、`02-following.png`、`03-followers.png`、`04-groups.png`；最终恢复态为 `05-all-restored.png`。
- 真机语义树确认四个 Tab 边界分别为 `[0,602][316,795]`、`[316,602][632,795]`、`[632,602][948,795]`、`[948,602][1264,795]`；选中状态逐项正确切换。群组页搜索提示正确切换为“搜索群组”。
- 真机当前数据下，关注为空态，粉丝显示 `newhandle1.agent-connect.cn`，群组显示 `new group / 共 2 位成员`；长 Handle、操作按钮、下划线、底栏均无裁切、重叠或跳位。仅切换 Tab，未执行关注/取消关注、发消息或进入群聊等业务动作；验收后停留在联系人“全部”。
- APK SHA-256：`2532a7c143e2f57089a4e2f126a954d13a5600bd4227b0fb87950ce24eb344bf`。
- 已删除 P0110 上本轮明确列出的 `awiki-contacts-tabs-*` 临时截图/XML；工作树内验收证据保留。
- 深色模式、最大动态字体、TalkBack/VoiceOver 实际朗读、横屏、其他真机尺寸、iOS 真机与正式签名发布保持 UNVERIFIED。
- 未提交、未推送、未合并、未发布；未使用任何 Superpowers 技能。

final result: passed

---

## 联系人群组 Tab 白屏修复复验（2026-08-02）

> P0110 已复现：群组列表首次打开正常，但联系人页在群组已选中时被 AppShell 保留为 Offstage，切到消息再返回联系人后，只剩底部导航，联系人内容区完全白屏。对照“全部”Tab 同路径正常，问题定位到群组内容区的 `AnimatedSwitcher` 叠层与保留页面生命周期组合，不是群组数据为空或接口失败。

### 修复与回归

- 移除联系人分类内容区的 `AnimatedSwitcher`、淡入叠层和旧子树堆叠；改为单一内容树直接切换。四个 Tab 的布局、文案、搜索提示、群组行和触控边界保持不变，因此本轮不重新生成 ImageGen 或修改 Ardot 视觉真值。
- 新增“群组已选中 → 外层 Offstage/TickerMode 隐藏 → 恢复联系人页”的回归用例，并断言联系人标题、“搜索群组”、群组行和选中内容全部存在。
- `flutter analyze`：No issues found；`tests/unit/friends_workspace_test.dart` 21/21 通过；联系人/资料/设置视觉用例 1/1 通过。现有 `integration_test plugin was not detected` 为测试目录提示，不影响 Widget 视觉断言结果。
- `git diff --check` 通过。

### P0110 真机闭环

- 修复前白屏证据：`.design-references/contacts-four-tabs-20260802/bug-white-screen/01-repro.png`；“全部”Tab 同路径正常的控制图为同目录 `07-return-while-all-selected.png`。
- 修复后首次群组页：`.design-references/contacts-four-tabs-20260802/bug-white-screen/fixed-device/01-group-first-open.png`；切到消息再返回联系人后的关键证据：同目录 `02-group-after-return.png`。
- 压力复验执行 3 轮联系人/消息底栏往返、3 轮全部/群组切换，以及一次回到系统桌面再恢复 APP；最终图与 XML 为同目录 `03-group-after-stress-and-resume.png` / `.xml`。最终语义树仍包含“联系人”“搜索群组”、四个 Tab、群组选中状态与 `new group / 共 2 位成员`，没有复发白屏。
- 使用保留数据覆盖安装；包名与版本为 `ai.awiki.awikime.dev` / `0.1.14+25`，`firstInstallTime` 保持 `2026-07-30 15:58:45`，`lastUpdateTime` 为 `2026-08-02 09:38:55`。
- APK SHA-256：`99a98961f87088acc6aa283324a14a6acf47581fe6d883b7c50b5e25a8cfc0ce`。
- 已删除 P0110 上本轮两个明确命名的 `awiki-group-white*` 临时目录和安装确认 XML；工作树内复现与修复证据保留。
- 未点击群组行或执行关注、取消关注、发消息等业务动作；未清除 APP 数据。深色模式、最大动态字体、TalkBack/VoiceOver、横屏、iOS 真机与正式签名发布保持 UNVERIFIED。
- 未提交、未推送、未合并、未发布；未使用任何 Superpowers 技能。

final result: passed

---

## 联系人群组本地导航与返回层级复验（2026-08-02）

> 本轮只修正页面归属与返回层级，不改变已确认的联系人、群组列表或群聊视觉，因此不重新生成 ImageGen 方案，也不修改 Ardot 视觉真值。

### 修复与自动化

- 将“准备群聊数据”和“切换到底部消息 Tab”拆开：联系人四 Tab 内的群组行只准备并打开会话数据，随后压入联系人工作区自己的群聊页面；群组列表等其他既有入口继续保持原导航行为。
- 联系人工作区新增 `groupChat` 详情状态；窄屏使用内层 Navigator 页面栈，宽屏使用联系人右侧详情区。打开群聊时不设置消息页的 `selectedConversationProvider`，也不改变 `shellDestinationProvider`。
- 系统返回与页面左上角返回都会弹出联系人内层群聊页，恢复联系人“群组”Tab、搜索提示和原群组列表；群聊详情显示期间底部 Tab 隐藏。
- `flutter analyze`：No issues found；`tests/unit/friends_workspace_test.dart` 22/22 通过，其中新增用例断言群聊期间 Shell 保持联系人、消息选中会话为空，系统返回后仍为联系人群组列表。
- `git diff --check` 通过。

### P0110 真机闭环

- 进入群聊证据：`.design-references/contacts-four-tabs-20260802/group-local-navigation/chat.png`；画面直接显示 `new group` 群聊，未出现消息列表中转，底部四 Tab 在详情页隐藏。
- Android 系统返回后的证据：同目录 `back-to-groups.png`；页面恢复为联系人，群组选中且 `new group / 共 2 位成员` 保留。页面左上角返回按钮的独立复验结果位于 `header-back-to-groups.png`，结果一致。
- 真机语义树确认群聊页存在“返回”“打开群聊信息”和输入控件；返回后的语义树同时包含“联系人”、群组选中状态、群组行和底部四 Tab，消息 Tab 未被选中。
- 使用保留数据覆盖安装；包名与版本为 `ai.awiki.awikime.dev` / `0.1.14+25`，`firstInstallTime` 保持 `2026-07-30 15:58:45`，`lastUpdateTime` 为 `2026-08-02 09:56:01`。
- APK SHA-256：`ef809a75fc1c19f535acfabc1ccf9a35e6655c7649147ff9959fc2a9d02bf951`。
- 未发送消息、未更改群成员、未清除 APP 数据；未提交、未推送、未合并、未发布；未使用任何 Superpowers 技能。

final result: passed

---

## 联系人个人资料第 3 版重设计复验（2026-08-02）

> 用户选定 ImageGen 第 3 版“紧凑操作中心”。本轮先以生成图固定视觉方向，再反推 Flutter；没有直接在既有页面上盲改，也没有使用 Superpowers 技能。

### ImageGen 真值与实现对照

- 选定稿：`.design-references/peer-profile-redesign-20260802/imagegen/03-compact-action-center.png`，原始像素 `853 × 1844`，设计目标视口 `390 × 844`。页面采用居中头像/姓名/Handle、轻量状态标签、并排小按钮、全宽扁平详情行和低强调底部删除动作。
- Flutter 视觉基线：`docs/ui-optimization-plan/screenshots/09e-compact-contact-profile.png`，视口 `393 × 852 @1x`。ImageGen 与 Flutter 同画面对照：`.design-references/peer-profile-redesign-20260802/qa/01-imagegen-vs-flutter.png`。
- P0110 最终截图：`.design-references/peer-profile-redesign-20260802/device/route-back-profile.png`，原生视口 `1264 × 2800 / 560dpi`。全页对照为 `.design-references/peer-profile-redesign-20260802/qa/02-imagegen-vs-p0110.png`，头像、标题、状态与操作区聚焦对照为同目录 `03-hero-actions-focused.png`。
- P0110 使用真实长 Handle 时姓名在当前字体度量下完整保持一行；ImageGen 参考图为两行。两者都居中且没有溢出、裁切或挤压操作按钮，属于实时内容与设备字体度量差异，不是布局偏差。

### 版式、尺寸与功能

- “发消息”“关注”和“删除本地聊天记录”基础字号均为 `16`；前两个按钮视觉高度 `40dp`、点击高度 `48dp`，并排居中。删除动作同样使用 `40dp` 视觉高度与 `48dp` 点击高度。
- 头像在紧凑布局为 `60 × 60dp`；DID、主页、身份卡改为连续全宽详情行，保留复制 DID、打开主页、Markdown 身份资料与真实空态“暂无资料”。没有新增大卡片、重阴影、渐变或装饰性图层。
- P0110 语义边界确认“发消息”为 `[326,1075][620,1243]`、“关注”为 `[658,1075][938,1243]`、删除动作为 `[115,2472][1149,2640]`；按钮间距稳定，底部危险操作没有遮挡系统手势区。
- 真机验证“发消息”能进入既有 canonical 单聊且没有发送内容；巡检发现原实现返回后会跳到消息 Tab，现已改为保留联系人工作区页面栈，Android 系统返回恢复当前个人资料页。关注和删除会改变业务状态，本轮未点击。

### 自动化与真机闭环

- `flutter analyze`：No issues found；个人资料、身份流、联系人工作区定向测试共 `40/40` 通过；联系人/资料/设置视觉基线 `1/1` 通过；`git diff --check` 通过。已知 `integration_test plugin was not detected` 仅是该 Widget 视觉测试所在目录的提示，不影响断言结果。
- 使用保留数据覆盖安装；包名与版本为 `ai.awiki.awikime.dev` / `0.1.14+25`，`firstInstallTime` 保持 `2026-07-30 15:58:45`，`lastUpdateTime` 为 `2026-08-02 10:37:06`。
- 最终 APK SHA-256：`d3f13b43e75757c7778c5a063baa46ded7ef31cda266db8b3db3b0d3188f1ea0`。验收结束后 APP 停留在最终个人资料页，便于直接查看。
- 深色模式、最大动态字体、TalkBack/VoiceOver 实际朗读、横屏、其他真机尺寸、iOS 真机与正式签名发布保持 UNVERIFIED。
- 未提交、未推送、未合并、未发布；未使用任何 Superpowers 技能。

final result: passed

---

## 个人资料关注状态一致性修复复验（2026-08-02）

> 本轮是既有控件的状态一致性修复，不改变已确认的版式、字号或组件样式，因此不重新生成 ImageGen 方案。

### 根因与修复

- 联系人“关注”列表使用 `listFollowing`，个人资料页原先只使用单独的 `relationStatus`。P0110 当前数据中，前者确认已关注 newhandle1，后者短暂只返回“关注了我”，导致资料页错误显示“关注”按钮。
- 资料页现在将 `FriendsState.isFollowing(DID)` 作为已关注方向的本地真值，与远端状态合并：`none + following → following`，`follower + following → friend`。因此已关注联系人不会出现可重复点击的“关注”按钮。
- 取消关注完成后会保留对方仍关注我的 `follower` 方向，不会错误降为 `none`；未关注、单向关注、被关注和朋友四种状态继续使用既有按钮与关系标签。

### 自动化与 P0110

- `flutter analyze`：No issues found；个人资料、资料 Provider、联系人 Provider、联系人工作区定向测试 `44/44` 通过；联系人/资料/设置视觉基线 `1/1` 通过；`git diff --check` 通过。
- P0110 “关注”Tab 中 newhandle1 显示“取消关注”；进入资料页后显示“朋友 + 取消关注”，返回列表并再次进入仍保持一致。证据为 `.design-references/peer-profile-redesign-20260802/device/follow-state-list.png`、`follow-state-profile.png` 和 `follow-state-profile-reopen.xml`。
- 真机验收未点击“取消关注”或“关注”，现有关系没有改变；APP 最终停留在 newhandle1 个人资料页。
- 使用保留数据覆盖安装；包名与版本为 `ai.awiki.awikime.dev` / `0.1.14+25`，`firstInstallTime` 保持 `2026-07-30 15:58:45`，`lastUpdateTime` 为 `2026-08-02 11:18:55`。APK SHA-256：`226138b272ae07e46858dfa3f9f57c7683ee4406b344db4b1fe8e5839f645585`。
- 未提交、未推送、未合并、未发布；未使用任何 Superpowers 技能。

final result: passed

---

## 联系人消息按钮返回白屏修复复验（2026-08-02）

> 本轮是既有导航行为修复，不改变联系人、消息列表或聊天页的视觉，因此不重新生成 ImageGen 方案，也不修改 Ardot 视觉真值。

### 根因与修复

- AppShell 使用 Offstage 保留四个底部 Tab；联系人页内层 `NavigatorPopHandler` 在联系人 Tab 不可见时仍参与 Android 系统返回。联系人右侧“消息”切到消息 Tab 的聊天页后，手机返回手势同时弹出了后台联系人内层 Navigator，导致再次切回联系人时内容栈为空，只剩底部导航。
- 联系人内层 `NavigatorPopHandler` 现在只在联系人是当前 Shell 目标时启用；页面脱离 AppShell 独立使用时仍保持原有返回处理。消息按钮、聊天路由、页面布局和返回后的消息列表行为均未改变。
- 新增完整 AppShell 回归用例：联系人 → 右侧“消息” → 聊天页 → Android 系统返回 → 再切联系人，并断言联系人页面、列表和原联系人行全部存在。

### 自动化与范围边界

- `flutter analyze`：No issues found；`tests/unit/friends_workspace_test.dart` 24/24 通过；既有“Android 系统返回从 compact 私聊回到消息列表”用例 1/1 通过；联系人/资料/设置视觉用例 1/1 通过；`git diff --check` 通过。
- 扩大到跨断点导航组合测试时，既有用例“手机四入口与桌面身份 Dialog 在跨断点时保持有效状态”仍在 `profile-display-name` 断言失败，单独运行结果相同。该失败不经过联系人消息按钮或本轮返回处理器，未作为本修复的通过依据，后续独立处理；其余未覆盖平台与场景保持 UNVERIFIED。

### P0110 真机闭环

- 修复前已用冷启动完整复现：联系人 → newhandle1 右侧“消息” → 聊天页 → 左边缘返回手势 → 消息列表 → 联系人，最终只剩底部导航。白屏证据为 `.design-references/peer-profile-redesign-20260802/device/contact-message-bug-cold-after.png`。
- 修复后按同一路径冷启动复验通过：返回手势恢复消息列表，再切联系人时“联系人”、全部/关注/粉丝/群组、newhandle1 与右侧“消息”均存在。最终证据为 `.design-references/peer-profile-redesign-20260802/device/contact-back-fixed-contacts.png` / `.xml`。
- 同一路径额外重复 3 轮，每轮语义树都完整包含联系人标题、四个分类、newhandle1、消息按钮和底部四 Tab，没有再次白屏；APP 最终停留在联系人“全部”页，便于直接查看。
- 使用保留数据覆盖安装；包名与版本为 `ai.awiki.awikime.dev` / `0.1.14+25`，`firstInstallTime` 保持 `2026-07-30 15:58:45`，`lastUpdateTime` 为 `2026-08-02 11:33:42`。APK SHA-256：`b6d2a9554574605052becc9773402a3154447d64bf1715438c0b4551cc3c368c`。
- 未发送消息、未更改联系人关系、未清除 APP 数据；未提交、未推送、未合并、未发布；未使用任何 Superpowers 技能。

final result: passed

---

## “我”页关注 / 粉丝列表入口复验（2026-08-02）

> 本轮只为既有关注、粉丝统计补充导航交互，不改变已确认的头像、文字、分隔线或列表视觉，因此不重新生成 ImageGen 方案，也不修改 Ardot 视觉真值。

### 交互与导航

- “我”页的关注与粉丝统计现在分别打开现有“我关注的”和“关注我的”完整列表；两个入口使用独立稳定 Key，并向无障碍语义树暴露按钮角色、数量、名称和点击动作。
- 可点击区域扩展为左右各半栏、44dp 高；统计文字和 30dp 分隔线仍保持原坐标，DID / 主页 / 身份卡 / 设置区域没有位移。
- 列表属于“我”工作区自己的内层导航栈，不切换到联系人 Tab。详情页显示时隐藏底部四 Tab；Android 返回手势或列表左上角返回都会恢复“我”页及底部 Tab。
- 内层返回处理器只在“我”Tab 激活且列表已打开时启用，避免不可见的保留页面响应其他 Tab 的系统返回。

### 自动化与 P0110

- `flutter analyze`：No issues found；个人页完整测试 14/14 通过；联系人工作区 24/24 通过；联系人/个人页/设置视觉基线 1/1 通过；`git diff --check` 通过。
- P0110 冷启动后，“1 关注”和“1 粉丝”的语义边界分别为 `[56,1138][630,1292]` 与 `[634,1138][1208,1292]`，均为可点击节点；入口页证据为 `.design-references/peer-profile-redesign-20260802/device/profile-relationship-final-overview.png` / `.xml`。
- 关注入口打开“我关注的”并显示 newhandle1，证据为同目录 `profile-relationship-following.png`；左边缘返回手势恢复“我”页。粉丝入口打开“关注我的”并显示 newhandle1，证据为 `profile-relationship-followers.png`；左上角返回恢复“我”页，最终证据为 `profile-relationship-final-return.png`。
- 未点击“关注”或“取消关注”，没有改变关系数据；APP 最终停留在“我”页。深色模式、最大动态字体、TalkBack 实际朗读、横屏、其他 Android 尺寸、iOS 真机与正式签名发布保持 UNVERIFIED。
- 使用保留数据覆盖安装；包名与版本为 `ai.awiki.awikime.dev` / `0.1.14+25`，`firstInstallTime` 保持 `2026-07-30 15:58:45`，`lastUpdateTime` 为 `2026-08-02 11:52:08`。APK SHA-256：`d277c742926025d77b79c4d558ee6146cc4d8b8c54ce44df4a81eae581a2010d`。
- 未提交、未推送、未合并、未发布；未使用任何 Superpowers 技能。

final result: passed

---

## 冷启动开屏与会话恢复连续性复验（2026-08-02）

> 本轮针对“强杀后台后先闪登录页、再进入消息页”的冷启动割裂感：先用内置 ImageGen 固定开屏方向，再按真实会话恢复状态实现路由门禁。未使用 Superpowers 技能。

### ImageGen 真值与实现

- 内置 ImageGen 选定稿：`.design-references/splash-redesign-20260802/imagegen/01-runtime-gated-splash.png`，SHA-256 为 `051dd09b167728e9adf61cbcab65f481dab5ac02cd4541b0960a98a666b50900`。最终提示方向为：393 × 852 的 AWiki Me 移动端开屏，淡冷蓝白背景，使用仓库正式 Logo，保留“连接你的 Agent 世界”与三项能力文案，底部使用轻量加载线；不出现手机边框、黑色四角、按钮或“点击继续”。
- Flutter 复用同一开屏组件覆盖租户启动、数据升级与会话恢复三个初始化阶段，避免原来的 Spinner、登录页和主界面在冷启动期间连续跳变。
- 开屏使用 Safe Area、可滚动紧凑布局、系统栏同色背景、加载语义和 `disableAnimations` 降级；进度动画只表示真实初始化，不设置固定 2.5 秒或 2.8 秒等待，不人为拖慢启动。

### 根因与路由修复

- `AppShell` 原先只判断 `session.isLoggedIn`。冷启动第一帧中 `AppRuntimeState.isInitialized == false` 且会话尚未异步恢复，因此错误地把“暂时还没有会话”当成“确认未登录”，先渲染了登录页。
- 现在先以 `runtime.isInitialized` 为门禁：未完成恢复时只显示开屏；恢复到已保存会话后直接进入消息工作区；恢复完成且确实无会话时才显示登录页。
- 主动退出登录发生在运行时已经初始化之后，因此仍会立即回到登录页，不会被开屏遮住。

### 自动化与范围边界

- 新增 5 个开屏定向用例，覆盖恢复期间不显示登录页、已保存会话直接进入消息工作区、明确无会话立即显示登录页、正式 Logo/文案/无伪交互，以及横屏、大字体与减少动态效果；连同租户启动状态共 `11/11` 通过。
- 登录页、AppShell 更新状态与实时连接 Toast 回归共 `51/51` 通过；`flutter analyze` 为 `No issues found`；`git diff --check` 通过。
- 审批通道恢复后 Android Debug APK 构建成功，并在 P0110 保留数据覆盖安装；包名与版本为 `ai.awiki.awikime.dev` / `0.1.14+25`，`firstInstallTime` 仍为 `2026-07-30 15:58:45`，`lastUpdateTime` 为 `2026-08-02 12:51:43`。APK SHA-256：`17be095754f4951810fea18a14e14289042db88827c046d2be940fdf600ecedc`。

### P0110 冷启动闭环

- 同步录屏捕获到 `LaunchState: COLD`，首次 `TotalTime: 802ms`。逐帧接续为系统桌面 → Android 原生浅色过渡 → AWiki 新开屏 → 消息列表；160 个录制帧中未出现登录/注册页面。全序列证据为 `.design-references/splash-redesign-20260802/device/cold-start-2.mp4` 与 `cold-start-2-contact-sheet.png`，稳定开屏帧为同目录 `splash-stable.png`，最终消息页为 `final-messages.png` / `.xml`。
- 额外执行两轮强杀后台冷启动，`LaunchState` 均为 `COLD`，`TotalTime` 分别为 `735ms` 与 `730ms`；最终语义树 `repeat-2-final.xml`、`repeat-3-final.xml` 均包含“消息”和“搜索会话”，不包含登录/注册入口。
- 真机最终停留在消息页；既有账号、会话和联系人数据均保留，没有发送消息或改变业务状态。P0110 上本轮明确命名的临时录屏与 XML 已删除，工作树验收证据保留。
- 深色模式、最大动态字体、TalkBack/VoiceOver 实际朗读、其他 Android 尺寸、iOS 真机与正式签名发布保持 **UNVERIFIED**。
- 未提交、未推送、未合并、未发布；未使用任何 Superpowers 技能。

final result: passed

---

## “我”页关注 / 粉丝列表标题 16 号字复验（2026-08-02）

> 用户已明确指定“我关注的”和“关注我的”使用 16 号字，本轮是既有顶栏的精确字号一致性调整，不重新生成 ImageGen 方案，也不改变列表布局或交互。

### 实现与自动化

- `RelationshipListPage` 原先未传标题字号，手机端回退到 `responsive.titleXl = 20`。现在两个列表页统一复用四个主 Tab 的紧凑顶栏 token：`16 / FontWeight.w600 / height 1.25`。
- 新增两个定向断言，分别核对“我关注的”和“关注我的”实际 `TextStyle.fontSize == 16`、`fontWeight == w600`；`tests/unit/profile_page_test.dart` 共 `14/14` 通过。
- `flutter analyze`：No issues found；`git diff --check` 通过。

### P0110 真机

- 保留数据覆盖安装成功；包名与版本为 `ai.awiki.awikime.dev` / `0.1.14+25`，`firstInstallTime` 保持 `2026-07-30 15:58:45`，`lastUpdateTime` 为 `2026-08-02 13:01:38`。APK SHA-256：`46ba363025e0181aa82d42e77dcdfa088dacfd82a3df76e7d198490c72c6f8c1`。
- “我关注的”证据为 `.design-references/profile-relationship-title-20260802/device/following-title-16.png` / `.xml`；“关注我的”证据为同目录 `followers-title-16.png` / `.xml`。两个标题语义区域均为 `[56,189][1208,427]`，居中位置一致。
- 未点击关注、取消关注或联系人行，没有改变业务数据；APP 最终停留在“关注我的”列表，便于直接查看。P0110 上本轮临时 XML 已删除，工作树证据保留。
- 未提交、未推送、未合并、未发布；未使用任何 Superpowers 技能。

final result: passed

---

## 会话详情气泡统一轮廓复验（2026-08-02）

> 本轮针对消息气泡尾部看起来像单独三角形、尾部与圆角矩形相接处残留竖向描边的问题。先使用内置 ImageGen 固定简约、小弧尾的方向，再按真机像素效果实现；未使用 Superpowers 技能。

### ImageGen 真值与实现

- 修改前真机证据为 `.design-references/chat-bubble-refinement-20260802/current-device/chat-current.png`：圆角矩形与独立尾部各自绘制，主体侧边描边仍穿过连接处，形成“矩形 + 三角形”的双轮廓和明显竖边。
- 内置 ImageGen 选定稿为 `.design-references/chat-bubble-refinement-20260802/imagegen/02-compact-unified-contour.png`，SHA-256 为 `dcbb88174e1c4b736b8adbdbe9e816c166a299007f51966090bb7976f85c61d1`。最终提示方向为：保持现有会话布局、头像和配色，只把左右气泡改成短而圆润的小弧尾；气泡主体与尾部必须是一条连续外轮廓，不出现内部竖线、双描边、粘贴感或尖锐长三角。
- Flutter 现在使用单个 `ShapeBorder` 同时定义主体圆角和左右镜像尾部，填充与描边各绘制一次；删除原有独立尾部 Painter 和叠放 Stack。尾部宽 6dp、根部加宽并使用三次贝塞尔曲线与圆润尖端，不再保留主体侧边的内部竖线。
- 文本、图片和文件附件共用同一连续轮廓；尾部占用头像侧内部留白，原有最大宽度、内容间距、附件阴影、消息时间、头像和输入区不变。

### 自动化与 P0110

- 紧凑与展开视觉基线 `1/1` 通过；完整聊天页测试 `111/111` 通过，覆盖左右文本、Markdown、图片、附件、长消息、滚动、发送状态与交互；`flutter analyze` 为 `No issues found`；`git diff --check` 通过。
- P0110 修改后会话详情为 `.design-references/chat-bubble-refinement-20260802/final-device/02-chat-detail.png`，2 倍像素检查为同目录 `03-chat-bubbles-2x.png`。左右短消息与图片消息均只有一条连续外轮廓，尾部连接处无竖线、无第二层圆角矩形边框，左右镜像一致。
- Android 系统返回会恢复消息列表，语义树仍包含“消息”、newhandle1 和会话预览；重新进入会话后标题、112 / 111 消息与输入框均存在。APP 最终停留在 newhandle1 会话详情，便于直接查看。
- 使用保留数据覆盖安装；包名与版本为 `ai.awiki.awikime.dev` / `0.1.14+25`，`firstInstallTime` 保持 `2026-07-30 15:58:45`，`lastUpdateTime` 为 `2026-08-02 13:20:09`。APK SHA-256：`52d2d34aa87a80faf7b20fe9d69444dcea327500d8bceb5205713917a51fbf78`。
- 未发送消息、未改变联系人关系、未清除 APP 数据；P0110 上本轮临时 XML 已删除，工作树截图证据保留。深色模式、最大动态字体、TalkBack 实际朗读、横屏、其他 Android 尺寸、iOS 真机与正式签名发布保持 **UNVERIFIED**。
- 未提交、未推送、未合并、未发布；未使用任何 Superpowers 技能。

final result: passed

---

## 用户信息 16 号顶栏与右侧自己头像导航复验（2026-08-02）

> 本轮是已确认会话界面的精确字号与导航修正，不改变页面视觉方向，因此不重新生成 ImageGen 方案。使用 `ui-ux-pro-max` 复核字号层级、语义标签与可预期返回路径；未使用 Superpowers 技能。

### 实现

- 手机窄屏的“用户信息”顶栏从默认大标题改为统一 `16` 号字 token，保持居中、原返回按钮与原内容布局。
- 会话详情中右侧自己的消息头像现在打开独立“我的信息”页，复用既有我页资料、DID、主页、身份卡和设置内容；不再从手机底部弹出身份弹窗。
- 手机系统返回会恢复原会话详情；桌面端继续使用原有当前身份弹窗，避免改变 macOS 工作区交互。
- 新增“我的信息 / My info”本地化标题，专用于会话中的自己头像入口。

### 自动化与 P0110

- `flutter analyze`：6 个相关文件 `No issues found`；完整聊天页与个人页回归 `126/126` 通过，其中私聊、群聊和智能体会话的右侧自己头像路径 `3/3` 通过；`git diff --check` 通过。
- P0110 冷启动 `LaunchState: COLD`，`TotalTime: 999ms`。右侧自己头像打开“我的信息”，语义边界为 `[520,217][744,287]`；系统返回后会话标题与三点入口均保留。证据为 `.design-references/chat-avatar-self-info-20260802/device/03-my-information.png` / `.xml` 和 `04-back-to-chat.xml`。
- 再点击左侧对方头像，“用户信息”顶栏居中且与 16 号字 token 一致，证据为同目录 `05-user-information-16.png` / `.xml`。
- 保留数据覆盖安装成功；包名与版本为 `ai.awiki.awikime.dev` / `0.1.14+25`，`firstInstallTime` 保持 `2026-07-30 15:58:45`，`lastUpdateTime` 为 `2026-08-02 15:05:15`。最终 APK SHA-256：`afe02f68b5284c03a125d049b4469218f50d6aeb1ec47b94503648dd449603b1`。
- 未发送消息、未改变关注关系、未清除 APP 数据；未提交、未推送、未合并、未发布。深色模式、最大动态字体、TalkBack/VoiceOver 实际朗读、横屏、其他 Android 尺寸、iOS 真机与正式签名发布保持 **UNVERIFIED**。

final result: passed
