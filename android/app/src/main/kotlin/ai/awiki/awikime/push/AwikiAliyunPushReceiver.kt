package ai.awiki.awikime.push

import android.content.Context
import android.content.Intent
import android.util.Log
import ai.awiki.awikime.AliveBackgroundSyncScheduler
import com.alibaba.sdk.android.push.MessageReceiver
import com.alibaba.sdk.android.push.notification.CPushMessage

class AwikiAliyunPushReceiver : MessageReceiver() {
    override fun showNotificationNow(
        context: Context,
        extraMap: MutableMap<String, String>?,
    ): Boolean {
        logTransportGate(BackgroundUrgentTransportDiagnostics.fromNoticeCallback(extraMap))
        return RemotePushPresentationState.shouldShowNotification(extraMap)
    }

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
        logTransportGate(BackgroundUrgentTransportDiagnostics.fromMessageCallback())
        emit(
            context,
            "message_received",
            mapOf("msgId" to message.messageId),
        )
        try {
            AliveBackgroundSyncScheduler.enqueue(context)
        } catch (error: RuntimeException) {
            Log.w("AWikiRemotePush", "alive_background_sync enqueue failed", error)
        }
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

    private fun logTransportGate(diagnostic: BackgroundUrgentTransportDiagnostic) {
        // Keep this native-only and low-cardinality.  Do not include a provider
        // payload, marker ID, identity, title, content, or ticket in logs.
        Log.i(
            "AWikiRemotePush",
            "background_urgent_transport_gate callback=${diagnostic.verdict.callback} " +
                "blocker=${diagnostic.verdict.blocker} " +
                "probe=${diagnostic.isolatedProbeMarkerPresent}",
        )
    }
}
