# AWiki Me Join 后根密钥传输

状态：Step 3 V1 active contract；唯一原生生产路径

总体协议与密码学边界以
[`v1-step3-root-key-transfer-and-management-readiness-implementation-plan.md`](../../awiki-plan/20260718-awiki-multi-device-implementation/refactor/v1-step3-root-key-transfer-and-management-readiness-implementation-plan.md)
为准。本文只记录 AWiki Me 的产品入口、Host API 和状态边界。

## 1. 产品入口

远端 Join 已消费但本地批准收口被中断时，Core 会从已验证的完成通知和本机批准记录恢复。
App 重开本机已批准的完成通知，或收到其完成更新后，读取 Core 的 Authorized 结果并显示
可选管理权限步骤，不再退化成“等待管理设备响应 / 完成”。该读取不重放批准、不显示过期
SAS，也不自动发送 Root；其他管理员消费的通知不能据此恢复本机授权入口。

V1 提供两个入口，但二者委托同一个 Core Root Transfer：

- 当前管理设备刚完成一次 Join，且目标已经成为
  `active + member + management_ready=false` 时，可以立即“继续授予管理权限”；目标固定为
  这次 Join 返回的 `authorizedDevice`；
- 用户当时跳过、关闭页面或稍后改变决定时，设备列表会对权威 Registry 中符合相同条件的
  普通设备显示“授予管理权限”。

设备列表不是通用传输控制台：不提供传输历史、接收端恢复按钮、Registry completion 轮询或
imported-ACK 状态机。每次点击都从 fresh Registry/Manifest/PreKey 或既有 P5 pending 重新
`prepare`，不复用 Join Session 或旧 handle。

接收端的消息同步与实时恢复可以同时触发 Core 收尾；同一转移由 Core 串行、幂等收敛，
不会因完成阶段已经前进而误报设备权限失效。App 不吞掉真实权限错误。
恢复后重新加入的 E2E 会并发发起两次显式同步，并核验管理权限、会话保留和普通历史隔离。

终态 Join 通知可能先于批准调用及其 `authorizedDevice` 返回；`isActionPending` 为真时，
审批页只能显示不可点击的“正在完成设备操作”，不能提前显示“完成”并让用户退出。
批准收尾后重新判断精确目标资格，显示授予管理权限步骤；它仍是单独的用户确认操作。
真实 E2E 同时延迟批准结果并处理终态通知，禁止先等待收尾结束来绕过这个窗口。

审批 Inbox 的异步验证读取不得覆盖同一身份下已完成的审批或较新的选择；特别是
“response_verified 读取开始 → 审批成功 → 旧读取返回”时，必须保留 `authorizedDevice`
和继续授予权限入口。此入口不以已有管理员数量为隐藏条件。

设备列表可以显示较新的 account-state 缓存，但用户点击授予权限时必须重新读取权威
Registry，并核对相同 device ID、signing key 和 E2EE key。读取期间显示忙状态并阻止
重复点击；设备已失效、密钥改变、读取或 prepare 失败时显示失败提示，不能静默返回。
缓存不能直接成为授权依据，且仍需用户确认和系统认证后才能发送根密钥。

测试分层：系统测试使用真实 CLI/Core 验证 Join 前后 Registry、PreKey 与管理能力，
不能观察 Flutter 的按钮状态。过去的 App E2E 顺序等待审批完成、打开 Devices 时主动刷新，
未制造后台旧读取晚于审批返回的时序，也未要求“点击”本身读取 Registry。现在由
`devices_ui_test.dart` 固定复现双管理员、缓存领先、读取失败和重复点击；真实 `root-transfer`
E2E 用仅延迟真实响应的测试门闩覆盖迟到验证，并以独立 attestation 要求点击重新读取
Registry。正常成功链路、等待固定时间或单独的 CLI 通过不能替代这些 UI 回归断言。

真实双 App 的 `ROOT-TRANSFER-APP-PAIR-E2E-001` 另行验证：普通 Join 后立即观察主 App
授予入口，通过该入口准备但不发送，再从设备列表确认发送；接收端也是 App，必须自行
完成导入并让两端 Registry 都显示两个 ready 管理设备。`multi-device-app-pair-later-admin-grant`
现在选择这个双 App suite，`root-transfer` 仍是 App+CLI，二者不可互相冒充。

## 2. 操作顺序

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
密文的短期 handle，不自动发网；Realtime/App 启动也不自动重发。只有本次 user-presence
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
