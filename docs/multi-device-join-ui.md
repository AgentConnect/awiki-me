# AWiki Me 多设备加入、设备页与永久撤销

状态：实现完成，默认关闭；Join、根导入与永久撤销已有显式远端 E2E gate

整体身份和密码学方案以 Core 仓库中的
[多设备架构](../../awiki-cli-rs2/docs/architecture/multi-device/multi-device-architecter.md)
和[架构概览](../../awiki-cli-rs2/docs/architecture/multi-device/multi-device-architecture-overview.md)
为准。本文只记录 AWiki Me 的产品边界与 UI 状态流。

## 1. 产品入口与开关

多设备入口由编译期开关 `AWIKI_MULTI_DEVICE_ENABLED` 控制，默认值为 `false`。
开关关闭时，设置页和 onboarding 保持原有布局，Core 也以 Join capability 关闭状态打开；
开关开启时：

- 已登录用户可从“设置 → 设备”查看当前设备、已授权设备和待审批请求；
- 未登录的新设备可从 onboarding 选择“将此设备加入已有账户”；
- V1 只比较两端独立计算的 6 位验证码，不提供二维码或扫码入口。

永久撤销由独立编译期开关 `AWIKI_MULTI_DEVICE_DEVICE_REVOKE_ENABLED` 控制，默认同样为
`false`。它只开放已登录用户的设备页和撤销能力，不会隐式开放新设备 Join；Join 或撤销
任一开关启用时，设置页均可进入设备页读取权威 Registry。

设备级 Direct 产品路径由编译期开关 `AWIKI_MULTI_DEVICE_DIRECT_E2EE_ENABLED` 控制，
默认 `false`。App 只把该值传给 `AwikiImCoreOpenOptions`，不新增 UI；它与 Join、根密钥
传输、永久撤销、Handle Recovery 和 Group E2EE 开关彼此独立，也不进入跨域协议字段。

## 2. App 状态流

```text
新设备：Handle + SMS OTP
  -> AWiki 域内 account-verification exchange
  -> token 在 data adapter 内立即交给 Core 消费
  -> Core 创建并持久化 Join
  -> App 轮询无秘密进度并短暂显示 6 位 SAS
  -> authorized / cancelled / expired

已有管理设备：设备页读取 Registry
  -> claim pending Join
  -> Core 验证 challenge 并投影 6 位 SAS
  -> 用户确认两端一致
  -> 默认 member；显式开关才选择 admin
  -> 一次系统 user-presence
  -> Core 完成授权
```

App 重启后只从 Core 恢复 Session 摘要，再轮询恢复当前进度。App 不把 SAS 写入
`ProductLocalStore`、偏好设置或 E2E 报告；终态由 Core 投影，重复点击由 service/provider
和 Core 幂等门禁共同拒绝。

## 3. 安全边界

AWiki Me 只持有可展示的设备摘要、Join 阶段和一次性审批句柄。设备签名私钥、设备
E2EE 私钥、配对共享秘密、challenge 明文和 DID 根私钥始终留在 Core/Vault。
SMS OTP 只进入发起方法；域内 exchange 返回的 account token 只存在于 data adapter
的局部变量，并立即包装为 Core 单次消费对象，不进入 application/presentation state、
日志、错误、持久化或跨域协议。

`admin` 选择只表示用户明确授予管理意图。根密钥导入完成并达到
`management-ready` 前，UI 不应把设备描述为可管理其他设备；后续
`admin-awaiting-root → importing → ready/failed` 产品流见
[管理设备根密钥导入](root-key-transfer-ui.md)。

## 4. 永久撤销

只有当前 `active + admin + management-ready` 设备可以看到其他 active 设备的撤销动作。
App 先显示破坏性确认窗口；用户确认后再请求一次系统 PIN、生物识别或等价
user-presence，拒绝时不得调用 Core。当前设备不显示撤销动作；Core 继续 fail closed
拒绝 self revoke 和最后一台 ready admin。成功后 App 重新读取 Registry，不根据本地按钮
点击推断撤销已生效。

App/Flutter DTO 只包含 DID、目标不透明 `device_id` 和 `revoked` 状态。控制消息、proof、
Document/Registry 版本与 hash、`auth_generation`、operation ID 和密钥材料都不能进入页面、
通知、日志或普通聊天记录。撤销只保护未来访问，不能远程删除目标设备已经获得的数据。

## 5. 验证

确定性覆盖：

```bash
flutter test tests/unit/data/im_core/awiki_im_core_device_management_adapter_test.dart \
  tests/unit/devices/device_management_service_test.dart \
  tests/unit/devices/devices_ui_test.dart
```

真实 App + CLI + `awiki.info` 的 `DEVICE-JOIN-E2E-002` 与永久撤销
`DEVICE-REVOKE-E2E-001` 已进入显式激活的 `multi-device-remote-join` suite，合同位于
`tests/e2e/flutter/app/multi_device_join_ui_test.dart` 及其
`root_key_transfer_ui_test.dart` part；它只有在独立 Core 数据目录、动态一次性 OTP、双端
SAS、每次真实系统 user-presence 和最终 Registry 断言全部完成后才可通过。
`DEVICE-JOIN-E2E-001` 与 `003` 仍为 planned，不得以 `002`、本地 capability gate 或
fake-backed Widget 测试替代其通过证明。
