# AWiki Me 多设备加入、设备页与永久撤销

状态：消息驱动的 member Join 默认存在；根导入、永久撤销和 E2EE 不属于本步骤

整体身份和密码学方案以 Core 仓库中的
[多设备架构](../../awiki-cli-rs2/docs/architecture/multi-device/multi-device-architecter.md)
和[架构概览](../../awiki-cli-rs2/docs/architecture/multi-device/multi-device-architecture-overview.md)
为准。本文只记录 AWiki Me 的产品边界与 UI 状态流。

## 1. 产品入口与开关

多设备入口不再由 `AWIKI_MULTI_DEVICE_ENABLED` 控制注册协议或产品可见性：

- 已登录用户可从“设置 → 设备”查看当前设备、已授权设备和待审批请求；
- 未登录首页只显示统一登录/注册；当已验证 Handle 已存在时，用户可选择“加入新设备”；
- V1 只比较两端独立计算的 6 位验证码，不提供二维码或扫码入口。

永久撤销由独立编译期开关 `AWIKI_MULTI_DEVICE_DEVICE_REVOKE_ENABLED` 控制，默认
`false`。它只开放撤销动作；关闭时仍可进入设备页读取权威 Registry。

设备级 Direct 产品路径由编译期开关 `AWIKI_MULTI_DEVICE_DIRECT_E2EE_ENABLED` 控制，
默认 `false`。App 只把该值传给 `AwikiImCoreOpenOptions`，不新增 UI；它与 Join、根密钥
传输、永久撤销和 Group E2EE 开关彼此独立，也不进入跨域协议字段。V1 不提供 Handle
Recovery 服务或远端流程，只显示明确的不支持提示。

## 2. App 状态流

```text
新设备：统一登录/注册中的 Handle + SMS OTP
  -> AWiki 域内 account-verification exchange 返回一次性 grant
  -> App 显示“加入新设备 / 恢复 Handle”选择
  -> 选择 Join 后 data adapter 将内存中的 grant 立即交给 Core 单次消费
  -> Core 创建并持久化 Join
  -> App 轮询无秘密进度并短暂显示 6 位 SAS
  -> Core finalization 得到 active + member + management_ready=false
  -> App 按精确 DID 激活已经提交的本地 Identity
  -> authorized / cancelled / expired

已有管理设备：可信 system_notification_changed
  -> Core 验证、提交标准 P3 系统通知并形成 local Join inbox
  -> App 立即把该事件作为设备域失效信号，独立刷新 local_device_join_requests
  -> reliable message sync 仍并行执行，但其失败或退避不阻塞 Join inbox
  -> AppShell 展示全局“查看并验证”入口
  -> 用户打开请求（只读，不 claim、不验证、不批准）
  -> 用户明确点击“开始验证”
  -> Core 原子绑定 claimant、生成 challenge 并发送 JoinClaimed
  -> ResponseVerified 后 Core 才向本机投影 6 位 SAS
  -> 用户确认两端一致
  -> 一次系统 user-presence
  -> Core 固定按 member 完成授权
```

新设备重启后只恢复仍在有效期内、拥有精确本地 DID/device binding，且实时 Registry 仍确认
为本机 active member 的 Session 摘要，并继续使用新设备 status poll。历史 `authorized`
记录、已撤销身份、仅 DID 相同但 device 不同的记录都不能恢复成“设备已加入”；网络暂时不可用
时保持失败关闭，而不是把未验证的本地记录当成当前 Join。管理设备不再通过 HTTP pending
list、status timer 或 admin poll 发现/推进 Join，只恢复 Core 已验证的本地通知投影与本机
verification progress。App 不把 SAS 写入 `ProductLocalStore`、偏好设置或 E2E
报告；终态由 Core 投影，重复点击由 service/provider 和 Core 幂等门禁共同拒绝。请求已由
另一台管理设备处理时只读展示，不能继续验证或批准。

管理设备完成授权后，服务端会消费 Join 请求并把它从待审批 inbox 移除；这不表示本机授权
终态失效。只要 Core 已返回同一 Join Session 的 `authorized`，审批页就保留“设备已加入”
直到用户关闭页面。App 不得因为后续 inbox 对账找不到已消费请求，就退回打开页面时缓存的
`responseVerified` 请求并再次显示“等待管理设备响应”。

新设备的 `authorized + consumed` 投影通过精确 DID 激活本地 member 会话时，Devices
provider 只跨这一次“未登录 → 同 DID”切换保留该终态，避免通用 session reset 把成功页
提前清空；登录其他 DID、退出登录或后续 session 切换仍完整清空设备状态。页面轮询始终由
widget lifecycle 约束：每个异步边界后重新检查页面是否仍挂载，页面销毁后不得读取
Riverpod `ref`、激活身份或继续更新 UI。

## 3. 安全边界

AWiki Me 只持有可展示的设备摘要、Join 阶段和一次性审批句柄。设备签名私钥、设备
E2EE 私钥、配对共享秘密、challenge 明文和 DID 根私钥始终留在 Core/Vault。
SMS OTP 只进入发起方法；域内 exchange 返回的 account grant 只存在于 data adapter
的进程内 continuation map。presentation 只持有 opaque continuation ID；选择 Join 时 grant
才交给 Core 单次消费，选择 Recovery 或取消时立即丢弃。grant 不进入日志、错误、持久化
或跨域协议，Join 页面也不再重复采集 Handle、手机号或注册 OTP。
发码端返回 HTTP `429` 时，User Service 的 `Retry-After` 是重试时间的机器可读事实源；
data adapter 只把有界秒数投影为 typed rate-limit error，不向 presentation 透传 Problem
JSON 或供应商详情。Join 页面显示明确的“发送过于频繁”提示并在剩余时间内禁用重发，
不得将限流降级为通用“设备操作失败”。发码成功时，adapter 同样只返回不含手机号、
Handle 或供应商信息的重发等待时间；页面按手机号与 Handle 组成的当前目标维护短生命周期
倒计时，发送中禁用重复请求，成功后给出轻量提示。切换目标只切换当前展示的倒计时，
不会丢失原目标尚未结束的重发边界。

JoinRequested / JoinClaimed / JoinResponseVerified 是通用系统通知承载的业务 payload。
Message Service 按标准 P3 signed message 传输，Core 负责验证可信 service DID、proof、
audience、expiry 和业务绑定并提交本地投影。AWiki Me 只消费
`system_notification_changed` 信号和 Core 的 typed local projection，不解析 P3 JSON、
不验证 proof，也不把通知 title/body 投影成普通聊天、conversation 或 timeline。该信号只
触发设备域读取；全局审批入口完全来自 Core 返回的 typed local Join projection，不能直接
使用 realtime payload 作为 UI 真相。入口只打开审批页，不会自动执行开始验证、拒绝或批准。

未登录新设备没有 current Core identity，因此不能复用要求已选身份的 Directory adapter。
onboarding 注册流程不在发送 OTP 或提交注册前用未认证的 public-profile 查询 Handle，
也不再根据查询结果分派注册或恢复协议。现有 Join adapter 的 Handle 解析仍属于 Join
自身的 account-verification 边界，将在后续 Join 专项步骤随 Core 新入口一起收敛；它不能
被注册流程复用为身份状态探针。

注册 application 边界只接收 Core 的 `registered` / `joinRequired` 两种结果：

- `registered` 携带已持久化身份，App 才激活会话并更新资料；
- `joinRequired` 不携带身份或秘密材料，只携带 App 内 opaque continuation ID；App 显示
  Join/Recovery 选择，只有用户选择 Join 后才创建 Join 并打开进度页；
- 任何未知状态都失败关闭，App 不猜测、不回退到旧 Recovery，也不在本地保存中间密钥。

新注册的 P5 PreKey Bundle 生成和发布仍由 Core 注册事务在本地提交后继续负责。AWiki Me
不得跳过或替代这段调用链，也不得删除仅为迁移而改名的原 publication helper。Legacy →
Manifest 升级同样只消费 Core 后续提供的 typed `running` / `retryRequired` 投影；App
不得因身份进入 VNext 就删除 Legacy key-2/key-3、既有 PreKey、Session、Ratchet 或 MLS
state，这些历史解密与迁移材料的兼容窗口和清理条件由 Core 明确定义。

AWiki Me 只维护一个当前 access token 会话，不引入 refresh token 或 device token。正常
请求使用 `Authorization: Bearer`；401 时通过 `AuthSessionCoordinator` singleflight
触发一次新的 DID-WBA 签名请求获取 access token，并只重放原请求一次。并发请求共享同一
次续期，第二次 401 直接向上返回。若 V1 部署期保持 User Service JWT signing key 不轮换，
这只是上线部署约束，不能据此宣称 Message Service 已完整实现基于 `kid` 的多 key 验签。

Join V1 不提供 `admin` 选择，也不因批准 Join 触发根密钥传输；结果固定为
`active + member + management_ready=false`。管理员升级和普通 P5 RootKeyEnvelope 属于
第三步，当前保留的旧 root-control 实现不能从本 Join 流程被调用。

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
flutter test tests/unit/app_runtime_notification_test.dart \
  tests/unit/message_sync_coordinator_test.dart \
  tests/unit/data/im_core/awiki_im_core_mappers_test.dart \
  tests/unit/data/im_core/awiki_im_core_device_management_adapter_test.dart \
  tests/unit/devices/device_management_service_test.dart \
  tests/unit/devices/devices_ui_test.dart
```

本步骤只接受上述消息驱动 Join focused tests，不执行完整 AWiki Me `full` 或第三步的
Root/MLS E2E。现有 `multi-device-remote-join` runner 中依赖 Registry pending discovery、
split claim/admin poll、admin toggle 或旧 root-control 的场景不能作为本步骤通过证据；
两个 Join 方向必须由真实 listener/system-notification 入口推进：CLI 管理端以专用
`im.device.join.requested` host event 唤醒，App 管理端等待 AppShell 全局审批入口；测试
不得直接调用 Message Inbox hydration、`requestSync()` 或 `refreshJoinInbox()` 代替唤醒。
实现存在不等于远端已通过，仍需独立的 `awiki.info` pass attestation。

App↔App 验证使用独立的 `multi-device-app-pair` suite 和
`DEVICE-JOIN-E2E-004`。它在同一台 macOS 上运行两个 bundle/build/state 均隔离的真实
App 进程，管理端仍必须由 `system_notification_changed` → Core typed Join inbox →
AppShell 全局入口发现请求，加入端仍通过可见 onboarding UI 发起。测试协调器只交换阶段
checkpoint，并在内存中比较两端 SAS，不得替代产品同步或记录秘密。完整运行边界见
[One-host App↔App E2E mode](multi-device-app-pair-e2e.md)。
