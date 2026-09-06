# Computer-Use 选择器

优先点「可见文案」。`e2e-*` 是产品代码里的 semantics identifier，accessibility 树能读到时一并核对。文案来自 `lib/l10n/app_zh.arb`。

## 窗口

| 角色 | 窗口标题 | Bundle ID |
| --- | --- | --- |
| App A / Admin | `AWikiMe (Development)` | `ai.awiki.awikime.dev` |
| App B / Joiner | `AWikiMe Joiner` | `ai.awiki.awikime.dev.manual.joiner` |

登录页大标题是「登录或注册」。已登录壳左侧有头像和导航轨，semantics `e2e-authenticated`。

## 登录 / 注册

| 用途 | 可见文案 | Semantics / Key |
| --- | --- | --- |
| 页标题 | 登录或注册 | |
| 提示 | 手机号会自动判断登录已有 Handle 或注册新 Handle | |
| 手机号 | 手机号 / 输入手机号，左侧前缀 `+86` | `e2e-phone-input` |
| Handle | 账号用户名 / 用户名 handle | `e2e-handle-input` |
| 验证码 | 验证码 / 输入验证码 | `e2e-otp-input` |
| 发码 | 发送验证码；冷却中为「重新发送（Ns）」 | `e2e-send-otp-button` |
| 提交 | 登录/注册 | `e2e-complete-login-button`（移动布局）；macOS 主按钮文案是「登录/注册」 |
| 已有 Handle | 这个 Handle 已经存在 | |
| 加入已有账户 | 将此设备加入已有账户 | |
| 恢复 | 恢复 Handle | |
| 取消 | 取消 | |

邮箱路径本目录第一版不用。

## 主壳导航

桌面左侧轨，中文系统文案：

| 用途 | 可见文案 | Semantics / Key |
| --- | --- | --- |
| 消息 | 消息 | `e2e-messages-tab` / `desktop-rail-messages` |
| 智能体 | 智能体 | `e2e-agents-tab` / `desktop-rail-agents` |
| 联系人 | 联系人 | `e2e-contacts-tab` / `desktop-rail-contacts` |
| 任务 | 任务 | `desktop-rail-tasks` |
| 工作台 | 工作台 | `desktop-rail-workbench` |
| 设置 | 设置 | `e2e-settings-tab` / `desktop-rail-settings` |
| 头像 | 左上头像 | `mac-me-rail-avatar` |
| 退出当前测试身份 | 设置 → 退出登录 → 确认退出 | `settings-logout-row` |

第一版只要求消息 / 智能体 / 联系人 / 设置可切换。任务和工作台点开不崩溃即可，不作为独立用例。

## 更多操作

入口是顶栏加号，semanticsLabel「更多操作」。

| 用途 | 可见文案 | Semantics / Key |
| --- | --- | --- |
| 菜单入口 | 更多操作 | `e2e-quick-actions-button` / `shell-quick-actions-button` |
| 发单聊 | 发起新消息 | `e2e-start-conversation-menu-item` / `quick-action-start-conversation` |
| 建群 | 创建群聊 | `quick-action-create-group` |
| 加群 | 加入群聊 | `quick-action-join-group` |
| 关注 | 关注联系人 | `quick-action-follow-contact` |

macOS 消息页也可能出现 `conversation-quick-actions-button`。两个入口菜单内容相同，点到其中一个即可。

## 身份查找

「发起新消息」「关注联系人」「添加群成员」共用查找框。

| 用途 | 可见文案 | Semantics / Key |
| --- | --- | --- |
| 输入 | 输入 @handle / DID / Agent 地址 | `e2e-identity-lookup-input` / `identity-lookup-input` |
| 搜索 | 匹配身份 | `e2e-identity-lookup-search-button` / `identity-lookup-search-button` |
| 开始聊天 | 开始聊天 | `e2e-identity-start-chat-button` / `identity-start-chat-button` |
| 关注 | 关注 | `e2e-identity-add-contact-button` / `identity-add-contact-button` |
| 加群成员 | 添加 | `e2e-identity-add-group-member-button` / `identity-add-group-member-button` |
| 预览名 | 解析成功后的主显示名 | `identity-preview-display-name` |

输入 Handle 时不要带 `@`，也不要手写 `did:`。对方 Handle 用本地部分，例如 `cub09051132`。

## 聊天

| 用途 | 可见文案 | Semantics / Key |
| --- | --- | --- |
| 输入框 | 输入消息... | `e2e-chat-input` / `chat-composer-input` |
| 发送 | 发送按钮（纸飞机/发送图标） | `e2e-chat-send-button` |
| 返回 | 返回 | `e2e-chat-back-button` |
| 会话信息 | 会话信息入口 | `e2e-chat-information-button` |
| 添加群成员 | 聊天顶栏加人 | `e2e-chat-header-add-group-member-button` / `chat-header-add-group-member-button` |

会话列表行按 acceptance.md 的昵称／完整 Handle 基线识别，群按本次群名识别；不能因名字相近就当成同一对象。未读数字出现在行右侧或消息 Tab 角标。

## 联系人 / 群

| 用途 | 可见文案 | Semantics / Key |
| --- | --- | --- |
| 联系人页 | 联系人 | `friends-list-surface` |
| 群组入口行 | 群组 / 我加入的全部群聊 | `friends-groups-row` |
| 群列表 | 群聊列表 | |
| 创建群对话框 | 创建群聊 | |
| 群名 | 名称 / 输入群聊名称 | `e2e-create-group-name-input` / `create-group-name-input` |
| 提交建群 | 创建 | `e2e-create-group-submit-button` / `create-group-submit-button` |
| 关注成功 | 已关注 | |

联系人行标题在昵称已知时必须是当前昵称，无昵称时才按规则回退完整 Handle；点行后核对资料对应的完整 Handle。点行应打开资料或会话；「发消息」文案是 `发消息`。

## 名称编辑与本地身份切换

| 用途 | 可见文案／操作 | Semantics / Key |
| --- | --- | --- |
| 编辑自己的昵称 | 左上头像 → 个人资料 → 编辑个人资料 | Key `profile-edit-button`；宽布局对话框 Key `profile-edit-dialog` |
| 昵称字段 | 昵称 / 输入昵称 | |
| 保存资料 | 保存 | |
| 刷新对端名称 | 打开该联系人的资料页，核对完整 Handle | |
| 本地已有身份入口 | 退出当前账号后，登录页的「切换身份」区域 | Key `onboarding-local-credential-section` |
| 选择原 App B 或 H | 点击完整 Handle 对应的身份行 | `onboarding-local-credential-select:<credentialName>`；动态后缀仅作定位，不当作公共昵称 |

身份切换使用已保存凭证，不点删除按钮、不重新发注册 OTP。切换成功后先核对当前完整 Handle，再收发消息；看到旧身份内容混入当前列表、聊天标题或草稿应记录失败。

## 智能体 / Daemon

| 用途 | 可见文案 | Semantics / Key |
| --- | --- | --- |
| 安装 Daemon | 安装新的 Daemon | `agents-install-daemon-row` |
| 安装对话框 | 到宿主机安装代理 | |
| 复制命令 | 复制安装命令 | |
| 已复制 | 已复制 | |
| Daemon 就绪状态 | 正常 | |

安装命令含 `--token`。复制后到终端执行，不要把 token 贴回聊天或报告。

## 加入设备

| 用途 | 可见文案 | Semantics / Key |
| --- | --- | --- |
| 打开本次新设备请求 | 确认新设备 → 查看并验证 | `device-join-request-entry` |
| 等待 | 等待管理设备响应 | |
| Joiner 六位码 | 六位数字，无固定标题要求 | Key `device-join-sas` |
| 管理端六位码 | 六位数字，无固定标题要求 | Key `device-approval-sas` |
| 开始验证 | 开始验证 | `multi-device-start-verification` |
| 确认一致 | 我已确认两台设备的 6 位验证码一致 | `device-sas-confirmation` |
| 授权 | 确认并授权 | `multi-device-approve` |
| 不一致 | 验证码不一致 | |
| 拒绝 | 拒绝请求 | |
| 成功 | 设备已加入 | |
| 用户在场失败 | 未完成系统身份确认，设备未获授权 | |
| 普通设备角色 | 普通设备 | |
| 管理设备角色 | 管理设备 | |
| 拒绝结果 | 设备请求已拒绝 / 设备关联已取消 | |

从统一登录页选择「将此设备加入已有账户」时已发起 Join，进入进度页后不再点「开始关联」。先去 App A 打开请求并点「开始验证」，握手后才等待两端六位码。表中的 Flutter Key 用于源码定位，不保证出现在 accessibility 树中。

两端 SAS 必须肉眼一致后再勾选，只记录比较结果，不保存数字。系统弹出 Touch ID / 密码且没有真人完成认证时，computer-use 记 `blocked`，不要点「取消」后当成通过。

## Handle Recovery（必测重点）

| 用途 | 可见文案 | Semantics / Key |
| --- | --- | --- |
| 已登录入口 | 设置 → 恢复 Handle DID | Key `settings-recover-handle-did-row` |
| 登录页入口 | 这个 Handle 已经存在 → 恢复 Handle | Key `existing-handle-recovery-action` |
| 恢复页面 | 恢复 Handle | Key `handle-recovery-page` |
| 只读目标 | 完整 Handle | Key `handle-recovery-handle` |
| 设置恢复手机号 | 已绑定手机号；填写完整 E.164，框内无固定 `+86` | `handle-recovery-phone-input` |
| 登录页恢复手机号 | 已绑定手机号；只读沿用登录页验证结果 | Key `handle-recovery-phone` |
| 恢复验证码 | 短信验证码 | Key `handle-recovery-otp` |
| 专用发码 | 发送验证码 / 重新发送（Ns） | `handle-recovery-send-otp` |
| 验证资格 | 验证恢复资格 | `handle-recovery-verify` |
| 不可逆说明 | 此恢复不可撤销。 | |
| 风险确认 | 我已了解以上影响 | Key `handle-recovery-risk-confirmation` |
| 提交 | 确认并恢复 | `handle-recovery-activate` |
| 同一操作续跑 | 继续恢复 | `handle-recovery-resume` |
| 已完成但会话未激活 | 继续进入消息 | `handle-recovery-enter-messages` |
| 旧设备失效 | 账号登录状态已失效 | |
| 现场比较身份 | 个人资料 → DID；窄布局可展开 DID 行 | |

设置入口保留当前登录和本地数据；登录页入口沿用已验证 Handle/手机号并单独请求恢复 OTP。两条入口的手机号输入方式不能混用。比较 DID 时仅在现场确认保留／变化，不把完整值写入报告。

出现未知结果或可继续状态时保留当前恢复页，按 playbook 的有界续跑规则处理；「开始新的恢复」和「隔离密钥不可用的操作」不是本套测试的重试按钮。
