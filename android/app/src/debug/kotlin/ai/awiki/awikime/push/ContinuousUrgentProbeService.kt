package ai.awiki.awikime.push

import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import android.os.SystemClock
import android.util.Log
import androidx.core.app.NotificationCompat
import org.json.JSONObject

/** Debug-only C0: explicitly armed on this phone, no authority over IM messages. */
internal object ContinuousUrgentServiceProbe {
    const val ID = 924041
    var activeToken: String? = null
    var deadlineMillis: Long = 0
    private const val PREFS = "continuous_service_probe"
    private const val TOKEN = "token"
    private const val CONSUMED = "consumed"
    private const val ARMED_AT = "armed_at"

    fun arm(context: Context, token: String): Boolean {
        if (token.length !in 16..80) return false
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        if (prefs.getString(TOKEN, null) == token) return true
        return prefs.edit()
            .putString(TOKEN, token).putBoolean(CONSUMED, false)
            .putLong(ARMED_AT, SystemClock.elapsedRealtime()).commit()
    }

    fun receive(context: Context, body: String?): Boolean {
        val payload = runCatching { JSONObject(body ?: "") }.getOrNull() ?: return false
        if (payload.optString("awiki_diagnostic") != "continuous-c0") return false
        val token = payload.optString("token")
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val age = SystemClock.elapsedRealtime() - prefs.getLong(ARMED_AT, -1_000_000)
        if (token != prefs.getString(TOKEN, null) || age !in 0..300_000 || prefs.getBoolean(CONSUMED, true)) {
            Log.i("AwikiContinuousService", "rejected_unarmed_or_duplicate")
            return true
        }
        // Consume before starting. An OS denial is not a reason to auto-retry or re-arm.
        if (!prefs.edit().putBoolean(CONSUMED, true).commit()) return true
        try {
            context.startForegroundService(Intent(context, ContinuousUrgentProbeService::class.java)
                .putExtra(TOKEN, token))
            Log.i("AwikiContinuousService", "background_start_requested")
        } catch (error: RuntimeException) {
            Log.i("AwikiContinuousService", "background_start_rejected type=${error.javaClass.simpleName}")
        }
        return true
    }
}

class ContinuousUrgentProbeService : Service() {
    private val handler = Handler(Looper.getMainLooper())
    private lateinit var cue: ForegroundUrgentCueController
    private var active = false
    private var token: String? = null
    private var wakeLock: PowerManager.WakeLock? = null
    private val timeout = Runnable { finishCue("timeout") }

    override fun onCreate() {
        super.onCreate()
        cue = ForegroundUrgentCueController(this) { active }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == "stop") {
            if (!active) stopSelf()
            else if (intent.getStringExtra("token") == token) finishCue("user")
            return START_NOT_STICKY
        }
        if (active) return START_NOT_STICKY
        token = intent?.getStringExtra("token")
        if (token == null || Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            stopSelf()
            return START_NOT_STICKY
        }
        UrgentNotificationChannel.ensureCreated(this)
        val stop = PendingIntent.getService(this, ContinuousUrgentServiceProbe.ID,
            Intent(this, javaClass).setAction("stop").putExtra("token", token),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        val view = PendingIntent.getActivity(this, ContinuousUrgentServiceProbe.ID,
            Intent(this, ContinuousUrgentProbeActivity::class.java)
                .addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP)
                .putExtra("token", token),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        val notification = NotificationCompat.Builder(this, UrgentNotificationChannel.ID)
            .setSmallIcon(applicationInfo.icon)
            .setContentTitle("AWiki 持续声振测试 · 最长60秒")
            .setContentText("循环响铃与振动；查看或关闭立即停止。")
            .setContentIntent(view).setFullScreenIntent(view, true).setDeleteIntent(stop)
            .addAction(0, "关闭提醒", stop)
            .setOnlyAlertOnce(true).setOngoing(true).setTimeoutAfter(60_000)
            .setSilent(true)
            .setForegroundServiceBehavior(NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE).build()
        try {
            ContinuousUrgentServiceProbe.activeToken = token
            ContinuousUrgentServiceProbe.deadlineMillis = SystemClock.elapsedRealtime() + 60_000
            if (Build.VERSION.SDK_INT >= 34) {
                startForeground(ContinuousUrgentServiceProbe.ID, notification,
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_SHORT_SERVICE)
            } else startForeground(ContinuousUrgentServiceProbe.ID, notification)
            active = true
            if (!cue.start(60_000)) {
                finishCue("policy_denied")
                return START_NOT_STICKY
            }
            // Bounded CPU lifetime only; no screen wake, system volume, or DND override.
            wakeLock = getSystemService(PowerManager::class.java)
                .newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "AWiki:ContinuousDebugProbe")
                .apply { acquire(65_000) }
            handler.postDelayed(timeout, 60_000)
            Log.i("AwikiContinuousService", "started elapsed=${SystemClock.elapsedRealtime()}")
        } catch (error: RuntimeException) {
            Log.i("AwikiContinuousService", "start_failed type=${error.javaClass.simpleName}")
            finishCue("failure")
        }
        return START_NOT_STICKY
    }

    override fun onTimeout(startId: Int) { finishCue("system_timeout") }
    override fun onTimeout(startId: Int, fgsType: Int) { finishCue("system_timeout") }

    private fun finishCue(reason: String) {
        active = false
        ContinuousUrgentServiceProbe.activeToken = null
        ContinuousUrgentServiceProbe.deadlineMillis = 0
        handler.removeCallbacks(timeout)
        cue.stop()
        wakeLock?.let { if (it.isHeld) it.release() }
        wakeLock = null
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
        Log.i("AwikiContinuousService", "stopped reason=$reason elapsed=${SystemClock.elapsedRealtime()}")
    }

    override fun onDestroy() {
        active = false
        ContinuousUrgentServiceProbe.activeToken = null
        ContinuousUrgentServiceProbe.deadlineMillis = 0
        handler.removeCallbacks(timeout)
        cue.stop()
        wakeLock?.let { if (it.isHeld) it.release() }
        wakeLock = null
        super.onDestroy()
    }
}
