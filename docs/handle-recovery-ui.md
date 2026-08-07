# Handle Recovery V1 UI

Handle Recovery 是一个默认关闭的高风险身份恢复入口。AWiki Me 只有在本地
`AWIKI_MULTI_DEVICE_HANDLE_RECOVERY_ENABLED` 为真，并且当前租户的 Server Info
声明支持 phone Handle Recovery 时，才会在已登出但仍保留本地凭据的 onboarding
页面显示该入口。

当前人工联调构建还会在登录/注册表单下方显示一个临时的全局“恢复 Handle”按钮。
该按钮只在上述双重 capability 门禁通过时出现。全局入口不绑定当前激活身份：用户输入
完整 Handle 后，Core 先在本地多身份索引中精确匹配；本地不存在时使用公开 WNS 当前
binding，并在手机号验证成功后新增恢复身份。远端人工验证完成后必须删除该临时按钮。

## 当前协议边界

- 当前 OTP purpose 固定为 `awiki.identity.handle-recovery.v1`。
- App 先生成 opaque operation ID，再请求 OTP；OTP、Handle 和 operation ID 必须在
  prepare 阶段保持同一绑定。身份卡入口可以提供精确本地 selector；全局入口不提供
  selector，由 Core 按 Handle 精确匹配本地身份或创建新的本地身份。
- App 的 session projection 必须同时保留 Core `identityId` 与用户可见的 local alias；
  身份卡 Recovery 只传前者。全局 Recovery 传空 selector，禁止把当前身份、
  `credentialName` 或 alias 当作目标猜测。
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

`HANDLE-RECOVERY-V1-E2E-001` 使用一个 fresh App/native Core root 创建 ready-admin
fixture，登出后从可见入口完成发码、OTP、风险确认、activate 和 bounded resume。
最终 oracle 要求：Handle 和稳定本地 selector 不变、DID 被替换、Registry 只有一个
ready current admin，并且旧 DID 不再出现在本地 identity projection。该专项支持 Linux
Flutter desktop runner，也可在 macOS runner 上执行。

```bash
AWIKI_MULTI_DEVICE_REMOTE_RECOVERY_E2E_ENABLED=1 \
AWIKI_MULTI_DEVICE_E2E_PHONE=<dedicated-test-phone> \
AWIKI_MULTI_DEVICE_E2E_OTP_COMMAND_JSON='<reviewed-json-argv-resolver>' \
AWIKI_MULTI_DEVICE_E2E_HANDLE_PREFIX=recovery \
dart run tests/e2e/runner.dart \
  --case multi-device-remote-recovery \
  --config <local-awiki-info-config.yaml>
```

该 suite 只允许受审计的 `https://awiki.info` 配置。注册和 Recovery 可以复用 ignored
local YAML 中同一个测试手机号和六位固定验证码；也可以使用 JSON-argv resolver。resolver
从 stdin 接收 phone、purpose、裸 Handle、Handle domain 以及 Recovery operation ID，
stdout 只能返回 `{"otp":"123456"}` 形状。shell command string、staged SMS-error
continuation、把 OTP 写入受版本控制文件或报告都被拒绝。

缺少专用账号、resolver、远端 capability 或真实短信成功时，只能报告未执行/失败，
不能把编译通过当作远端 Recovery 已通过。
