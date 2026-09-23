# Text Notify Android review regression acceptance

Status: broader matrix planned; focused M153 lock-screen View acceptance passed on 2026-09-23 (evidence below).
Owner: AWiki Me Android product E2E. Existing System Test
`tests_v2/message_service/test_text_notify.py` owns service annotation,
replay/history/offline-sync checks; native display is not its oracle.

Use the same authorized M153 and local Debug build, real Skill/CLI send path,
and existing test identities. Record exact App/CLI SHAs and system permission
state. Each message gets its own event/message identity; do not resend an
uncertain event. Do not use Debug probe as product evidence.

1. Start one urgent cue, then deliver one normal and one different urgent text.
   Require one unchanged cue deadline and two separate silent notification-list
   entries. Open each and verify its original message. Redeliver the same
   provider message during and after the cue: no duplicate entry or later ring.
2. Upgrade without clearing App data from a build with a muted Direct (also
   hidden in recents). After login, send normal and urgent texts to that peer:
   chat content remains available, no native cue/banner. Unmute through UI;
   subsequent authorized messages may alert. Simulate mirror failure, require a
   visible paused state, preserved canonical mute and successful explicit retry.
3. Switch A → B while hydration is pending, then back to A. No old callback may
   activate B's presentation or remove A's mute. Consent remains per account.
4. With a bounded test clock offset, use server expiry 120 seconds and a device
   clock five seconds behind, one-second transport delay: fresh message alerts.
   Expired and >30-second future-tolerance-bound messages must not start a cue.
   Restore clock and settings after the test.
5. During the active cue verify mute, master-off, View, Close and 60-second stop.
   Notify passive slots are removed for muted peers/master-off/account switch;
   unrelated chat notifications remain. Preserve message history.

## 锁屏查看消息回归（2026-09-23）

用户已报告 0.1.31 在 M153 锁屏下“查看消息”不能打开会话；以下是修复候选的必验步骤，
安装与启动结果见下文；最新候选已通过进程存在时的锁屏点击跳转，其他变体仍待真机验收。

1. 使用真实 Skill Agent 发送一条新的 urgent Notify。锁屏全屏提醒中点击“查看消息”：
   声振立即停止，系统要求正常解锁；通过用户认证后自动打开 AWiki Me 的原消息会话。
   分别覆盖 App 进程已存在和冷启动，不在锁屏上展示聊天正文。
2. 取消解锁：不能导航、不能恢复声振；等待超过原 60 秒截止后仍可点击查看并成功打开。
3. 双击查看、旋转或系统重建提醒页：保留同一消息目标，不重复投递打开事件。
4. 分别从通知栏“查看消息”、60 秒后的普通通知点击进入；解锁与消息路由行为一致。
5. 点击关闭只停止提醒。解锁期间账号/租户发生变化时，旧消息不能打开到其他账号。

自动化覆盖：`TextNotifyAlertActivityTest` 在真实 Activity、Keyguard callback 和持久事件桥边界
验证打开前没有路由、停止声振后的等待、取消重试、重建、关闭与账号隔离；不代替真机声振与认证验收。

本地验证记录：App 基线 `883968c135b7ce0a343dd551e9ddfa2998cf5562`，本地 Dart wrapper 使用
Core `457845db7e483ccdcdb5556decd209125db44ca9`。旧 Notify wrapper 缺少新基线的 `caBundle`
参数，首次编译失败后改用该配套 0910 源码；没有修改正式依赖清单或发布任何依赖。
JDK 17 执行 `android/gradlew -p android :app:testDebugUnitTest --console=plain`：
41 passed、0 failed、0 skipped；新增 8 项含 Android API 28 与 35。将 Activity 临时还原为
基线代码时，锁屏查看用例按预期失败（尚未解锁就已发出打开事件）；恢复修复后全组通过。
### M153 本地安装与启动（2026-09-23）

- PASS：App 修复提交 `708d0425a7b5ac72687fc09207c87fed7674b573` 与上述 Core
  源码完成 arm64 原生库及 Flutter Debug APK 本地构建。未发版。
- 首次测试构建误用默认 `lib/main.dart` 入口，读取了另一套旧数据并报 `vault_key_missing`。
  原开发版 APK 的实际入口是已有 `tool/run_android_notify_diagnostic.dart`，使用
  `notify-diagnostic` 独立 state root 与真实平台 secret provider。恢复原 APK 后账号与会话正常。
- 改用原诊断入口后，本地版本名 `0.1.31-lockscreen-local` 又触发 Core 的纯数字版本格式
  校验，报 `invalid_input`。将版本名改为合法的 `0.1.31` 后启动正常。
  两个测试构建配置问题均已解决，没有修改 vault、迁移或 Core 校验逻辑。
- PASS：最终修复包 `ai.awiki.awikime.dev`、`0.1.31`、versionCode 2042 同签名覆盖安装，
  原已登录账号与原聊天列表可见。未清数据、重置账号或执行恢复；没有启用 E2E fake provider。
- PASS：主应用 `ai.awiki.awikime` 保持 `0.1.31`（versionCode 2041），未覆盖。
- PASS：用户确认使用开发版现有账号后，通过 App 设置开启该账号的紧急提醒。
  真实 Skill Agent 消息 `msg-notify-20260923-lockview-02` 于 `2026-09-23T04:29:42.273146Z`
  被服务端接受；M153 随后在安全锁屏状态自动展示该消息的 `TextNotifyAlertActivity`。
- PASS：点击“查看消息”后出现系统面部/指纹认证界面；`TextNotifyAlertService` 已停止。
  随后观察到 Keyguard 已解除，焦点进入 `.dev` 的 `MainActivity`。
- 初次验收 BLOCKER（后续已解决，见下节）：App 停留在消息列表，目标消息未显示。原生桥记录了 `notification_opened`，
  Flutter 回执为 `retryableFailure`、`pending=1`。通过现有 Core `pendingProcessing()` API
  读取到 `MessageProcessingStatus.retrying:sync.peer_resolution_pending`，表示该条消息仍在等待
  verified peer identity。发送方位于 anpclaw.com，接收方位于 awiki.info；尚未证明具体失败点，
  不将它直接归因于 Keyguard 或跨域服务。不能因此宣称原消息路由通过。
- 初次验收 UNVERIFIED：最终消息定位、取消解锁后重试、冷启动路由，以及用户现场声振停止确认。
  为读取上述安全诊断码临时热重载了 adapter，仅调用公开 Core API；随后已撤回全部临时代码。
  未修改 Core、服务端、账号或数据库以绕过待解析状态。
- 发送前另遇 CLI 设备 bearer 不可用，通过官方 `id refresh-token` 恢复同一身份。
  首条 `msg-notify-20260923-lockview-01` 在请求前失败，同编号重试返回
  `message_retry_conflict`；本地记录保留为 pending，未删除、改写或继续重试。第二条是独立测试事件。

可复现本地构建参数：`flutter build apk --debug --target-platform android-arm64
--target tool/run_android_notify_diagnostic.dart --build-name 0.1.31 --build-number 2042`，
附带上述 App/Core source-ref defines。诊断入口只隔离 state root；本次仍需完整真实消息验收。
2042 APK SHA-256：`669144cd0a6c9a841b15dae46066ea3928e6bcbe9f82b3a7831c6690851eef2d`。


### 跨服务身份解析修复与最终点击复验（2026-09-23）

- 根因：本地 Directory 对首次遇到的外域 Skill Agent DID 返回 Handle 不存在，Core 未从
  DID document 的 `ANPHandleService` 发现公开绑定，因此消息一直处于待解析状态。
  Core PR #46 增加严格限定的 not-found fallback；验证 DID 文档、HTTPS endpoint、有效绑定、
  generation 与精确 Handle/DID 后才投影。认证错误和冲突不回退，没有修改 User/Message Service。
- 使用 App `708d0425a7b5ac72687fc09207c87fed7674b573` + Core
  `36835746cbab3b72a84efe9e955f903c04502533`，ANP
  `0ba814aadc6567cdba366a0550f79e433233e687`、Identity
  `65a79d2644a065942004fad6272ea8b8b6b792f4` 构建 Android arm64。
  这些是实际本地源码版本，不代表 registry 或 CI 固定依赖已经验证通过。
- PASS：Core Handle discovery 31 项、directory runtime 5 项，共 36 项测试通过；Android
  原生库与本地 Debug APK 构建通过。同一诊断入口和 numeric 版本名，build number 改为 2043。
  APK SHA-256：`da834790f154f8408b5b8941786e8efd2919fba0a2cc8c1ac3e7894289de8fa6`。
- PASS：同签名覆盖 `.dev`，保留账号、消息和通知设置。设备日志为本地时间 **12:57:59.985**：旧 pending 消息 `committed=1`，列表可见复验 02。
  旧打开事件 `matched=false`，不将其计为路由通过。
- PASS：复验 03 发送前读取到 `showing=true / secure=true`。消息
  `msg-notify-20260923-lockview-03` 于 `2026-09-23T05:01:50.337577Z` 被真实服务接受。
  本地时间 13:01:52 收到推送并显示 `TextNotifyAlertActivity`；13:01:56.824 收到
  `notification_opened`；13:01:57.275 为 `receipt=succeeded / recovered=1 / matched=true`。
- PASS：复验 03 期间测试端没有手动启动 MainActivity 或点击聊天列表；随后 UI hierarchy 显示
  目标会话内含复验 02 与 **复验 03** 的正文，MainActivity 在前台、Keyguard 已解除，
  `TextNotifyAlertService` 不再运行。完整的“锁屏提醒 → 点击 → 解锁 → 自动打开原消息会话”
  在该进程已存在场景通过。系统解锁由设备侧完成，未绕过认证。
- UNVERIFIED：复验 03 没有用户对物理声振停止的额外口头确认；冷启动、取消解锁后重试、
  旋转/重建等真机变体未执行。自动测试覆盖不等价于这些真机验收。
- BLOCKER（合并门禁）：Core 的源码集成检查通过，但 registry 检查找不到精确依赖
  `awiki-im-core = 0.1.5`，Node 检查缺少固定 ANP/Identity 版本的 API。
  因此仍保留 Draft；局部真机成功不代表跨平台 CI 或发布依赖就绪。未进行发布或部署。

The native Robolectric and Dart tests cover deterministic decisions and
persistence/concurrency behavior. They do not attest M153 display, vibration,
sound, background survival or the real server-to-device transport.
