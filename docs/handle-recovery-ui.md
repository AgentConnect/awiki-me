# AWiki Me Handle Recovery 产品流

状态：App-owned 状态机、生产 Core adapter、requester 激活链与旧管理设备通知/取消闭环已接入；默认关闭

整体身份语义以
[多设备架构](../../awiki-cli-rs2/docs/architecture/multi-device/multi-device-architecter.md)
和 [Step 09](../../plan/20260718-awiki-multi-device-implementation/steps/09-handle-recovery.md)
为准。本文只记录 AWiki Me 的产品状态、秘密边界和启用门禁。

## 1. 产品语义

V1 只支持一条恢复路径：

```text
输入精确 Handle 与所属域
  -> 以 awiki.device.recovery.begin.v1 + Handle/domain 请求第一次 SMS OTP
第一次 SMS OTP
  -> begin：创建 Recovery Session
  -> cooling：正在通知旧设备和绑定渠道，旧管理设备可取消
  -> ready：以 awiki.device.recovery.finalize.v1 + Handle/domain/Session
            重新发送并输入独立的第二次 SMS OTP
  -> 用户明确确认风险
  -> finalize：本机创建新根密钥、新设备密钥和新 DID
  -> Handle 切换到新 DID，旧设备退出
```

第一次 OTP 不激活身份、不切换 Handle，也不能作为 finalize 的再次确认。普通 login/register
验证码也不能用于 Recovery。冷静期的权威 deadline 只来自后续 status；UI 不把 begin 响应误写成
“旧设备已收到通知”。App 已删除
onboarding 中注册 Handle 后调用旧版 `recoverHandle()` 并自动恢复群组的行为。恢复完成后，
历史消息解密能力、Direct 会话和群组成员关系均不自动继承。

## 2. App 边界

`HandleRecoveryPort` 是 AWiki Me 自有的 application boundary。UI 只接收无秘密投影：
Recovery ID、Handle、旧/新 DID、阶段、冷静期/过期时间、交互侧和当前设备是否可取消。
SMS OTP 仅作为 begin/finalize 方法的 write-only 参数。App Port 分开定义 begin/finalize 发码和
兑换：begin 必须绑定 exact Handle local-part/domain；finalize 还必须绑定
`recovery_session_id`。该约束对应 user-service 同域 REST：

```text
POST /auth/sms-codes
POST /auth/account-verification/exchange

begin purpose:    awiki.device.recovery.begin.v1
finalize purpose: awiki.device.recovery.finalize.v1
```

adapter 在方法内部完成发码、兑换并把 purpose-limited credential 直接交给 Core，App boundary
不返回 grant/token。

实现 adapter 时必须在方法内部完成 purpose-limited account-verification exchange，并立即把
grant 交给 Core。Recovery token、account token、DID 私钥、DID Document 和设备 proof 不得
进入 Riverpod state、日志、错误详情、ProductLocalStore 或 E2E 报告。
Recovery 的稳定 operation ID、幂等重试和重启续传也由 adapter/Core 持久管理，UI 不得在
每次 finalize 重试时临时生成不同的 wire operation ID。

旧管理设备从 Core 的独立、secret-free `OldAdminRecoveryNotice` 读取 event/session ID、Handle、
旧 DID、申请时间和可取消截止时间，在“设备”页获得显式取消入口。通知不伪装成请求方的
`HandleRecoveryProgress`，也不携带 raw control payload、sync checkpoint、token、proof、邮箱、
秘密或内部版本。新设备不能把本地放弃误当成服务端取消。

finalize 和旧 admin cancel 即使被其它调用方直接调用，也必须在 application service 再次验证
显式 intent，并通过 `UserPresencePort` 完成本机 PIN/生物识别；不支持、取消或失败均 fail closed，
不会调用 Core 敏感写。

cutover 成功后远端状态已经是 `consumed`，绝不能再次 finalize。Core 必须先持久化可恢复的新
身份，并投影 `localActivationPending`。本地激活严格复用正常会话链：先由
`AppRuntime` 立即清除旧身份的完整 authenticated UI state，并 fail-closed 等待旧身份的
Realtime 连接停止；停止失败时保持登出且不得继续切换。之后再由 `AppSessionService` 清理已
撤销旧身份、切换 Core identity、认证并写入 `ActiveSessionStore`，
再由 `AppRuntime` 初始化 E2EE，最后 ACK Core 的 durable pending marker。App 不得绕过
`AppSessionService` 直接制造登录态。

`AppShell` 独立于 Onboarding 恢复并观察 Recovery 投影。ActiveSessionStore 写入或 E2EE
失败时清除伪登录态和 active pointer，只保留“重试本地激活”；marker ACK 失败时新身份和
E2EE 可以继续使用，但全局显示可重试提示，后续只重试 marker ACK，不重复 finalize、身份
切换或 E2EE。进程重启时，正常 Session restore 只初始化一次 E2EE；若其 DID 与 pending 的
新 DID 完全一致，则只继续 marker ACK。重试身份始终从 Core 的 durable projection 重新读取，
进程内 AppSession 不作为恢复权威。

Recovery restore、status、cancel、finalize 和本地 activation 使用同一个 operation generation
线性化状态写入；加载或动作进行中所有可见操作入口均禁用，较慢的旧 restore 结果不得覆盖
更新的 ACK、激活或取消结果。

生产 adapter 的 SMS 发码与 exchange 都绑定 exact purpose、Handle local-part 和 domain；finalize
额外绑定 `recovery_session_id`，并且只接受响应中的 `reconfirmation_token`。begin 只接受
`account_verification_token`。两种 credential 在方法内部立即包装成不同的 SDK write-only grant，
不会进入 App state 或错误信息。

旧管理设备取消前，Application service 必须按 `event_id` 从 Core fresh get 通知并逐字段确认，
再重新触发一次 `UserPresencePort`，最后才调用既有 `cancel`。Core `cancel` 仍只返回权威的
Session ID 和 phase，并重新验证当前设备为 management-ready admin；普通设备、非 ready admin、
过期或已撤销设备均 fail closed。

取消成功后 App 再独立调用本地 dismiss，让已解决警报在刷新后隐藏。“仅在本设备隐藏”只调用
dismiss，文案明确它不会取消服务器上的 Recovery Session。Core 的 realtime/sync consumer 直接
持久化通知；设备页初始化和手动刷新重新 list 即可发现，不订阅 raw control。该控制通知不会进入
聊天、普通系统通知或通知预览。

## 3. 开关和 fail-closed 行为

入口由编译期开关 `AWIKI_HANDLE_RECOVERY_ENABLED` 控制，默认 `false`。仓库已接入生产
Recovery adapter；但开关关闭时不会构造 adapter、不会打开 Core gate，也不会退回旧版立即
恢复或改变身份状态。

生产 composition 只有在开关启用时才构造 adapter，并把同一个 gate 传给 IM Core。启用前仍必须
由 Core/SDK 和部署环境提供并验证：

1. 持久化且无秘密的 local recovery session projection；
2. begin/status/cancel/finalize Dart API，以及 begin/finalize 不同 purpose 的一次性 grant；
3. finalize 在新 Storage/Owner Scope 内生成全新 DID 和设备密钥，绝不复制旧 Ratchet、MLS
   或 root secret；
4. 旧管理设备通知、fresh-get + user-presence 签名取消和 cancel/finalize CAS 竞争；
5. finalize 成功后返回可激活的新身份，但失败/超时不得激活半成品。
6. cutover 前持久化新身份，并提供 consumed 后可重启续传的 activation projection/ACK。

缺少任一项时必须继续保持开关关闭，不能增加 HTTP-only 私钥生成或旧 `recoverHandle()`
fallback。旧管理设备通知消费已完成，但远端 capability 与完整 E2E gate 通过前，整体 Recovery
capability 仍不能发布启用。

## 4. 验证

确定性测试覆盖状态验证、冷静期、第二次 OTP、风险确认、新 DID 激活和旧管理设备取消：

```bash
flutter test tests/unit/application/app_session_service_test.dart \
  tests/unit/recovery/handle_recovery_service_test.dart \
  tests/unit/recovery/handle_recovery_provider_test.dart \
  tests/unit/data/im_core/awiki_im_core_handle_recovery_adapter_test.dart \
  tests/unit/handle_recovery_ui_test.dart \
  tests/unit/onboarding_page_test.dart
```

真实 App + CLI + `awiki.info` 的 `HANDLE-RECOVERY-E2E-001/002` 已登记到显式激活的
`multi-device-remote-recovery` suite：前者等待至少 3600 秒权威冷静期，经独立二次 OTP 和
真实 LocalAuthentication 激活不同的新 DID；后者证明旧 ready admin 的 durable 通知跨 App
重启后仍可见，并经真实 LocalAuthentication 取消且阻止 finalize。该 gate 要求两个隔离账号与
native Core roots、成功的产品短信发码和精确 CLI revision，明确不接受 staged SMS error。
`HANDLE-RECOVERY-E2E-003` 的旧 token、未来消息、Direct 与群重绑完整收敛仍保持 planned；
fake-backed Widget 测试不能作为远端恢复通过证据。
