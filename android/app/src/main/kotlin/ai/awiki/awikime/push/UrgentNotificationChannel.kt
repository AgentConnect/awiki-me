package ai.awiki.awikime.push

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.media.AudioAttributes
import android.media.RingtoneManager
import android.os.Build

internal object UrgentNotificationChannel {
    const val ID = "awiki_me_notify_urgent_v1"
    val audioAttributes: AudioAttributes = AudioAttributes.Builder()
        .setUsage(AudioAttributes.USAGE_NOTIFICATION)
        .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
        .build()

    /** Called only on explicit setup. Existing user channel choices are never rewritten. */
    fun ensureCreated(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = context.getSystemService(NotificationManager::class.java)
        if (manager.getNotificationChannel(ID) != null) return
        manager.createNotificationChannel(
            NotificationChannel(ID, "Urgent task notifications", NotificationManager.IMPORTANCE_HIGH).apply {
                description = "Urgent AWiki task alerts allowed by the receiving account"
                setSound(RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION), audioAttributes)
                enableVibration(true)
                vibrationPattern = longArrayOf(0, 700, 500, 700)
                setBypassDnd(false)
            },
        )
    }
}
