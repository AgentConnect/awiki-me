# AWiki Me 多设备加入与设备页

状态：实现完成，默认关闭；远端产品 E2E 待灰度环境启用

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

## 4. 验证

确定性覆盖：

```bash
flutter test tests/unit/data/im_core/awiki_im_core_device_management_adapter_test.dart \
  tests/unit/devices/device_management_service_test.dart \
  tests/unit/devices/devices_ui_test.dart
```

真实 App + CLI + `awiki.info` 的 `DEVICE-JOIN-E2E-001` 至 `003` 已登记为 planned，
合同位于 `tests/e2e/flutter/app/multi_device_join_ui_test.dart`。在远端 capability、
独立 Core 数据目录和真实一次性 OTP 流程就绪前，不得加入 executable suite，也不得以
fake-backed Widget 测试替代通过证明。
