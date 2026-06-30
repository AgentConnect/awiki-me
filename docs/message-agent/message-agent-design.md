# Message Agent MVP 优化方案

## 背景

Message Agent 是用户授权后，帮助 Human App DID 处理 IM 消息的独立 Agent。它运行在用户选择的 daemon 中，但不等同于 daemon，也不直接使用 daemon DID 作为消息处理身份。

本文沉淀 Message Agent 的 MVP 版本方案。MVP 的目标是尽快上线并跑通端到端闭环：Human App 发起启用，daemon 创建并运行消息处理 Agent，user-service 记录 owner 与 binding，message Agent 接入 Human DID 的消息流，对会话消息进行分析、总结、草稿生成和 App action 请求，并把处理结果回收到 Human App。

本轮 MVP 做三个重要收口：

- message Agent 可以处理所有会话，不再要求用户逐个手动开启会话。
- MVP 先不开放 message Agent 代发消息，也不承诺自动回复。
- bootstrap / delegated key 传输安全纳入本次 MVP，不能继续以 `secure:false` 普通 payload 传递敏感授权材料。
- 当前只支持 Hermes 作为消息处理运行引擎，但产品和数据模型需要预留未来支持 Codex、Claude Code 或其他 runtime provider。

## MVP 方案摘要

MVP 每一项方案先按以下口径收口：

- 入口：提供独立 Message Agent 设置页，创建 Agent 流程只作为可选入口。
- 开关：`AWIKI_AGENT_IM_ENABLED` 默认开启；显式设置为 `false` 时隐藏入口或显示实验功能关闭，不暴露半成品流程。
- daemon 选择：用户先选择运行 daemon，App 展示 daemon 在线状态、版本和可用能力。
- 运行引擎：MVP 只启用 Hermes Message Agent，但模型中保留 `runtime_provider`，未来可扩展 Codex、Claude Code。
- 身份模型：Human DID 是用户身份，Daemon Agent DID 是运行环境，Message Agent DID 是 daemon 内独立 runtime agent。
- delegated key：message Agent 使用 Human DID 下的 delegated key 接入 Human DID 消息流，Human App 不持有 Agent 私钥。
- 安全 bootstrap：delegated private package、bootstrap secret 和 WSS credential 必须通过安全 envelope 或等价安全通道传递。
- binding：user-service 记录 Human owner、daemon、Message Agent、delegated key 和 active binding。
- 消息路由：message Agent 使用 Human delegated key 建立 message-service WSS，接收 Human DID 的消息流。
- 处理范围：MVP 默认处理所有可处理会话，不做逐会话开启、白名单、黑名单或规则路由。
- 处理能力：MVP 做分析、总结、草稿生成和 App action 请求，不开放自动回复或代发。
- App 回收：`message.sync`、`runtime_final`、`app.action.requires_confirmation` 必须回收到 App。
- 用户确认：Human 确认后的发送由 Human App 现有发送链路完成，并回传 `awiki.app.action.result.v1`。
- IM 展示：绑定成功可以显示为一条 IM 消息，但授权事实来自 binding handshake。
- 停用删除：停用先停 binding 和处理 loop，删除 Message Agent 前必须先解除 active binding。
- 授权撤销：预留 delegated key revoke / DID Document 移除入口，不能把停用误描述为永久撤销 key。
- 技术债：协议级 `from: Agent DID`、`on_behalf_of: Human DID`、双 proof 和跨域 delegation 验证后续补齐。

## 核心产品规则

Message Agent 涉及四类身份和一个 delegated key：

```text
Human DID = 用户的人类身份，也是 Human App 登录和 IM 消息归属身份
Daemon Agent DID = 某台本机或远端 daemon 的运行环境身份
Runtime Agent DID = daemon 内创建的具体 Agent 身份
Message Agent DID = 被绑定为消息处理 Agent 的 Runtime Agent DID
user_did#daemon-key-1 = Human DID 授权 daemon 读取普通 inbox / 建立 delegated WSS 的 delegated key
```

UI 命名必须避免混用：

- daemon 在产品上称为「设备 Daemon」或「运行 Daemon」。
- message Agent 在产品上称为「消息处理 Agent」。
- 不把 daemon 叫成消息 Agent，也不把消息处理 Agent 的 DID 和 daemon DID 混在一起。

长期推荐关系是：

```text
Human DID
  授权
Message Agent DID
  运行在
Daemon Agent DID
```

MVP 里，message Agent 仍然有独立 `Message Agent DID`，但消息接入链路为了复用当前 message-service 能力，会使用 Human DID 下的 delegated key 建立 WSS 连接。这个 delegated key 只能作为 Human DID 的授权接入凭据使用，不应被产品解释为 daemon 或 Agent 的独立消息身份。

## MVP 目标

MVP 第一版以可上线、可观察、可停用为目标，而不是一次性补齐完整代理身份协议。

需要跑通的用户可见结果：

- 用户可以从明确的 Message Agent 设置入口启用能力。
- 用户可以选择一个 daemon 来运行消息处理 Agent。
- daemon 内创建并运行一个独立的 Message Agent。
- user-service 记录 Human owner、daemon、message Agent 和 binding。
- message Agent 使用 Human delegated key 接入 message-service WSS。
- message Agent 默认处理 Human DID 消息流里的所有可处理会话。
- message Agent 不直接代发消息，只生成分析、总结、草稿或 App action 请求。
- Human App 能展示 Agent 处理状态、结果摘要、草稿和需要确认的 action。
- 用户可以停用或删除 Message Agent，并停止消息处理链路。
- bootstrap / delegated key 敏感材料必须通过安全通道或加密 envelope 传递。

MVP 不追求：

- 多个 active message Agent 并存。
- 按联系人、群聊、规则路由到不同 Agent。
- Agent 协议级 `from: Agent DID` / `on_behalf_of: Human DID` 双 proof。
- 跨域可独立验证的 `delegation_proof`。
- message Agent 自动回复或无确认代发。
- E2EE 明文处理能力。

## 产品入口

MVP 应提供明确的 Message Agent 设置页，而不是把入口隐藏在普通 Agent 列表里。

推荐入口：

```text
Settings / Message Agent
```

设置页展示：

- 当前是否已启用 Message Agent。
- 当前绑定的 daemon。
- 当前消息处理 Agent。
- 当前运行引擎 / runtime provider。
- daemon 在线状态、版本、能力。
- delegated key / bootstrap 安全状态。
- Agent 处理范围。
- 最近处理状态或错误。
- 停用、删除、重新连接等操作。

当前实现状态（2026-06-30）：

- App Settings 已提供 `Message Agent` 稳定入口，进入独立的「消息处理 Agent」设置页。
- Agents tab 的 daemon detail 只提供「配置消息处理 Agent」摘要跳转卡，不再暴露旧的内嵌生命周期管理面板。
- 独立设置页展示运行 daemon、Hermes runtime provider、普通 `direct text` 处理范围、安全 bootstrap 公钥状态、授权状态和权限摘要。
- 启用按钮仅在 `AWIKI_AGENT_IM_ENABLED=true`、daemon ready 且 daemon 已上报 bootstrap public key 时可用；缺 key 或 daemon 未就绪时提示刷新 daemon 状态。
- 页面文案必须持续强调「只生成草稿，发送前需用户确认」「不会自动发送消息」「不处理 E2EE 明文」。

创建 Agent 流程可以保留「作为消息处理 Agent」的选项，但它不是唯一入口。两个入口最终进入同一套启用流程。

如果 `AWIKI_AGENT_IM_ENABLED=false`：

- UI 应隐藏 Message Agent 设置入口，或只显示「实验功能未开启」。
- 当前产品 UI 在 Settings 显示「实验功能未开启」，且 Agents/daemon detail 不展示可触发生命周期请求的管理按钮。
- 不展示半成品创建、绑定、配置入口。
- 不能让用户进入会失败或不可完成的流程。

## MVP 启用流程

MVP 推荐启用流程：

```text
进入 Message Agent 设置页
  -> 选择 daemon
  -> 展示 daemon 在线状态 / 版本 / 可用能力
  -> 选择或创建 Hermes Message Agent
  -> 展示处理范围：所有会话
  -> 展示权限摘要和安全说明
  -> 建立安全 bootstrap / delegated key 通道
  -> daemon 创建并持有 Agent runtime identity
  -> user-service 记录 owner + daemon + message-agent binding
  -> daemon 启动 message Agent runtime
  -> message Agent 使用 Human delegated key 连接 message-service WSS
  -> binding handshake 完成
  -> Human App 中展示绑定成功 IM 消息
```

启用时可以复用现有 `bootstrapMessageAgent`，但它必须满足本方案的安全要求：

- bootstrap 中不得以 `secure:false` 普通 payload 传递 delegated private package。
- delegated key 私钥不应进入 user-service。
- delegated key 私钥不应通过明文 App 消息传给 daemon。
- 如果存在必须传递的敏感材料，必须放进 daemon 公钥加密的 envelope。

MVP 中运行引擎固定为 Hermes，但启用流程不要把概念写死为「只能有 Hermes」。推荐在内部模型中保留：

```text
runtime_provider = hermes
runtime_profile = message_agent
```

未来可以扩展：

```text
runtime_provider = codex
runtime_provider = claude_code
```

MVP UI 可以只展示 Hermes 一个选项，或者直接默认选择 Hermes；但数据结构、binding 记录、daemon capability 上报和日志中应保留 provider 字段，避免后续接入 Codex / Claude Code 时迁移历史 binding。

## 身份与 Key 决策

已确认的身份与 key 决策：

- Human App 发起 Message Agent 创建和绑定流程。
- 如果 daemon 下已存在可识别的 Hermes Message Agent runtime，Human App 应复用该 runtime 并补齐/激活 user-service binding，不应重复签发 runtime registration token。
- daemon 负责生成并持有 Agent runtime identity。
- Message Agent 有独立 `Runtime Agent DID`。
- daemon DID 不作为处理消息的 Agent。
- user-service 记录 owner 和 message-agent binding。
- Human App 不直接持有 Agent 私钥。
- Human App 不导出 Agent 私钥。
- message Agent 通过 Human DID 下的 delegated key 接入 Human DID 的消息流。

推荐 delegated key 生成与注册方式：

```text
daemon 本地生成 delegated key pair
  -> daemon 只把 public key / key id / capability 请求交给 Human App
  -> Human App 确认授权
  -> Human App / user-service 将 public key 注册到 Human DID Document 或 delegated key registry
  -> delegated private key 保留在 daemon 本地
```

如果受当前实现限制，MVP 仍需要由 App 侧生成 delegated key，则必须通过安全 envelope 传递私钥材料：

```text
Human App 生成 delegated key pair
  -> Human App 使用 daemon bootstrap public key 加密 private package
  -> daemon 解密并本地保存
  -> user-service 只接收 public registration，不接收 private material
```

长期更推荐 daemon 本地生成 delegated key，避免 delegated private key 跨设备传输。

## 安全 Bootstrap 与 Delegated Key 传输

本次 MVP 必须支持安全传输，不能把该问题继续留到后续。

最低要求：

- daemon 在 pairing / bootstrap 前提供可验证的 bootstrap public key。
- Human App 在向 daemon 发送敏感 bootstrap payload 前，必须验证目标 daemon 身份和 key id。
- delegated private package、runtime bootstrap secret、WSS credential 等敏感材料必须使用 daemon public key 加密。
- 加密 envelope 必须绑定目标 daemon DID、Human DID、operation id、创建时间和过期时间。
- bootstrap token / pairing token 必须短期有效，并且只能使用一次。
- user-service 只能记录 public key、binding、状态和审计信息，不接收 delegated private key。
- 日志、错误、analytics 和 App UI 不得输出 private key、token、bootstrap secret 或完整加密明文。

推荐 envelope 语义：

```text
recipient: Daemon Agent DID
recipient_key_id: daemon bootstrap key id
sender: Human DID
operation: message_agent.bootstrap
expires_at: short ttl
ciphertext: encrypted delegated package / bootstrap secret
aad: human_did + daemon_did + operation_id + message_agent_binding_id
```

MVP 实施契约采用两个层次，当前落地方案已经使用 daemon `#key-3`
X25519 bootstrap public key 构造外层加密 envelope：

```text
awiki.daemon.bootstrap.secure.v1 = App 发给 daemon 的外层安全 envelope
awiki.daemon.bootstrap.v1 = daemon 解密后的内部 bootstrap payload
```

外层 `awiki.daemon.bootstrap.secure.v1` 必须包含：

- `recipient_daemon_did`
- `recipient_key_id`
- `sender_human_did`
- `operation_id`
- `issued_at`
- `expires_at`
- `nonce`
- `sender_ephemeral_public_key`
- `ciphertext`
- `aad`
- 可选 `payload_sha256`

外层 envelope 的明文字段只能表达路由、收件方、发送方、时效、重放保护、发送方临时公钥和 AAD。`aad` 和其它明文字段不得包含 `private_key_pem`、`private_key_multibase`、bootstrap secret、WSS credential 或其它私密材料。

内部 `awiki.daemon.bootstrap.v1` 只允许作为解密后的 daemon 内部结构继续复用，不再作为生产路径的普通明文 payload 直接发送。Human App 现在发送的是 `awiki.daemon.bootstrap.secure.v1`，其中 `ciphertext` 使用 X25519 shared secret 派生的 ChaCha20-Poly1305 加密；普通 `secure:false` transport 只承载外层 encrypted envelope，不承载 delegated private package 明文。daemon 收到旧明文 `awiki.daemon.bootstrap.v1` 时必须 fail closed，并提示需要 `awiki.daemon.bootstrap.secure.v1`。

安全验收口径：

- 代码中不再出现 message-agent bootstrap private package 通过 `secure:false` 普通 payload 明文发送的路径。
- daemon 不能解密非发给自己的 bootstrap envelope。
- 过期、重复使用、daemon DID 不匹配、key id 不匹配的 bootstrap 请求必须失败。
- 停用或删除后，不再允许使用旧 bootstrap token 重放创建绑定。

## MVP 消息路由

MVP 消息路由采用当前最短闭环：

```text
message Agent runtime
  -> 使用 Human DID delegated key 建立 WSS
  -> message-service 将连接视为 Human DID 的 delegated client
  -> message Agent 接收 Human DID 的消息流
  -> message Agent 对消息进行分析 / 总结 / 草稿生成 / action 判断
  -> message Agent 将处理状态和结果同步回 Human App
```

处理范围：

- MVP 默认可以处理所有会话。
- 不做用户逐会话手动开启。
- 不做联系人白名单 / 黑名单。
- 不做联系人级 Agent 路由。
- 不做群聊级 Agent 路由。

这里的「所有会话」表示：对 Human DID 消息流中 message-service 能通过 delegated WSS / inbox 提供给 message Agent 的所有可处理会话，默认进入处理范围。

MVP 仍需要遵守内容能力边界：

- 普通 `transport-protected` 消息可以进入处理。
- 当前无法解密或无法解释的 E2EE 消息不能承诺明文处理。
- 附件、复杂 payload、群聊事件等如果当前 runtime 不支持，应以 unsupported / skipped 状态同步回 App，而不是静默失败。

## MVP 发送与回复策略

MVP 先不开放 message Agent 代发消息，也不承诺自动回复。

message Agent 可以做：

- 分析消息。
- 总结会话。
- 生成回复草稿。
- 判断是否需要用户确认。
- 发起 `app.action.requires_confirmation`。
- 把处理结果通过 `message.sync` / `runtime_final` 同步回 Human App。

message Agent 不做：

- 不直接调用 outbound send 代替 Human DID 发 IM。
- 不自动回复联系人。
- 不在用户无感知的情况下发送消息。
- 不把 daemon/runtime outbound send 打开成默认能力。
- 默认 delegated key scope 不包含 `message.send.plain`；如果历史数据或测试 fixture 仍出现该 scope，MVP Message Agent bootstrap validation 必须拒绝它或把它视为 legacy 非生产路径。user-service delegated key 默认 scope 应只包含 `message.inbox.read.plain` 和 `message.history.read.plain`。

如果用户确认草稿或 action：

```text
Human App 展示草稿 / action
  -> 用户点击确认
  -> Human App 使用现有 Human DID 正常发送链路发送消息
  -> Human App 将 awiki.app.action.result.v1 回传 daemon
```

这不是 message Agent 代发，而是 Human App 在用户确认后发送。这样可以先跑通处理闭环，同时避免 MVP 里混淆 Agent 发送身份。

长期代发模型仍应升级为：

```text
from: Agent DID
on_behalf_of: Human DID
proof: Agent proof + Human delegation proof
```

## App 回收闭环

App 回收闭环是 MVP P0。没有回收闭环，即使 daemon 已处理消息，用户也无法理解 Agent 做了什么。

MVP 至少需要闭合三类事件：

```text
message.sync
runtime_final
app.action.requires_confirmation / awiki.app.action.result.v1
```

推荐行为：

- `message.sync` 落到聊天视图中的处理状态，或会话级「Agent 已处理」标记。
- `runtime_final` 展示处理结果摘要、分析结论、草稿内容或失败原因。
- `app.action.requires_confirmation` 在 App 中展示确认 / 拒绝 UI。
- 用户确认或拒绝后，App 发送 `awiki.app.action.result.v1` 回 daemon。
- daemon 收到 action result 后更新 runtime 状态，避免重复请求确认。

MVP UI 不需要复杂，但必须让用户看到：

- 哪条消息被 Agent 处理。
- Agent 当前是在处理中、已完成、失败还是等待确认。
- 如果生成草稿，草稿是什么。
- 如果需要确认，用户确认后发生了什么。

## Binding Handshake 与 IM 展示

产品表现上，Message Agent 创建 / 绑定成功后，应在 Human App 中表现为一条 IM 消息，例如：

```text
我是你的消息处理 Agent，已准备好处理消息。
```

这条消息用于让用户感知绑定完成，但底层不能只依赖普通文本消息作为授权事实。

底层必须有明确的 binding handshake：

```text
Human App 确认绑定意图
  -> daemon 准备 secure bootstrap
  -> delegated key 注册 / 更新完成
  -> daemon 启动 message Agent
  -> message Agent 建立 delegated WSS
  -> user-service 记录 active binding
  -> Human App 收到绑定成功状态
  -> IM 中展示绑定成功消息
```

IM 消息是产品展示层；binding handshake 是授权与状态事实来源。

binding 至少应记录：

- Human DID
- Daemon Agent DID
- Message Agent DID
- runtime provider
- runtime profile
- delegated key id
- binding id
- status
- created_at
- activated_at
- disabled_at / revoked_at
- last_seen_at
- error state

## 设置页状态

Message Agent 设置页建议展示以下状态：

```text
未启用
正在连接 daemon
正在安全授权
正在创建消息处理 Agent
正在建立消息连接
已启用
处理中
等待用户确认
已暂停
连接异常
停用中
已停用
```

最小状态机：

```text
not_configured
daemon_selected
secure_bootstrap_pending
agent_starting
wss_connecting
active
paused
error
revoking
revoked
```

用户不需要看到所有内部状态名，但 App 和 daemon 需要能用稳定状态排查问题。

## 停用与删除语义

需要区分四个动作：

```text
暂停处理消息
删除消息处理 Agent
移除此 daemon
撤销读取我消息的授权
```

MVP 第一版至少要支持：

```text
停用 Message Agent
删除 Message Agent
```

停用 Message Agent 表示停止让该 Agent 处理 Human DID 消息。停用后：

- user-service 将 message-agent binding 标记为 disabled / revoked。
- daemon 停止 message Agent 的消息处理 loop。
- daemon 断开或停止使用 delegated WSS 连接。
- Human App 不再展示该 Agent 为 active。
- 后续消息不再进入该 Agent 处理。

删除 Message Agent 表示删除 Agent 本身。如果被删除的 Agent 当前是 Message Agent，需要先停用 binding，再 archive runtime。

撤销读取我消息的授权是更强动作：

- 更新 Human DID Document，移除 `user_did#daemon-key-1`；或
- 调用 delegated key revoke 流程；并
- 让 message-service 后续拒绝该 delegated key 的 inbox / WSS 访问。

由于本轮 MVP 已要求支持 bootstrap / delegated key 安全传输，撤销入口也应至少在产品和后端语义上预留。即使第一版停用默认只停 binding，也不能把它描述成已经完成 DID Document 级永久撤销。

推荐 MVP 按钮：

- 「暂停处理消息」：停 binding 和处理 loop。
- 「删除消息处理 Agent」：先停用，再 archive runtime。
- 「撤销 Daemon 消息授权」：撤销 delegated key，影响该 daemon 后续读取消息。

Daemon 本身的「删除代理」入口与 Message Agent 生命周期分开处理：

- 正常已上线 daemon 通过 daemon control payload 执行自删除，避免 App 绕过运行端清理本地状态。
- 如果 daemon 注册后从未完成首个心跳（`status = registering` 且 `last_seen_at = null`），App 允许直接调用 `unbind_agent` 清理这条未完成安装记录；这种记录没有可达 daemon，不能依赖 control payload 删除。

## MVP 范围约束

第一版约束：

- 一个 Human DID 同时只能有一个 active Message Agent。
- 一个 Message Agent 必须绑定一个 daemon 运行。
- Message Agent 必须有独立 Runtime Agent DID。
- MVP 只支持 Hermes runtime provider，但 provider 字段必须预留。
- daemon DID 不能作为 Message Agent DID。
- Human App 不直接持有 Agent 私钥。
- message Agent 使用 Human DID delegated key 接入 message-service WSS。
- message Agent 默认处理所有可处理会话。
- message Agent 不自动回复，不直接代发。
- Human 确认后的发送由 Human App 正常发送链路完成。
- bootstrap / delegated key 敏感材料必须安全传输。
- 创建 / 绑定成功可以表现为 IM 消息，但授权事实必须来自 binding handshake。
- 停用 Message Agent 时必须解除消息代理 binding，并停止处理 loop。
- 第一版可以先支持创建时绑定为 Message Agent，后续再补已有 Agent 设置为 Message Agent。

## 已知技术债与后续演进

MVP 仍有这些技术债：

- WSS 接入身份仍复用 Human DID delegated key，message-service 尚未原生理解 `Agent DID on behalf of Human DID`。
- 当前消息 envelope 不能表达真实处理主体是 Message Agent。
- 对端看不到 `from: Agent DID` / `on_behalf_of: Human DID`。
- 缺少协议级双 proof 和 `delegation_proof`。
- 跨域服务不能独立验证 Human 授权 Agent 的事实和范围。
- delegated key scope 在协议和服务端 enforcement 上还需要继续细化。
- E2EE 明文处理不在 MVP 范围内。
- 处理所有会话可能带来噪音和隐私压力，后续需要联系人、群聊、会话级策略。

后续演进：

- Agent 以自身 `Agent DID` 建立连接和发送消息。
- 消息 envelope 显式记录 `from: Agent DID` 与 `on_behalf_of: Human DID`。
- Human 对 Agent 的授权使用 `delegation_proof` 表达，并支持范围、期限和撤销。
- 发送校验要求 Agent proof 与 Human delegation proof 同时成立。
- user-service 或授权服务提供可跨域验证的 binding / delegation 状态。
- 审计系统记录 Human、Agent、daemon、授权范围、处理时间、action 结果和撤销状态。
- 支持联系人白名单 / 黑名单、群聊策略、会话级策略。
- 支持多个 Message Agent 和规则路由。
- 在清晰授权和确认模型下，再逐步开放受控代发或自动回复。

## MVP 验收标准

MVP 完成时，应能验证：

- `AWIKI_AGENT_IM_ENABLED=false` 时，没有半成品入口。
- 用户能从 Message Agent 设置页完成 daemon 选择、权限摘要确认和启用。
- daemon 在线状态、版本和能力能被展示。
- bootstrap / delegated key 敏感材料不再通过 `secure:false` 普通 payload 发送。
- delegated private key 不进入 user-service。
- daemon 能启动独立 Message Agent runtime，并返回 Message Agent DID。
- user-service 能记录 active binding。
- message Agent 能使用 Human DID delegated key 建立 WSS。
- message Agent 能接收 Human DID 的消息流。
- message Agent 默认处理所有可处理会话。
- message Agent 能把处理状态、结果摘要、草稿或 action 请求回收到 App。
- App 能确认 / 拒绝 action，并把 `awiki.app.action.result.v1` 回传 daemon。
- message Agent 不直接代发 IM 消息。
- 停用后，binding 失效，daemon 停止处理 loop，WSS 不再继续作为 active message Agent 工作。
- 删除 Message Agent 时不会保留 active binding。

## 当前落地状态

截至 2026-06-19，MVP 已按以下仓库切片落地：

- `awiki-me-message-agent`
  - Message Agent 设置能力已在 Agent/daemon 页面完成过接入验证，但当前产品 UI 隐藏 daemon 详情页的 Message Agent 面板；底层 bootstrap、binding、revoke 与 App 回收能力保留。
  - `AWIKI_AGENT_IM_ENABLED` 关闭时阻断 bootstrap action；当前 UI 不再展示半成品入口。
  - App 能从 daemon diagnostics 读取 `bootstrap_key_id`、`bootstrap_public_key_b64u`、`bootstrap_key_algorithm`，并使用 daemon `#key-3` X25519 公钥生成 `awiki.daemon.bootstrap.secure.v1`。
  - App 回收 `awiki.message.sync.v1`、`awiki.app.action.v1`、`awiki.app.action.result.v1`，在聊天中展示处理状态、草稿和确认 / 拒绝 UI；raw JSON 不作为普通消息显示。
  - MVP 只允许 `message.create_draft` 写入草稿；用户确认后的发送仍由 Human App 发送链路负责。
- `awiki-cli-rs2-message-agent`
  - daemon 发布 bootstrap public key diagnostics。
  - daemon 接收 secure bootstrap envelope，校验 recipient、key id、TTL、nonce/replay、payload hash 和 canonical AAD，再解密内部 bootstrap payload。
  - 旧明文 `awiki.daemon.bootstrap.v1` 在 Message Agent bootstrap 路径 fail closed。
  - daemon 处理 delegated inbox 后写入 `message.sync` / `runtime_final` / `app.action` durable outbox。
  - active Message Agent runtime 调用 `msg.send` / `attachment.send` 时会被拒绝，避免 MVP 代发。
- `user-service-message-agent`
  - `/user-service/message-agent/rpc` 成为 owner + daemon + runtime Message Agent binding 的服务端事实源。
  - `ensure_binding` 校验 Human ownership、active daemon、daemon 托管 runtime、`runtime_provider`、active delegated key 和敏感字段拒收。
  - `disable_binding` 只停 binding；`revoke_binding` 要求 delegated key registry 已经 revoked，否则 fail closed。
  - delegated key public registration 默认是 read-only scope：`message.inbox.read.plain`、`message.history.read.plain`；不默认包含 `message.send.plain`。
- `awiki-system-test-message-agent`
  - 新增 Message Agent MVP focused acceptance：App recovery payload classification、user-service binding lifecycle、daemon 明文 bootstrap fail-closed。
  - 当前环境未部署 Message Agent RPC 或未启动本地 message-service 时，系统测试会显式 skip 并输出配置和原因。

## 发布与回滚

发布建议：

- 当前默认构建保留 Message Agent 底层能力，但不展示 daemon 详情页入口；后续独立设置页或灰度入口开放前，无需依赖用户手工点击启用。
- 发布默认开启构建前确认 daemon 版本包含 secure bootstrap、bootstrap public key diagnostics、no-send enforcement 和 App outbox 回收。
- 发布默认开启构建前确认 user-service 已部署 `/user-service/message-agent/rpc`，并且 delegated key 默认 scope 不包含 `message.send.plain`。
- 发布默认开启构建前确认 message-service 能接受 Human DID `#daemon-key-1` 作为当前 DID Document authentication 中的 delegated client。
- 监控 binding 创建失败、bootstrap 解密失败、daemon `mark_seen`、runtime_final outbox retry、action result 回传失败和 delegated WSS 连接失败。

回滚方式：

- 关闭 `AWIKI_AGENT_IM_ENABLED`，App 不再暴露新启用入口。
- 对已启用用户调用 `disable_binding`，daemon 停止 active Message Agent 处理 loop。
- 如需要强回收授权，先提交 signed DID Document update 移除 `user_did#daemon-key-1`，再调用 delegated key revoke / `revoke_binding`。
- daemon 保留 runtime archive 能力，但删除 runtime 前必须先停用 binding。

## 当前剩余风险

- 完整 App -> daemon -> user-service -> message-service -> App 的 happy path 尚需在部署了 Step 06 user-service RPC 且启动 message-service v2 的环境补跑；当前 Linux 容器只能提供 focused component / acceptance 证据。
- 当前 message-service 仍将 delegated WSS 视为 Human DID delegated client，协议层尚不能表达 `from: Agent DID` / `on_behalf_of: Human DID` 双 proof。
- `runtime_final` 当前按 `hash_only` retention 展示完成/有结果状态；完整草稿内容依赖 `message.create_draft` action payload。
- 撤销 delegated key 的强语义依赖 signed DID Document update 和 message-service DID Document cache 刷新，单纯 disable binding 不是永久撤销授权。
- MVP 不做会话级策略，默认处理所有可处理会话；后续需要补联系人/群聊/会话策略和隐私提示。

## 当前结论

MVP 推荐采用以下产品定义：

```text
用户从 Message Agent 设置页启用能力；
用户选择一个 daemon 作为运行环境；
daemon 创建并运行一个独立 DID 的消息处理 Agent；
Human App 发起创建和授权；
user-service 记录 owner、daemon、Message Agent 和 binding；
bootstrap / delegated key 敏感材料通过安全 envelope 或等价安全通道传递；
message Agent 使用 Human DID delegated key 连接 message-service WSS；
message Agent 默认处理所有可处理会话；
message Agent 只做分析、总结、草稿和 App action 请求；
MVP 不开放 message Agent 代发和自动回复；
Human 确认后的发送由 Human App 正常发送链路完成；
创建 / 绑定成功以 IM 消息形式展示，但底层事实来自 binding handshake；
停用或删除时，解除 binding 并停止消息处理链路。
```

这一定义服务于第一版快速上线，同时把最危险的安全传输问题纳入本次 MVP。协议级 `from: Agent DID`、`on_behalf_of: Human DID`、双 proof、跨域 delegation 验证和受控代发能力，作为后续演进继续补齐。
