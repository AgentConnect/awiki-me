package ai.awiki.awikime.push

import android.app.Notification
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.core.app.NotificationCompat
import com.alibaba.sdk.android.push.MessageReceiver
import com.alibaba.sdk.android.push.notification.CPushMessage
import com.alibaba.sdk.android.push.notification.NotificationConfigure
import com.alibaba.sdk.android.push.notification.PushData

class AwikiAliyunPushReceiver : MessageReceiver() {
    // EMAS 3.10.1 invokes this on its own NOTICE construction path. Keep one
    // presenter; do not post a second local notification from a receiver callback.
    override fun hookNotificationBuild(): NotificationConfigure = object : NotificationConfigure {
        override fun configBuilder(builder: Notification.Builder, data: PushData) = Unit
        override fun configBuilder(builder: NotificationCompat.Builder, data: PushData) = Unit

        override fun configNotification(notification: Notification, data: PushData) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
                notification.channelId == UrgentNotificationChannel.ID) {
                // Requires the server to reuse AndroidNotificationNotifyId.
                // This is not a durable dedupe receipt after dismissal/reboot.
                notification.flags = notification.flags or Notification.FLAG_ONLY_ALERT_ONCE
            }
        }
    }

    override fun showNotificationNow(
        context: Context,
        extraMap: MutableMap<String, String>?,
    ): Boolean {
        return RemotePushPresentationState.shouldShowNotification(extraMap)
    }

    override fun onNotification(
        context: Context,
        title: String?,
        summary: String?,
        extraMap: MutableMap<String, String>?,
    ) {
        NotificationScreenWakeController.wakeIfNeeded(context)
        emit(
            context,
            "notification_received",
            mapOf("title" to title, "summary" to summary, "extraMap" to extraMap),
        )
    }

    override fun onNotificationReceivedInApp(
        context: Context,
        title: String?,
        summary: String?,
        extraMap: MutableMap<String, String>?,
        openType: Int,
        openActivity: String?,
        openUrl: String?,
    ) {
        emit(
            context,
            "notification_received_in_app",
            mapOf(
                "title" to title,
                "summary" to summary,
                "extraMap" to extraMap,
                "openType" to openType,
                "openActivity" to openActivity,
                "openUrl" to openUrl,
            ),
        )
    }

    override fun onMessage(context: Context, message: CPushMessage) {
        emit(
            context,
            "message_received",
            mapOf(
                "title" to message.title,
                "content" to message.content,
                "msgId" to message.messageId,
                "appId" to message.appId,
                "traceInfo" to message.traceInfo,
            ),
        )
    }

    override fun onNotificationOpened(
        context: Context,
        title: String?,
        summary: String?,
        extraMap: String?,
    ) {
        emitOpened(context, title, summary, extraMap, launchApplication = false)
    }

    override fun onNotificationClickedWithNoAction(
        context: Context,
        title: String?,
        summary: String?,
        extraMap: String?,
    ) {
        emitOpened(context, title, summary, extraMap, launchApplication = true)
    }

    override fun onNotificationRemoved(context: Context, messageId: String?) {
        emit(context, "notification_removed", mapOf("msgId" to messageId))
    }

    private fun emitOpened(
        context: Context,
        title: String?,
        summary: String?,
        extraMap: String?,
        launchApplication: Boolean,
    ) {
        emit(
            context,
            "notification_opened",
            mapOf("title" to title, "summary" to summary, "extraMap" to extraMap),
        )
        if (!launchApplication) return
        val launchIntent = context.packageManager.getLaunchIntentForPackage(context.packageName)
            ?: return
        launchIntent.addFlags(
            Intent.FLAG_ACTIVITY_NEW_TASK or
                Intent.FLAG_ACTIVITY_CLEAR_TOP or
                Intent.FLAG_ACTIVITY_SINGLE_TOP,
        )
        context.startActivity(launchIntent)
    }

    private fun emit(context: Context, kind: String, payload: Map<String, Any?>) {
        RemotePushEventBridge.emit(context, kind, payload)
    }
}
