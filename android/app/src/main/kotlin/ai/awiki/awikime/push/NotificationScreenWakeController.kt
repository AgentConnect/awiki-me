package ai.awiki.awikime.push

import android.content.Context
import android.os.PowerManager
import android.util.Log

object NotificationScreenWakeController {
    private const val WAKE_DURATION_MS = 3_000L

    @Suppress("DEPRECATION")
    fun wakeIfNeeded(context: Context) {
        val powerManager = context.getSystemService(PowerManager::class.java) ?: return
        if (powerManager.isInteractive) return

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
