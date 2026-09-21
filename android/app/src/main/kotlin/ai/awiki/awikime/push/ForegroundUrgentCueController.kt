package ai.awiki.awikime.push

import android.app.NotificationManager
import android.content.Context
import android.media.AudioManager
import android.media.Ringtone
import android.media.RingtoneManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.util.Log
import androidx.core.app.NotificationManagerCompat

/** Single foreground cue. No service, wake lock, alarm, call audio, or full-screen intent. */
internal class ForegroundUrgentCueController(
    context: Context,
    private val isForeground: () -> Boolean,
) {
    private val app = context.applicationContext
    private val handler = Handler(Looper.getMainLooper())
    private val window = UrgentCueWindow()
    private var ringtone: Ringtone? = null
    private var vibrator: Vibrator? = null
    private val timeout = Runnable { stop() }
    private val check = object : Runnable {
        override fun run() {
            val decision = UrgentCuePolicy.evaluate(readState())
            if (!decision.allowed || window.expired(SystemClock.elapsedRealtime())) {
                stop()
                return
            }
            if (!decision.sound) stopSound()
            if (!decision.vibration) stopVibration()
            handler.postDelayed(this, 250)
        }
    }

    fun readState(): UrgentCuePolicy.State {
        val manager = app.getSystemService(NotificationManager::class.java)
        val audio = app.getSystemService(AudioManager::class.java)
        val channel = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            manager.getNotificationChannel(UrgentNotificationChannel.ID)
        } else null
        return UrgentCuePolicy.State(
            foreground = isForeground(),
            notificationsEnabled = NotificationManagerCompat.from(app).areNotificationsEnabled(),
            channelImportance = channel?.importance,
            channelHasSound = channel?.sound != null,
            channelVibrates = channel?.shouldVibrate() == true,
            interruptionFilterAllowsAll = manager.currentInterruptionFilter == NotificationManager.INTERRUPTION_FILTER_ALL,
            ringerMode = audio.ringerMode,
            notificationVolume = audio.getStreamVolume(AudioManager.STREAM_NOTIFICATION),
        )
    }

    fun start(requestedDurationMillis: Long = 60_000): Boolean {
        check(Looper.myLooper() == Looper.getMainLooper())
        val decision = UrgentCuePolicy.evaluate(readState())
        if (!decision.allowed || !window.begin(SystemClock.elapsedRealtime(), requestedDurationMillis)) return false
        if (decision.sound) startSound()
        if (decision.vibration) startVibration()
        handler.postDelayed(timeout, (window.deadlineMillis!! - SystemClock.elapsedRealtime()).coerceAtLeast(0))
        handler.post(check)
        Log.i(TAG, "started sound_requested=${ringtone != null} vibration_requested=${vibrator != null}")
        // Success means the bounded presentation session began, not that a human heard it.
        return true
    }

    fun stop() {
        handler.removeCallbacks(check)
        handler.removeCallbacks(timeout)
        stopSound()
        stopVibration()
        if (window.deadlineMillis != null) Log.i(TAG, "stopped")
        window.clear()
    }

    private fun startSound() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val uri = app.getSystemService(NotificationManager::class.java)
            .getNotificationChannel(UrgentNotificationChannel.ID)?.sound ?: return
        val player = runCatching { RingtoneManager.getRingtone(app, uri) }.getOrNull() ?: return
        try {
            player.audioAttributes = UrgentNotificationChannel.audioAttributes
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) player.isLooping = true
            ringtone = player
            player.play()
        } catch (_: Exception) { stopSound() }
    }

    @Suppress("DEPRECATION")
    private fun startVibration() {
        val service = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            app.getSystemService(VibratorManager::class.java)?.defaultVibrator
        } else app.getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
        if (service?.hasVibrator() != true || Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val channel = app.getSystemService(NotificationManager::class.java)
            .getNotificationChannel(UrgentNotificationChannel.ID) ?: return
        val pattern = channel.vibrationPattern ?: longArrayOf(0, 700, 500, 700, 1100)
        try {
            vibrator = service
            service.vibrate(VibrationEffect.createWaveform(pattern, 0), UrgentNotificationChannel.audioAttributes)
        } catch (_: Exception) { stopVibration() }
    }

    private fun stopSound() { ringtone?.runCatching { stop() }; ringtone = null }
    private fun stopVibration() { vibrator?.runCatching { cancel() }; vibrator = null }

    companion object { private const val TAG = "AwikiUrgentCue" }
}
