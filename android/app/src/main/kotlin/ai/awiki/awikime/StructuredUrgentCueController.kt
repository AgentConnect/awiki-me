package ai.awiki.awikime

import android.content.Context
import android.media.AudioAttributes
import android.media.Ringtone
import android.media.RingtoneManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.util.Log

/**
 * Owns the bounded, App-foreground urgent cue.
 *
 * The cue uses normal ringtone notification policy: it does not request DND
 * access, wake the screen, or use a full-screen Android intent.
 */
internal class StructuredUrgentCueController(
    context: Context,
) {
    private val applicationContext = context.applicationContext
    private val handler = Handler(Looper.getMainLooper())
    private var ringtone: Ringtone? = null
    private var vibrator: Vibrator? = null
    private val stopRunnable = Runnable { stop() }

    @Synchronized
    fun start(maxDurationMillis: Long): Boolean {
        stop()
        val boundedDuration = maxDurationMillis.coerceIn(
            MIN_DURATION_MILLIS,
            MAX_DURATION_MILLIS,
        )
        val soundStarted = startRingtone()
        val vibrationStarted = startVibration()
        Log.i(
            TAG,
            "started sound=$soundStarted vibration=$vibrationStarted duration_ms=$boundedDuration",
        )
        if (!soundStarted && !vibrationStarted) {
            return false
        }
        handler.postDelayed(stopRunnable, boundedDuration)
        return true
    }

    @Synchronized
    fun stop() {
        val hadActiveCue = ringtone != null || vibrator != null
        handler.removeCallbacks(stopRunnable)
        ringtone?.runCatching { stop() }
        ringtone = null
        vibrator?.runCatching { cancel() }
        vibrator = null
        if (hadActiveCue) {
            Log.i(TAG, "stopped")
        }
    }

    private fun startRingtone(): Boolean {
        val uri = RingtoneManager.getActualDefaultRingtoneUri(
            applicationContext,
            RingtoneManager.TYPE_RINGTONE,
        ) ?: RingtoneManager.getActualDefaultRingtoneUri(
            applicationContext,
            RingtoneManager.TYPE_NOTIFICATION,
        ) ?: return false
        val player = RingtoneManager.getRingtone(applicationContext, uri)
            ?: return false
        return runCatching {
            player.audioAttributes = CUE_AUDIO_ATTRIBUTES
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                player.isLooping = true
            }
            player.play()
            ringtone = player
            true
        }.getOrElse {
            player.runCatching { stop() }
            false
        }
    }

    @Suppress("DEPRECATION")
    private fun startVibration(): Boolean {
        val service = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            applicationContext
                .getSystemService(VibratorManager::class.java)
                ?.defaultVibrator
        } else {
            applicationContext.getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
        } ?: return false
        if (!service.hasVibrator()) {
            return false
        }
        return runCatching {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                service.vibrate(
                    VibrationEffect.createWaveform(VIBRATION_PATTERN_MILLIS, 0),
                    CUE_AUDIO_ATTRIBUTES,
                )
            } else {
                service.vibrate(VIBRATION_PATTERN_MILLIS, 0)
            }
            vibrator = service
            true
        }.getOrElse { false }
    }

    companion object {
        const val DEFAULT_DURATION_MILLIS = 30_000L
        private const val TAG = "AwikiUrgentCue"
        private const val MIN_DURATION_MILLIS = 1_000L
        private const val MAX_DURATION_MILLIS = 30_000L
        private val VIBRATION_PATTERN_MILLIS = longArrayOf(0L, 700L, 500L, 700L, 1_100L)
        private val CUE_AUDIO_ATTRIBUTES = AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_NOTIFICATION_RINGTONE)
            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
            .build()
    }
}
