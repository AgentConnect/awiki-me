# Handle Recovery V1 UI

Handle Recovery 是已有 Handle 登录/注册流程中的高风险分支，不再是首页独立入口。
首页只保留统一的登录/注册动作；当已验证的手机号、验证码和 Handle 对应一个已存在
Manifest 身份时，App 才让用户选择“加入新设备”或“恢复 Handle”。Recovery 选项仍要求
`AWIKI_MULTI_DEVICE_HANDLE_RECOVERY_ENABLED` 和当前租户 Server Info 的 phone Recovery
capability 同时开启。

选择 Recovery 后，Handle 和手机号以只读方式沿用已验证的 onboarding 上下文，页面不会
要求再次输入；注册授权会被丢弃，并立即请求 purpose 为
`awiki.identity.handle-recovery.v1` 的独立 Recovery OTP。注册/Join 与 Recovery 的重发
边界按 purpose 隔离，避免注册冷却阻止专用 Recovery OTP，同时仍分别遵守服务端返回的
`retry_at`。Recovery 不绑定当前激活身份，也不要求本机曾保存目标 Handle。

## 当前协议边界

- 当前 OTP purpose 固定为 `awiki.identity.handle-recovery.v1`。
- Core 在请求 Recovery OTP 前创建 opaque operation ID；OTP、Handle 和 operation ID 必须
  在 prepare 阶段保持同一绑定。统一 onboarding Recovery 不提供 selector；Core 按 Handle
  精确匹配本地身份，本地不存在时生成新的本地 owner 与身份材料。
- App 禁止把当前身份、`credentialName` 或 alias 当作恢复目标猜测。Core 返回本次
  operation 的 `ownerIdentityId`，后续 status/activate/resume 才按该 owner/operation 推进。
- OTP 仅作为瞬时输入传给 Core，App 不持久化 OTP、grant、密钥或证明材料。
- prepare 后 UI 必须展示 Handle 保留、其他设备重新加入、普通本地数据迁移以及
  E2EE/DID-only 限制等不可逆影响；用户明确确认后才允许 activate。
- 本地已有目标 Handle 时只迁移该身份的普通数据，不切换或覆盖其他身份；本地没有目标
  Handle 时 `localOrdinaryDataWillMigrate=false`，恢复完成后把新身份加入本地身份列表。
- activate 需要 user presence。正式 App 使用平台 LocalAuthentication；自动化 E2E
  只能覆盖测试专用 `UserPresencePort`，不能声称验证了真实系统认证。
- Core 是唯一恢复状态机。App 只展示粗粒度 phase，并在 Core 标记可恢复时提供精确
  resume；完成时持久化 Core 授权的 Registry epoch reset，并清理本地 locator。
- 当前 V1 不使用历史的 `awiki.device.recovery.begin.v1` /
  `awiki.device.recovery.finalize.v1`、旧管理设备通知或冷静期取消流程。

## UI E2E

`HANDLE-RECOVERY-V1-E2E-001` 先创建远端 ready-admin fixture，再销毁 setup root，并用一个
没有任何本地身份的 fresh App/native Core root 打开统一 onboarding。用同一 Handle 和手机号
完成登录/注册验证后选择 Recovery，再完成专用 OTP、风险确认、activate 和 bounded resume。
fixture 注册与 UI 验证复用同一测试手机号时，用例必须先遵守首个注册 OTP receipt 的
`retry_at`，并确认 UI 已把第二次 OTP 绑定到规范化 Handle/手机号后才允许提交，避免把
服务端冷却或异步请求竞态误判为产品恢复失败。
进入 Recovery 后还会断言已验证 Handle/手机号仅以只读上下文展示、页面只保留一个 Recovery
OTP 输入框，并且 Core 恰好收到一次同一 Handle/手机号且不带本地 identity selector。
最终 oracle 要求：Handle 保留、新的本地 owner 被安装、DID 被替换、Registry 只有一个
ready current admin，并且旧 DID 不出现在 fresh root 的 identity projection。该专项支持
Linux Flutter desktop runner，也可在 macOS runner 上执行。

同一 suite 的 `HANDLE-RECOVERY-V1-E2E-003` 在 Recovery 前用第二套独立 App root 建立旧 member。
Recovery 完成后先要求该旧 principal 的远端消息操作被拒绝，再使用 fresh ordinary Join
OTP/Grant 和 SAS 将同一旧 App 加入新 DID。最终两套 App 的 Registry 与 session 必须收敛，
并与第二个 App 中独立注册的外部 identity 双向各完成一条 Direct exact-one；恢复 App 发出的
消息还必须在 rejoined sibling 上形成 exact own-sync。该业务 case 在 Linux/macOS 使用相同
case ID、动作和 oracle，不包含双发起端、连续第二次 Recovery、revoke 或 MLS 完整矩阵。

独立的 `HANDLE-RECOVERY-REGISTRATION-REJOIN-E2E-001` 复用上述两套 fresh App root，但旧
member 不直接申请普通 Join OTP。它在旧 principal 被围栏后重新打开统一 onboarding，提交
existing Handle registration，并选择 Core 返回的 opaque continuation。App 只持有
`preparation_id/mode/requires_user_presence`，不接触 account verification token、Recovery
transition 或 owner 选择；一次 user presence 后由 Core 在同一进程消费 preparation 并建立
Recovery-aware Join。审批和激活后执行标准 Root/P5，要求 rejoined peer 成为
management-ready admin，且 P5 不进入普通消息历史，随后双向 Direct 各精确一次。该 case 在
显式 Linux/Xvfb 或 macOS `awiki.info` 配置下运行：

```bash
dart run tests/e2e/runner.dart \
  --case multi-device-app-pair-recovery-registration-rejoin \
  --config <explicit-awiki-info-config.yaml>
```

```bash
AWIKI_MULTI_DEVICE_REMOTE_RECOVERY_E2E_ENABLED=1 \
AWIKI_MULTI_DEVICE_E2E_HANDLE_PREFIX=recovery \
dart run tests/e2e/runner.dart \
  --case multi-device-remote-recovery \
  --config <local-awiki-info-config.yaml>
```

该 suite 只允许受审计的 `https://awiki.info` 配置。注册和 Recovery 复用 ignored、
权限受限的 local YAML 中同一个测试手机号和六位固定验证码；仍须先调用真实、精确绑定
purpose/Handle/operation ID 的短信接口。OTP 只在测试进程内读取并注册到 redactor，不能
写入 run config、版本控制文件、attestation、诊断或报告。

缺少专用账号、固定 OTP 配置、远端 capability 或短信请求成功时，只能报告未执行/失败，
不能把编译通过当作远端 Recovery 已通过。
