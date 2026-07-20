# AWiki Me 管理设备根密钥导入

状态：App 产品流已实现，能力默认关闭；真实 `awiki.info` E2E 已进入显式激活 gate

整体密码学流程以 Core 仓库的
[多设备架构](../../awiki-cli-rs2/docs/architecture/multi-device/multi-device-architecter.md)
和 [Step 06](../../plan/20260718-awiki-multi-device-implementation/steps/06-admin-root-transfer-revoke.md)
为准。本文只记录 AWiki Me 的产品状态和边界。

## 1. 开关与状态

根传输由编译期开关 `AWIKI_MULTI_DEVICE_ROOT_TRANSFER_ENABLED` 控制，默认 `false`，
并与 Join 开关独立传给 IM Core。只有当前 `active + admin +
management_ready=true` 的设备可以开始传输；member 和尚未 ready 的 admin
不能执行审批或其他管理动作。接收端 admin 可以在 user-presence 后仅恢复 Core
已持久化的 imported ACK，这不授予其他管理能力。

```text
admin-awaiting-root
    -- Direct 尚未就绪 --> 安全会话建立中（仍是 awaiting）
    -- 本机 user-presence + Core 接受密文投递 --> importing
    -- Registry management_ready=true ----------> ready
    -- 安全失败 -------------------------------> failed
```

若 Direct P5 v2 会话尚未建立，首次操作只会触发 Core 的 session Init，RootKeyEnvelope
尚未生成，也没有可供 `listRootKeyTransfers` 恢复的 sidecar。App 明确显示“安全会话
正在建立中”的信息提示，不使用失败样式；仅在当前前台保留无秘密的
recipient/message ID；用户让接收设备同步后，
必须再次完成 user-presence，App 才用相同参数继续调用 `send`。该预备步骤不能显示为
`importing` 或“传输失败”，也不能自动绕过第二次确认。

`ready` 只来自重新读取的 Device Registry。投递成功或 Core 的 `completed` 进度仅表示
控制流已经推进，不能提前显示为 ready。失败后的显式重试再次要求 user-presence，
并由 Core 恢复原 Direct message ID；重复完成由 Core/服务端幂等处理。

## 2. App/Core 边界

AWiki Me 只向 Core 传递 identity selector、目标 `device_id`、初始 message ID 和已完成的
user-presence 断言，并只接收无秘密的投递回执/进度摘要。RootKeyEnvelope、根私钥、
Direct 密文、imported ACK 和 transport sidecar 均留在 Core/服务端既定边界中；控制
JSON 不会进入聊天 timeline、通知、日志、错误文案或 ProductLocalStore。

接收端导入由 native inbox 自动处理。App 每次打开或刷新设备页时，通过公共 SDK 读取
Core 按本机 identity/device scope 保存的无秘密摘要，以恢复 sender/receiver 的
`importing/failed` 和原 message ID；App 不在 ProductLocalStore 再维护一套状态机。
Core 摘要只用于进度和重试，Device Registry 的 `management_ready` 仍是权限事实源。
会话 Init 尚未创建 root sidecar，因此它只是一项前台操作意图；进程重启后回到
`admin-awaiting-root`，不得伪造持久化 transfer。

## 3. 验证

```bash
flutter test tests/unit/devices/root_key_transfer_service_test.dart \
  tests/unit/data/im_core/awiki_im_core_root_key_transfer_adapter_test.dart \
  tests/unit/devices/devices_ui_test.dart
```

`ROOT-TRANSFER-E2E-001` 已加入显式激活的 `multi-device-remote-join` suite：它使用独立
Core 数据根、动态一次性 OTP、真实 user-presence、部署后的 awiki.info 路由，以及
CLI/Core completed imported-ACK 与两端 Registry `management_ready` 的联合断言。代码存在
不代表远端已经通过；隐藏 rollout、账号或人工认证前置条件缺失时必须 fail closed。
重启、失败重试和幂等 readiness 合同 `ROOT-TRANSFER-E2E-002` 仍为 planned。
