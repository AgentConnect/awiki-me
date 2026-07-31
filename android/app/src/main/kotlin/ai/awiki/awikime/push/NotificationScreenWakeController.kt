package ai.awiki.awikime.push

import android.app.NotificationManager
import android.content.Context
import android.os.Build
import android.os.PowerManager
import android.util.Log

object NotificationScreenWakeController {
    private const val MESSAGE_NOTIFICATION_CHANNEL_ID = "awiki_me_messages"
    private const val WAKE_DURATION_MS = 3_000L

    @Suppress("DEPRECATION")
    fun wakeIfNeeded(context: Context) {
        val notificationManager =
            context.getSystemService(NotificationManager::class.java) ?: return
        val powerManager = context.getSystemService(PowerManager::class.java) ?: return
        val notificationsEnabled =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                notificationManager.areNotificationsEnabled()
            } else {
                true
            }
        val channelImportance =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                notificationManager
                    .getNotificationChannel(MESSAGE_NOTIFICATION_CHANNEL_ID)
                    ?.importance
            } else {
                NotificationManager.IMPORTANCE_DEFAULT
            }
        if (
            !NotificationWakePolicy.shouldWake(
                isInteractive = powerManager.isInteractive,
                notificationsEnabled = notificationsEnabled,
                channelImportance = channelImportance,
            )
        ) {
            return
        }

        val wakeLock = powerManager.newWakeLock(
            PowerManager.SCREEN_BRIGHT_WAKE_LOCK or
                PowerManager.ACQUIRE_CAUSES_WAKEUP or
                PowerManager.ON_AFTER_RELEASE,
            "${context.packageName}:remote_push_notification",
        )
        wakeLock.setReferenceCounted(false)
        runCatching {
            wakeLock.acquire(WAKE_DURATION_MS)
        }.onFailure { error ->
            Log.w(
                "AWikiRemotePush",
                "Unable to wake screen for notification: ${error.javaClass.simpleName}",
            )
        }
    }
}
