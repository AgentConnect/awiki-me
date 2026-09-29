# 2026-09-28 Android 升级与对方资料展示修复

## Android 升级

固定来源的 flutter_secure_storage 10.3.1 runtime 收入 third_party，Java 运行时仅四处
备份迁移 preferences 名称改为有效 namespace。原实现创建新的 namespace 时会误删旧
全局 wrapped AES key，从而出现旧密文仍在、解密失败的 BAD_DECRYPT。

对已损坏安装，仅允许明确列出的可重建 App 状态在读取旧 namespace 的指定解密错误时
视为缺失，回到身份选择并让正常登录重新保存选择。目标 namespace 的错误、未知 key、
Scope 根密钥、vault、凭据、写入失败均继续失败关闭。不删除旧密文、不重建根密钥，
不绕过身份或鉴权检查，不清除聊天记录。iOS/macOS/Windows 平台实现没有变更。

## 对方名称与聊天入口

Core PR https://github.com/AgentConnect/awiki-cli-rs2/pull/53 修复公共 Profile 混入
当前账号 Handle 的根因，并保留通过校验的外域 WNS 展示资料。
App 校验目录身份与嵌套 Profile 的一致性，缺少昵称保持空值，由统一显示规则回退。
进入会话只传递原始 Profile，不把格式化后的短 Handle/标题存为昵称。资料入口使用
已知 DID 向 Core 解析 canonical 会话，展示 Handle 不得改变操作对象。
既有 canonical ID、Persona、消息、会话记录和账号切换围栏保持原所有权。

## 已执行验证

- 8 个相关 Dart 测试文件合计 133 项通过，包含 Android 旧值/新值/Scope/登录失败边界、
  身份匹配、进入会话、资料冲突、无昵称及账号切换。
- 资料页的 9 个 widget 用例通过；发消息与删除入口 fixture 同步为按 DID 解析。
- 原有资料 Provider 3 项及 Agent 页面 53 项通过；初跑中两项资料页旧 fixture 只提供
  Handle 对应 canonical ID，按新入口合同调整 fixture 后定向重跑通过。
- 8 个改动文件 focused analyze 无问题；补充文件分析结果见 PR。
- App smoke `AwikiMeApp start conversation stays in recents before first send` 通过：
  完整 App + fake 服务，核对匹配结果的昵称、完整 Handle、聊天标题及首条消息前的会话。
  本轮通过 Flutter tester 执行，非真实 macOS 原生/跨域投递验收。
- 新增两个展示回归在旧 App 实现上均失败；Core 的 4 个新增回归亦在旧实现失败。
- Android 16 独立原生 fixture 已完成 9.2.4 → 修正版，以及 9.2.4 → 未修 10.3.1
  损坏 → 修正版两条路径，均包含冷启动；旧密文摘要、Scope envelope 和可用选择持久化
  均通过。正式签名的 0.1.35 → 0.1.36+47 覆盖安装及冷启动 smoke 通过。
- System 跨域编排/恢复合同 13 项通过；Core 的 Profile 42、Directory 27、HTTP 28 项通过。

## 审查、依赖与待验

安全审查核对了秘密与辅助状态的边界、目标存储读取/写入失败、Scope/vault 拒绝、
跨账号资料、合法重名、Profile/目录冲突及 SessionEpoch。不存在清库、绕过鉴权或
显示字段建立 canonical 身份的替代路径。

Core 的固定源码清单与联调锁随配套 PR 提供，用于可复现 review 构建；不将本地相邻源码
冒充已发布 SDK。正式构建需要先发布修复版 Core 并更新 registry pin，不能复用旧 native。
当前桌面上的 Android 0.1.36+47 包只包含前一项 Android 修复，不包含本轮新增名称修复。
尚未收到用户真机覆盖安装登录的验收结果；也尚未用包含两项修复的新客户端进行真实跨域
账号匹配、刷新与投递验收。本次没有重新打包、发布、修改生产服务或已安装 App 数据，
也没有触发 hosted CI。原生 Android 的生物识别迁移分支随 namespace 一致修正，但当前
产品不使用该分支，未宣称已进行生物识别设备验收。

## 统一 review 整合

原 App #46 的两个修复提交完整合入发布 PR #45；此前上海版本配置继续保留，Android
存储实现、身份展示实现、测试及 vendor 文件均与原修复 PR 一致。Core 对应最终入口为
https://github.com/AgentConnect/awiki-cli-rs2/pull/52；按其中提交的 `dependencies.source.json`
与锁做源码联调，不再以旧 #53 作为独立待合并入口。

本次只整合待审源码，不重发 0.1.35 安装包。后续正式构建应递增产品版本，并先发布修复
Core、更新 registry pin 和原生 SDK；未完成的真机覆盖安装与真实跨域消息验收继续保留。
合并后重新验证的命令、结果与最终 SHA 记录在 awiki-plan 的统一审查清单。
