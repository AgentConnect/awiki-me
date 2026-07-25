package ai.awiki.awikime.push

import android.content.Context
import android.content.Intent
import com.alibaba.sdk.android.push.MessageReceiver
import com.alibaba.sdk.android.push.notification.CPushMessage

class AwikiAliyunPushReceiver : MessageReceiver() {
    override fun onNotification(
        context: Context,
        title: String?,
        summary: String?,
        extraMap: MutableMap<String, String>?,
    ) {
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
