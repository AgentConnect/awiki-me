# Handle Recovery V1 UI

Handle Recovery 是已有 Handle 登录/注册流程中的高风险分支，不再是首页独立入口。
首页只保留统一的登录/注册动作；当已验证的手机号、验证码和 Handle 对应一个已存在
Manifest 身份时，App 才让用户选择“加入新设备”或“恢复 Handle”。Handle Recovery 是
AWiki Me 的基线能力，不使用 Debug/Release 或平台编译开关；当前租户仍须通过 Server Info
声明 phone Recovery capability，避免向旧版或第三方租户发送其不支持的 V4 请求。租户未声明
能力时，弹窗只展示加入设备和取消，并使用 join-only 文案，不显示无法点击的恢复按钮。

选择 Recovery 后，Handle 和手机号以只读方式沿用已验证的 onboarding 上下文，页面不会
要求再次输入；注册授权会被丢弃，并立即请求 purpose 为
`awiki.identity.handle-recovery.v1` 的独立 Recovery OTP。注册/Join 与 Recovery 的重发
边界按 purpose 隔离，避免注册冷却阻止专用 Recovery OTP，同时仍分别遵守服务端返回的
`retry_at`。Recovery 不绑定当前激活身份，也不要求本机曾保存目标 Handle。

已登录用户也可从设置选择“恢复 Handle DID”。该入口要求重新输入手机号并完成同一专用
Recovery OTP、风险确认和 activate 流程，但必须把当前会话的 exact `localIdentityId` 交给
Core；恢复前不退出、不删除凭证或本地数据，因此 Direct、Group、Agent 历史和智能体库存继续
归属于同一 stable owner。恢复完成后同样直接返回消息主界面。

## 当前协议边界

- 当前 OTP purpose 固定为 `awiki.identity.handle-recovery.v1`。
- Core 在请求 Recovery OTP 前创建 opaque operation ID；OTP、Handle 和 operation ID 必须
  在 prepare 阶段保持同一绑定。统一 onboarding Recovery 不提供 selector；Core 按 Handle
  精确匹配本地身份，本地不存在时生成新的本地 owner 与身份材料。
- App 禁止把当前身份、`credentialName` 或 alias 当作恢复目标猜测。Core 返回本次
  operation 的 `ownerIdentityId`，后续 status/activate/resume 才按该 owner/operation 推进。
- 上述省略 selector 只适用于 fresh onboarding。设置中的已登录恢复必须显式使用当前
  `localIdentityId`，不得退化为 alias、DID 或新建 owner。
- OTP 仅作为瞬时输入传给 Core，App 不持久化 OTP、grant、密钥或证明材料。
- prepare 后 UI 必须展示 Handle 保留、其他设备重新加入、普通本地数据迁移以及
  E2EE/DID-only 限制等不可逆影响；用户明确确认后才允许 activate。
- 本地已有目标 Handle 时只迁移该身份的普通数据，不切换或覆盖其他身份；本地没有目标
  Handle 时 `localOrdinaryDataWillMigrate=false`，恢复完成后把新身份加入本地身份列表。
- fresh Recovery 的消息副本仍按 `tail_only` 启动，因此当前版本不会自动恢复 Recovery 前的
  Direct 历史；这需要后续增加服务端可审计的恢复副本 bootstrap 授权，App 不在本地猜测旧
  Direct ownership。普通 transport-protected Handle 群则复用现有 `group.rebind_member`：群
  列表刷新先续跑 Core repair，旧 DID 成员换绑到新 DID，旧 DID 发出的群消息继续显示为本人。
  DID-only 与 Group E2EE 群仍保持 fail closed。
- activate 需要 user presence。正式 App 使用平台 LocalAuthentication；自动化 E2E
  只能覆盖测试专用 `UserPresencePort`，不能声称验证了真实系统认证。
- Core 是唯一恢复状态机。App 只展示粗粒度 phase，并在 Core 标记可恢复时提供精确
  resume。远端 Commit 已成功、本机 JWT 刷新或 P5 PreKey 发布暂时失败时，Core 必须
  保留同一 operation 并投影 `local_transition_pending`；App 刷新精确 status 后自动续跑一次，
  仍失败则保留“继续恢复”操作，不得降级为“未准备完成”或要求新建 Recovery。
  完成时持久化 Core 授权的 Registry epoch reset、激活恢复身份并直接收束到消息主界面，
  不把用户留在 Recovery 页面。
- `applied` 只证明 Core Recovery 已完成，不等同于 App 会话已经激活。Recovery 页面必须同时
  确认 `sessionProvider` 与 runtime 都提交了同一个恢复身份，才允许退出页面并进入消息主界面；
  本地会话激活失败时保留完成页面和“继续进入消息”按钮，只重试本地身份激活，不新建 Recovery、
  不再次替换 DID，也不得误退回普通登录/注册流程。
- 已登录用户从设置发起 Recovery 时，App 在不可逆提交前先暂停旧会话的实时连接和后台同步，
  防止旧 DID 被围栏后的迟到回调清除恢复后的新会话；提交前取消或失败则恢复原会话，提交后只
  激活 Core 返回的新身份并进入消息主界面。
- Recovery 不新增身份通知。其他 App 在 realtime 连接中断时立即用 Reliable Sync 复核现有
  授权；Core 返回终止性 `authRevoked` 后，App 先隔离旧会话和投影、回到统一登录页，再展示
  一次“账号登录状态已失效”的确认提示。该提示使用中性文案，因为同一终止状态也可能来自
  单设备撤销或会话失效。
- 旧设备重新打开 Join 页时，若旧授权 Join 的 Registry 读取返回 `device.inactive` 等稳定
  设备失效码，App 将该本地会话视为不可恢复并继续展示 fresh Join；用户提交的新 Join 会
  取代仍在执行的旧会话恢复，迟到的旧读取结果不得覆盖新 Join 状态。

设置中的“退出并删除当前数据”是另一条破坏性路径：用户确认后按 stable owner 删除当前身份
在 App/Core 本地库中的消息、群、智能体、草稿、偏好、同步状态、E2EE 数据及本地凭证；远端
Handle 和其他设备不受影响，其他本地身份也不得被删除。删除后的本地历史和密钥不承诺由
Recovery 或 Join 找回。App 只有在 App overlay 与 Core owner 数据均删除成功后才清除会话并
返回登录页，避免界面已退出但本地清理尚未完成。
- 当前 V1 不使用历史的 `awiki.device.recovery.begin.v1` /
  `awiki.device.recovery.finalize.v1`、旧管理设备通知或冷静期取消流程。

## UI E2E

`HANDLE-RECOVERY-V1-E2E-001` 先创建远端 ready-admin fixture，再销毁 setup root，并用一个
没有任何本地身份的 fresh App/native Core root 打开统一 onboarding。用同一 Handle 和手机号
完成登录/注册验证后选择 Recovery，再完成专用 OTP、风险确认、activate 和 bounded resume。
activate 后若 Core 回报 post-commit `local_transition_pending`，用例允许 App 在同一
operation 上自动续跑一次；如仍为可恢复状态，再通过可见的“继续恢复”按钮在有界
预算内推进，终态或不可恢复错误仍 fail closed。
fixture 注册与 UI 验证复用同一测试手机号时，用例必须先遵守首个注册 OTP receipt 的
`retry_at`，并确认 UI 已把第二次 OTP 绑定到规范化 Handle/手机号后才允许提交，避免把
服务端冷却或异步请求竞态误判为产品恢复失败。
进入 Recovery 后还会断言已验证 Handle/手机号仅以只读上下文展示、页面只保留一个 Recovery
OTP 输入框，并且 Core 恰好收到一次同一 Handle/手机号且不带本地 identity selector。
最终 oracle 要求：Handle 保留、新的本地 owner 被安装、DID 被替换、Registry 只有一个
ready current admin，恢复页自动退出到消息主界面，并且旧 DID 不出现在 fresh root 的
identity projection。用例还创建一个 Handle-backed transport Group 和一条恢复前消息，要求
恢复后旧成员精确换绑到新 DID、旧消息仍识别为本人，并能在同一老群发送一条新消息。该专项支持
Linux Flutter desktop runner，也可在 macOS runner 上执行。

`HANDLE-RECOVERY-SETTINGS-CONTINUITY-E2E-001` 专门覆盖已登录用户从设置发起恢复。Phase A
在同一 stable owner 下建立双向 Direct、Handle-backed 非 E2EE transport Group，以及真实
daemon/Runtime Agent 的 prompt/reply，再从设置使用 exact `localIdentityId` 完成一次 Recovery，
并在 Core commit 后制造进程切断。Phase B 用相同 App、peer 和 daemon state root 重启，要求
Handle/account 不变且 generation 只增加 1；三个 conversation ID、Group DID、Agent DID 和
Runtime handle 均不变；原消息完整、exact-one，旧 DID 发出的消息仍显示为本人。随后 Direct
和 Group 双向各发送一条消息，原 Agent 接收一条新 prompt 并返回一条确定性回复；最终
conversation/Agent ID 集合完全不增长，三个线程只增加各自预期的两条消息。Agent 流程使用真实
App/Core、daemon、User Service 和 Message Service，测试 gateway 只替代外部 LLM；群断言不
扩展到当前架构明确 fail-closed 的 MLS/E2EE 或 DID-only 群。Runtime Agent prompt 固定走
`default-plain` Direct；普通恢复用例显式关闭人与人 Direct E2EE 以验证 transport 连续性，
registration rejoin/P5 用例则显式开启 Direct E2EE。

恢复 E2E 的公共 fixture 合同位于
`tests/e2e/handle_recovery_fixture_contract.dart`。它分别定义 Fresh Root 与 Local Data 的固定
资源形状；ready checkpoint 只允许 `sha256:` 脱敏引用、非负期望计数、fixture kind 和阶段，
严格拒绝额外字段、full identity、路径、消息正文及 secret 类字段。Local Data Phase A 依次建立
identity、Direct 双向历史/read、Group 双向历史/read/双成员 metadata、真实 Daemon/Runtime
及 prompt/reply；Phase B 在发送新消息前用相同 run reference 和 observed count 重建 checkpoint，
任何 ID 替换或资源数增长都会 fail closed。准备失败按最后完成的阶段写入当前 case 自己的
`failureObservation`；公共 exact-one oracle 同时在 raw collection 上统计 canonical ID 和
run-unique semantic fingerprint，不能由 `set`、`any` 或首条命中吞掉重复。Fresh Root 的合同
已固定，实际 focused fixture 接线属于后续 Fresh case 拆分，不得把合同单测解释为远端产品通过。

crash-cut handoff 本身也使用严格 schema，只保存 Recovery transition 的 `sha256:` 引用、预期
数量、`recovery_commit_durable` 阶段和可选 fixture checkpoint，不保存 owner/account/operation、
full DID、generation、Handle、conversation/Group/Agent/message ID 或正文。Phase B 先从同一 Core
root 的本地 identity inventory 和只读 Recovery operation/epoch receipt 恢复 transition 原值，
逐项匹配脱敏引用；再从 App、peer、Group、Agent 与 conversation/message 公开投影中按引用做 raw
exact-one 解析。缺失引用可以在有界窗口等待收敛，重复引用或语义错配立即失败，不能选第一条继续。
handoff 文件仍只存在于 ignored 运行目录并保持权限 `0600`。

同一 suite 的 `HANDLE-RECOVERY-V1-E2E-003` 在 Recovery 前用第二套独立 App root 建立旧 member。
Recovery 完成后先要求该旧 principal 的远端消息操作被拒绝，并要求旧 App 自动清除会话、
显示一次失效确认并回到统一登录页，再使用 fresh ordinary Join
OTP/Grant 和 SAS 将同一旧 App 加入新 DID。最终两套 App 的 Registry 与 session 必须收敛，
并与第二个 App 中独立注册的外部 identity 双向各完成一条 Direct exact-one；恢复 App 发出的
消息还必须在 rejoined sibling 上形成 exact own-sync。该业务 case 在 Linux/macOS 使用相同
case ID、动作和 oracle，不包含双发起端、连续第二次 Recovery、revoke 或 MLS 完整矩阵。

独立的 `HANDLE-RECOVERY-REGISTRATION-REJOIN-E2E-001` 复用上述两套 fresh App root，但旧
member 不直接申请普通 Join OTP。它在旧 principal 被围栏后重新打开统一 onboarding，提交
existing Handle registration，并选择 Core 返回的 opaque continuation。App 只持有
`preparation_id/mode/requires_user_presence`，不接触 account verification token、Recovery
transition 或 owner 选择；一次 user presence 后由 Core 在同一进程消费 preparation 并建立
Recovery-aware Join。审批和激活后执行标准 Root/P5，要求 rejoined peer 成为
management-ready admin，且 P5 不进入普通消息历史，随后双向 Direct 各精确一次。该 case 在
显式 Linux/Xvfb 或 macOS `awiki.info` 配置下运行：

```bash
dart run tests/e2e/runner.dart \
  --case multi-device-app-pair-recovery-registration-rejoin-management-transfer \
  --config <explicit-awiki-info-config.yaml>
```

```bash
AWIKI_MULTI_DEVICE_REMOTE_RECOVERY_E2E_ENABLED=1 \
AWIKI_MULTI_DEVICE_E2E_HANDLE_PREFIX=recovery \
dart run tests/e2e/runner.dart \
  --case multi-device-remote-recovery \
  --config <local-awiki-info-config.yaml>
```

该 suite 只允许受审计的 `https://awiki.info` 配置。注册和 Recovery 复用 ignored、
权限受限的 local YAML 中同一个测试手机号和六位固定验证码；仍须先调用真实、精确绑定
purpose/Handle/operation ID 的短信接口。OTP 只在测试进程内读取并注册到 redactor，不能
写入 run config、版本控制文件、attestation、诊断或报告。

缺少专用账号、固定 OTP 配置、远端 capability 或短信请求成功时，只能报告未执行/失败，
不能把编译通过当作远端 Recovery 已通过。
