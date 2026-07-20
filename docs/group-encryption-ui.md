# AWiki Me 多设备群加密状态

状态：App 状态投影已实现，能力默认关闭；P6 v2 公共 Core 编排与真实 `awiki.info` E2E
仍是启用门禁。

整体流程以 Core 仓库的
[多设备架构](../../awiki-cli-rs2/docs/architecture/multi-device/multi-device-architecter.md)
和 [Step 08](../../plan/20260718-awiki-multi-device-implementation/steps/08-mls-multi-device.md)
为准。本文只记录 AWiki Me 的产品边界。

## 产品状态

群详情页只显示本设备的三类主要状态：

```text
正在加入群加密
群加密需要重试
群加密已就绪
```

环境不具备群加密能力时显示“暂不可用”。重试只调用 IM Core 的公共群安全修复入口，
随后重新读取 Core 状态；App 不执行 Add、Welcome、Commit、Remove，也不自行推进 epoch。

## 安全与启用边界

编译期开关 `AWIKI_MULTI_DEVICE_GROUP_E2EE_ENABLED` 默认 `false`。App 只接收
`ready/preparing/needs-retry/unavailable`、是否可安全发送和是否可重试等无秘密投影，
不接收或展示 Leaf index、KeyPackage 私钥、epoch secret、Commit/Welcome 明文或 MLS
数据库内容。群业务成员仍按 DID 展示，不因同一 DID 有多个 Leaf 而出现重复成员。

当前 `awiki_im_core` Dart 公共接口提供通用的
`client.secure.group(groupDid).status()/repair()`，但底层产品编排尚未从 P6 v1 切换到已完成
的 P6 v2 多设备 runtime。因此该开关不得在普通账户启用，也不能据此宣称同 DID 多 Leaf
已经完成产品联调。Core 将公共状态/修复入口接入 P6 v2，并通过独立设备数据根的远端 E2E
后，App 无需理解 MLS 内部细节即可启用。

## 验证

```bash
flutter test tests/unit/data/im_core/awiki_im_core_group_encryption_adapter_test.dart \
  tests/unit/group_encryption_ui_test.dart
dart run tool/validate_test_catalog.dart
```

真实产品合同 `MLS-MULTI-DEVICE-E2E-001`、`002` 当前保持 planned；Widget fake 不能把它们
标记为通过。
