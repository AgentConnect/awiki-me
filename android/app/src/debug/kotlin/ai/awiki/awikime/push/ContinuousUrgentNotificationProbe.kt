package ai.awiki.awikime.push

import android.app.Notification
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.SystemClock
import android.util.Log
import androidx.core.app.NotificationManagerCompat

/** Debug-only C0 experiment. No IM authority, background service, or periodic push. */
internal object ContinuousUrgentNotificationProbe {
    const val ID = 924040
    private const val PREFS = "continuous_urgent_platform_probe"
    private const val TOKEN = "last_token"
    private const val DEADLINE = "deadline"

    fun post(context: Context, token: String): String {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return "unsupported"
        if (token.isBlank() || token.length > 80) return "invalid_token"
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        // Consumed even after cancellation/timeout. A repeated test delivery never reposts.
        if (prefs.getString(TOKEN, null) == token) return "duplicate_ignored"
        val manager = context.getSystemService(NotificationManager::class.java)
        if (manager.activeNotifications.any { it.id == ID }) return "already_active"
        if (!NotificationManagerCompat.from(context).areNotificationsEnabled()) return "permission_denied"
        UrgentNotificationChannel.ensureCreated(context)
        if ((manager.getNotificationChannel(UrgentNotificationChannel.ID)?.importance ?: 0) < 4) {
            return "channel_disabled"
        }
        val deadline = SystemClock.elapsedRealtime() + 60_000
        if (!prefs.edit().putString(TOKEN, token).putLong(DEADLINE, deadline).commit()) {
            return "persistence_failed"
        }
        val stop = PendingIntent.getBroadcast(context, ID,
            Intent(context, ContinuousUrgentProbeStopReceiver::class.java).putExtra(TOKEN, token),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        val view = PendingIntent.getActivity(context, ID,
            Intent(context, UrgentNotificationProbeActivity::class.java)
                .addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP)
                .putExtra("continuous_stop_token", token),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        val notification = Notification.Builder(context, UrgentNotificationChannel.ID)
            .setSmallIcon(context.applicationInfo.icon)
            .setContentTitle("AWiki 持续提醒测试 · 最长60秒")
            .setContentText("查看或关闭立即停止。这是本机平台测试。")
            .setContentIntent(view)
            .setDeleteIntent(stop)
            .addAction(Notification.Action.Builder(null, "关闭提醒", stop).build())
            .setAutoCancel(true)
            // OS-owned cancellation survives loss of this Activity/process.
            .setTimeoutAfter(60_000)
            .build().apply { flags = flags or Notification.FLAG_INSISTENT }
        // Never combine ONLY_ALERT_ONCE with reposts: updates may stop ongoing alerting.
        manager.notify(ID, notification)
        Log.i("AwikiContinuousProbe", "posted deadline_elapsed=$deadline")
        return "continuous_posted"
    }

    fun stop(context: Context, token: String? = null) {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        if (token != null && token != prefs.getString(TOKEN, null)) return
        context.getSystemService(NotificationManager::class.java).cancel(ID)
        Log.i("AwikiContinuousProbe", "stopped elapsed=${SystemClock.elapsedRealtime()}")
    }
}

/** Only explicit PendingIntents from this Debug package can invoke it. */
class ContinuousUrgentProbeStopReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val token = intent.getStringExtra("last_token") ?: return
        ContinuousUrgentNotificationProbe.stop(context, token)
    }
}
