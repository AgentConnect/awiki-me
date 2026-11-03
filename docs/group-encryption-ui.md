# AWiki Me 多设备群加密状态

状态：App 状态投影与 P6 v2 公共 Core 编排已接入，能力保留；AWiki Me 当前没有群 E2EE
设置入口，新建群默认使用非 E2EE。真实 `awiki.info` 执行仍受服务端 rollout、账号资格和
操作员门禁约束。

整体流程以 Core 仓库的
[多设备架构](../../awiki-cli-rs2/docs/architecture/multi-device/multi-device-architecter.md)
和 [Step 08](../../awiki-plan/20260718-awiki-multi-device-implementation/steps/08-mls-multi-device.md)
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

修复若返回 Core 明确可重试的 `group.local_cursor_stale`，App 仍重新读取同一群的实际状态，
因为并发接收可能在本次修复推进后使其本地快照失效。App 不再次提交修复、不推断已经成功，
只根据新的 Core Ready／可安全发送投影显示已就绪，否则保留准备中或需要重试状态。
权限拒绝、无效游标及其他错误继续失败；返回其他群的状态仍拒绝。

邀请时若 Core 返回 `group.e2ee.state_not_ready`，成员仍未加入，弹窗保留并提示
“尚未加入：群聊正在更新成员的加密身份，请保持群主客户端在线，完成后重试”。
该状态单独映射为 `groupEncryptionMaintenance`，不归因于被邀请人尚未准备加密或 Agent
准入失败。群主 Core 根据权威状态完成接续；App 不绕过成员门禁或代替 Core 修复 MLS。

## 安全与启用边界

编译期开关 `AWIKI_MULTI_DEVICE_GROUP_E2EE_ENABLED` 默认保留 P6 capability，但它不是
“新建群默认加密”的产品策略。当前没有用户选择入口，新建群不请求 `group-e2ee`，仍创建
普通 transport-protected 群；已有或未来显式选择的 E2EE 群仍可复用相同 Core 能力。App 只接收
`ready/preparing/needs-retry/unavailable`、是否可安全发送和是否可重试等无秘密投影，
不接收或展示 Leaf index、KeyPackage 私钥、epoch secret、Commit/Welcome 明文或 MLS
数据库内容。群业务成员仍按 DID 展示，不因同一 DID 有多个 Leaf 而出现重复成员。
默认建群请求不携带 `group-e2ee`、`e2ee=true` 或由 E2EE 派生的附件要求。

`awiki_im_core` Dart 公共接口通过
`client.secure.group(groupDid).status()/repair()` 承载 P6 v2 多设备 runtime。修复执行期间
App 强制投影“正在加入群加密”，不会保留旧的 ready 文案；只有 Core 返回可安全发送后才
显示“群加密已就绪”。通用 SDK 自身仍保持 fail-closed 默认；AWiki Me 保留 capability
不会绕过服务端能力校验，也不会把普通群自动升级为 E2EE 群。

设备撤销后，App 保留分页枚举及每群一次的公共修复调用，只跳过 Core 明确标识
`encrypted=false` 的普通群，避免把普通群不支持加密 repair 误报为“部分群同步未完成”。
列表缺少加密属性时，先通过现有公开 `getGroup` 读取同一精确群的状态；读取失败、返回其他群
或仍未知时不推断为普通群，保留原错误或修复路径。实际加密群修复失败继续显示部分完成，
不根据 Registry 撤销成功推断群密码学状态已就绪。

设备页的“部分相关群本次未能更新安全状态”只描述这一次后台修复的结果；普通接收同步
稍后完成时，该提示仍可保留。当前群的加密可用性始终取自 Core 对同一群返回的 Ready 与
可安全发送状态，不由设备页提示决定。设备撤销验收分别检查权威 Registry、已结束的修复
结果提示和当前群状态，并继续验证后续加密消息及被撤销设备读取拒绝。App 不为清除此提示
增加状态轮询或重复 repair，也不把提示当作 Remove 回执。

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

Recovery 群邀请回归需在配套新服务与新 Core 的候选中单独验证：既有加密群成员恢复身份，
接续完成前再 Join 一台设备（覆盖新设备排序在冻结设备之前），保持原群主客户端在线；
确认无需人工修改数据库即可先完成冻结设备 Add、旧 DID Remove，随后新增设备就绪。
此期间邀请应明确显示“尚未加入”，收敛后重试可成功邀请 DSH 身份并双向解密群消息。
再覆盖群主离线/重开、重复提示、冻结设备撤销时停止，不得把旧版本运行结果记为新代码通过。
该链路涉及 Message Service、Core 和 App/DSH，单元/Widget 通过不能代替定向 System 与产品 E2E。
