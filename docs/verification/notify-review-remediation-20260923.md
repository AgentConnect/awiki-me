# Notify 修复 PR #37 的审查整改

## 范围与行为

已合入 `release/0910` 的 `c0766135bab0eb730f6148806b886a62ababea16`。处理 Medium 发现：用户取消锁屏解锁后，后续紧急提醒复用旧弹窗时仍保留旧消息。

`TextNotifyAlertActivity.onNewIntent` 重新绑定当前 payload/token，重建内容与倒计时，并清理旧查看状态。系统解锁回调携带消息代次，Android 7 的凭据请求也使用不同请求号，旧结果不得打开新消息。相同提醒重复投递保留已有解锁请求，保存状态包含最新消息，账号与过期检查仍通过既有入口执行。

App 源码依赖固定到 Core #46 的 `5a27c50097e9b4ab36bd792590ccd14ed770bcf6`。

## PASS：本地 Android 验证

命令：`JAVA_HOME=/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home android/gradlew -p android :app:testDebugUnitTest --console=plain`

47 项通过，0 失败/错误/跳过；其中 Activity 14 项，API 24/28/35。新增 6 项覆盖：

- 取消解锁后，新 Intent 的关闭动作停止新的声振 token；
- 旧解锁成功回调不打开新消息，显式查看才打开正确消息；
- 重建后保留最新消息，即使启动 Intent 仍是旧值；
- 相同 Intent 重复投递不打断正在进行的解锁；
- 新消息的通知栏查看动作在 resume 后解锁并打开；
- Android 7 旧凭据结果不能打开替代提醒。

## BLOCKER / UNVERIFIED

本次没有安装手机测试包或触发真实通知；上述并发及重建场景的 M153 真机表现仍为 UNVERIFIED，不能复用之前候选包的设备证据宣称新 HEAD 已验收。Core #46 的 registry/固定 SDK CI 门禁需独立核对；源码验证通过也不等于具备合并条件。本次没有发版、部署或修改服务端。
