# AWiki Me 多设备群加密状态

状态：App 状态投影与 P6 v2 公共 Core 编排已接入，能力默认关闭；真实 `awiki.info`
执行仍受 rollout、专用账号和操作员门禁约束。

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
开关启用时，App 新建群会明确请求 `group-e2ee` 与附件能力；关闭时保持原有建群请求不变。

`awiki_im_core` Dart 公共接口通过
`client.secure.group(groupDid).status()/repair()` 承载 P6 v2 多设备 runtime。修复执行期间
App 强制投影“正在加入群加密”，不会保留旧的 ready 文案；只有 Core 返回可安全发送后才
显示“群加密已就绪”。该开关仍不得在未完成服务端 rollout 的普通账户启用。

## 验证

```bash
flutter test tests/unit/data/im_core/awiki_im_core_group_encryption_adapter_test.dart \
  tests/unit/group_encryption_ui_test.dart
dart run tool/validate_test_catalog.dart
# 仅在专用账号、ali rollout、动态 OTP 和真实 macOS user-presence 均就绪时：
dart run tests/e2e/runner.dart --case multi-device-remote-mls \
  --config <local-awiki-info-config.yaml>
```

真实产品合同 `MLS-MULTI-DEVICE-E2E-001`、`002` 已进入显式激活的
`multi-device-remote-mls` suite：真实 AWiki Me owner 与独立 CLI Core root 覆盖
Add/Welcome、未来文本和附件、精确设备 Remove。代码可执行不等于已有远端通过证据；
rollout 或操作员前置条件未就绪时不得标记为 pass，Widget fake 也不能替代该证据。
