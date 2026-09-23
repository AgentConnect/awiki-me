# Text Notify Android review regression acceptance

Status: planned; no new real-device attestation in this review-fix batch.
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
尚不代表该候选已安装或通过真机验收。

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
本轮尚未覆盖安装 M153，未声称系统认证或完整 Core 会话跳转已在修复包通过。

The native Robolectric and Dart tests cover deterministic decisions and
persistence/concurrency behavior. They do not attest M153 display, vibration,
sound, background survival or the real server-to-device transport.
