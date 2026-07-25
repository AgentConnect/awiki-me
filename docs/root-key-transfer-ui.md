# AWiki Me Join 后根密钥传输

状态：Step 3 V1 active contract；唯一原生生产路径

总体协议与密码学边界以
[`v1-step3-root-key-transfer-and-management-readiness-implementation-plan.md`](../../plan/20260718-awiki-multi-device-implementation/refactor/v1-step3-root-key-transfer-and-management-readiness-implementation-plan.md)
为准。本文只记录 AWiki Me 的产品入口、Host API 和状态边界。

## 1. 唯一产品入口

V1 只在当前管理设备刚完成一次 Join，并且新设备已经以
`active + member + management_ready=false` 加入后，显示“继续授予管理权限”。
目标固定为这次 Join 返回的 `authorizedDevice`，不能从设备列表重新选择。

设备列表不提供根密钥发送、进度、重试或接收端恢复按钮。V1 也不提供通用设备选择器、
传输历史、Registry completion 轮询或 imported-ACK 状态机。

## 2. 操作顺序

App 严格执行下面的单目标流程：

1. 调用 identity-scoped `client.rootKeyTransfer.prepare(recipientDeviceId)`；
2. 校验 Core 返回的 DID、设备 ID、签名密钥 ID 和 E2EE 密钥 ID 与刚完成的 Join 一致；
3. 只展示上述无秘密目标摘要，不展示 authorization handle；
4. 用户点击确认后，只触发一次系统 user-presence；
5. 将 opaque authorization handle 和确认结果传给
   `confirmAndSend`；
6. 校验接受回执的 DID、sender、recipient 和非空 message ID；
7. 以“根密钥已发送”结束，不等待 Registry readiness completion。

页面状态只包含：

```text
idle -> preparing -> awaitingConfirmation -> sending -> sent
                                             \-------> failed
```

发送期间按钮禁用，防止重复确认。失败只显示“设备已加入，新设备未获得管理权限，请稍后
重试。”；不会把 Core 诊断、PreKey、proof、nonce、密文、checkpoint 或 handle 投影到 UI。

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

专项验证覆盖精确 Join 目标、prepare 先于 user-presence、一次确认、opaque handle、无秘密
DTO／错误映射、接受回执校验，以及设备列表不存在通用根密钥操作。
