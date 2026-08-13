package ai.awiki.awikime

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

class AliveBackgroundUrgentDismissReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val nativeId = intent.getIntExtra(EXTRA_NATIVE_ID, -1)
        if (nativeId < 0) return
        AliveBackgroundUrgentNotificationController.cancel(
            context.applicationContext,
            nativeId,
            AliveBackgroundUrgentStopReason.NOTIFICATION_REMOVED,
        )
    }

    companion object {
        const val EXTRA_NATIVE_ID = "native_id"
    }
}
