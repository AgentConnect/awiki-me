# AWiki Me Join 后根密钥传输

## 一次 Join 授权自动配置管理权限（2026-09-15）

App/CLI 的正常加入确认含义为“允许该设备加入并成为管理设备”。保留身份/SAS 核对及一次 user presence；取消此路径后续独立 root 授权。Core 的既有普通 Join 接口仍供 Node/DSH 使用，独立 root-key send 仍要求单独明确授权，不能将 user_presence_confirmed 硬编码为 true 接入自动流程。

Core 在发送批准请求前，将自动任务随该 Join 的既有持久化批准记录保存，绑定 owner、DID、Join、目标设备和签名/E2EE 公钥、源管理设备及已批准文档。服务端批准响应丢失时，只能由已验证批准结果/通知恢复任务。自动尝试状态归 Core，发送原消息/密文仍复用既有 sender ledger 与 P5 pending outbound，不复制密码学实现。

首次立即尝试，包括 PreKey 未就绪在内最多四次（首次加最多三次重试）；每次可重试失败结束后持久化五秒后的下次时间。尝试先记账后发网，崩溃不返还预算；恢复中的未完成尝试先对账，并保守等待五秒。跨进程文件锁覆盖整个推进轮次，防止实时线程、同步与恢复重叠。网络操作有独立超时，不把五秒作为整个操作超时。

发送接受后停止发送重试，等待原接收端 pending root、完成证明、Registry 登记、本地 root 激活和认证更新链路。发送端只能报告服务端管理登记，不能据此声明接收端本地 root 已激活。四次耗尽显示“设备已加入，管理权限配置失败”；显式重试先对账接受/登记状态，才允许新一轮预算。撤销、设备/密钥变化、身份/签名验证失败终止任务。进程退出保留状态，不承诺退出后仍发网；长期离线保持等待，无任意失败期限。

无秘密投影只包含 Join/设备 ID、阶段、尝试次数、下次尝试时间、稳定错误码；不暴露 root、密文、proof 或自动授权 handle。真实四方向及第三台设备批准证据属于后续真实环境验收，不由本地测试代替。


状态：Step 3 V1 active contract；唯一原生生产路径

总体协议与密码学边界以
[`v1-step3-root-key-transfer-and-management-readiness-implementation-plan.md`](../../awiki-plan/20260718-awiki-multi-device-implementation/refactor/v1-step3-root-key-transfer-and-management-readiness-implementation-plan.md)
为准。本文只记录 AWiki Me 的产品入口、Host API 和状态边界。

## 1. 产品入口

正常 App/CLI Join 已在一次用户确认中授权精确目标成为管理设备。Core 在批准请求发送前持久化意图；批准响应丢失时由可信完成通知恢复同一任务，App 重开时只显示 Core 进度，不显示过期 SAS、不再次批准，也不扩大到其他管理员处理的 Join。

审批仍在提交时保留不可点击的“正在完成设备操作”；批准结束后显示配置中、等待接收端、登记完成或失败。允许安全离开页面，Core 在进程内继续有界工作，进程退出保留预算。迟到的验证读取不得覆盖已授权目标。

四次失败后的显式重试复用原 Join 授权，先对账本地 sender ledger 和权威 Registry，再启动新一轮。设备列表也将此目标的失败补救路由回同一 Join；有自动任务进行中时不显示第二个独立授予操作。

没有自动任务的既有普通设备仍可从设备列表执行独立手动授予。点击时重新读取权威 Registry，核对相同 device ID、签名及 E2EE key，再 prepare 和确认；缓存不能作为授权依据。独立手动 sender 与自动 sender 共享 exact-recipient 排他锁，拿锁后重验 ledger，避免两个入口同时发送。

接收端沿用 pending root、完成证明、Registry、active root 和认证更新链路。App 的本机管理按钮同时要求权威 Registry 和 Core `identityDeviceSummary` 的 `adminReady`；Registry 登记不能提前冒充本地激活。发送端自动状态仅报告管理登记，明确要求在接收设备核验本地管理能力。

本地 `devices_ui_test.dart` 保留迟到验证、终态通知先到、多个管理员、缓存领先、失败及重复点击覆盖；自动 Join 新增无第二次确认、等待不提前成功和 retry。`ROOT-TRANSFER-E2E-001` 使用 App→CLI，`ROOT-TRANSFER-APP-PAIR-E2E-001` 使用真实 App→App；真实环境均需单独指定并执行，不能由本地通过替代。

## 2. 既有普通设备独立手动授予的操作顺序

App 严格执行下面的单目标流程：

1. 调用 identity-scoped `client.rootKeyTransfer.prepare(recipientDeviceId)`；
2. 校验 Core 返回的 DID、设备 ID、签名密钥 ID 和 E2EE 密钥 ID 与当前选中的 eligible 设备一致；
3. 只展示上述无秘密目标摘要，不展示 authorization handle；
4. 用户点击确认后，只触发一次系统 user-presence；
5. 将 opaque authorization handle 和确认结果传给
   `confirmAndSend`；
6. 校验接受回执的 DID、sender、recipient 和非空 message ID；
7. 以“根密钥已发送”结束，不等待 Registry readiness completion。

如果已有 response-loss 后的 `pending_delivery`，`prepare` 只返回绑定原 message ID 和原 P5
密文的短期 handle，不自动发网；没有 Join 自动授权的独立手动任务在 Realtime/App 启动时不自动重发。只有本次 user-presence
确认后的 `confirmAndSend` 才续跑相同 bytes。取消确认会消费 handle，但不导出 root、不发网。

页面状态只包含：

```text
idle -> preparing -> awaitingConfirmation -> sending -> sent
                                             \-------> failed
```

发送期间按钮禁用，防止重复确认。失败显示“设备已加入，新设备未获得管理权限，请稍后
重试。”；只有 Core 明确返回 `retryable=true` 时，Join 审批页才同时提供“重试”。重试重新
prepare 同一 eligible 目标，成功后仍须显式确认和系统认证；不复用旧 handle，也不自动发送。
审批完成不表示新设备已完成激活或发布首个 PreKey；此时服务端 bundle-not-found 由 Core
映射为 `root_transfer.prekey_unavailable`，而非不可重试的 `prekey_invalid`。签名、绑定或
认证校验失败仍 fail closed。不会把 Core 诊断、PreKey、proof、nonce、密文、checkpoint
或 handle 投影到 UI。

## 3. App/Core 边界

Host API 只接收 `recipient_device_id`、opaque authorization handle 和
`user_presence_confirmed`。message ID 由 Core 生成。App 不接收或构造 RootKeyEnvelope、
根密钥、PreKey、session、proof、nonce、ciphertext 或 completion checkpoint。

公开错误固定为 `{code, retryable}`。Web 明确返回
`root_transfer.unsupported`，不得退回明文或 JavaScript 密码学实现。

## 4. 专项验证

```bash
flutter test \
  tests/unit/devices/root_key_transfer_service_test.dart \
  tests/unit/data/im_core/awiki_im_core_root_key_transfer_adapter_test.dart \
  tests/unit/devices/devices_ui_test.dart
```

专项验证覆盖精确 Join 目标、设备列表 eligible member、prepare 先于 user-presence、一次确认、
pending 不在确认前发网、opaque handle、无秘密 DTO／错误映射和接受回执校验。
真实 `root-transfer` E2E 在接收端激活前验证缺少 PreKey 的可重试状态，激活后通过审批页
重试至重新确认，再取消准备，继续保留原设备列表入口的完整发送及接收端 readiness 验收。
