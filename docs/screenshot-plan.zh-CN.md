# AWiki Me README 截图计划

[English](screenshot-plan.md) | [简体中文](screenshot-plan.zh-CN.md)

资源目录建议：

```text
docs/assets/readme/
```

## 1. Hero：人与 Agent 的可信对话

- 文件：`awiki-me-hero-conversation.png`
- 推荐尺寸：1600×1000；
- README 位置：首屏价值主张之后；
- 必须展示：左侧导航、会话列表、人与 Agent 的消息流；
- 最好展示：一条任务状态卡或授权请求；
- 不要展示：真实 DID、手机号、内部域名、测试账号和开发调试信息；
- 建议 alt text：`AWiki Me 会话页，左侧是会话列表，右侧展示人与 Agent 的消息、任务状态和授权请求`。

## 2. Agent 控制台

- 文件：`awiki-me-agent-console.png`
- 展示：Agent inventory、Daemon 状态、当前 runtime 或 Agent Inbox；
- 目标：让用户理解 AWiki Me 不只是普通 IM；
- 状态字段应使用稳定、可解释的示例，不展示 token 或内部 RPC payload。

## 3. 身份卡与信任状态

- 文件：`awiki-me-identity-card.png`
- 展示：显示名称、handle、简化 DID、身份验证状态、对象类型和可用操作；
- 可使用 `example.com` 域与 demo DID；
- 不要显示完整敏感身份或真实联系人。

## 4. 群组、Mention 与附件

- 文件：`awiki-me-group-attachment.png`
- 展示：群消息、合法 `@` Mention、图片/文件附件卡；
- 目标：证明群协作和附件是产品能力，而非 README 文字列表；
- 文件名、图片内容和成员名称都使用虚构数据。

## 5. 登录与租户选择（可选）

- 文件：`awiki-me-onboarding.png`
- 展示：登录/注册入口与低强调度的租户切换器；
- 适合放在入门文档，不建议占用 README Hero；
- 如使用 PRD 中旧设计稿，必须先确认与当前实现一致。

## 6. 30 秒演示 GIF（推荐）

- 文件：`awiki-me-first-conversation.gif` 或 WebP；
- 流程：启动 App → 选择身份 → 搜索联系人 → 发送消息 → 收到回复 → 查看 Agent 状态；
- 时长：20–40 秒；
- 不录制安装过程；
- 使用 18px 以上可读字体和稳定窗口尺寸。

## 7. Social Preview

- 文件：`awiki-me-social-preview.png`
- 尺寸：1280×640；
- 元素：AWiki Me 标识、产品截图裁切、短句 `Trusted messaging for people and AI agents`；
- 不要放过多功能点或小字号正文。

## 8. 拍摄前清单

- [ ] 使用当前 release 构建，不使用明显过期设计稿；
- [ ] 创建 demo tenant 和 demo identities；
- [ ] 清理通知、菜单栏和桌面隐私信息；
- [ ] 检查图片中无 token、绝对路径、OTP 和内部域名；
- [ ] 统一主题、窗口尺寸和缩放；
- [ ] PNG/WebP 压缩后文字仍清晰；
- [ ] README alt text 准确描述图片内容。
