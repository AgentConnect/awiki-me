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

class TextNotifyAlertService : Service() {
    private val handler = Handler(Looper.getMainLooper())
    private lateinit var cue: ForegroundUrgentCueController
    private var active = false
    private var token: String? = null
    private var payload: String? = null
    private var wakeLock: PowerManager.WakeLock? = null
    private val timeout = Runnable { finishCue("timeout") }

    override fun onCreate() {
        super.onCreate()
        cue = ForegroundUrgentCueController(this) { active && payload?.let { TextNotifyPresentation.allows(this, it, true) } == true }
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
        payload = intent?.getStringExtra("payload")
        if (payload == null || !TextNotifyPresentation.allows(this, payload!!, true)) { stopSelf(); return START_NOT_STICKY }
        val content = JSONObject(payload!!)
        if (token == null || Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            stopSelf()
            return START_NOT_STICKY
        }
        UrgentNotificationChannel.ensureCreated(this)
        val stop = PendingIntent.getService(this, TextNotifyPresentation.ID,
            Intent(this, javaClass).setAction("stop").putExtra("token", token).putExtra("payload", payload),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        val view = PendingIntent.getActivity(this, TextNotifyPresentation.ID,
            Intent(this, TextNotifyAlertActivity::class.java)
                .addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP)
                .putExtra("token", token).putExtra("payload", payload),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        val open = PendingIntent.getActivity(this, TextNotifyPresentation.ID + 1,
            Intent(this, TextNotifyAlertActivity::class.java).setAction("view")
                .putExtra("payload", payload).putExtra("token", token),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        val notification = NotificationCompat.Builder(this, UrgentNotificationChannel.ID)
            .setSmallIcon(applicationInfo.icon)
            .setContentTitle(content.optString("title").take(80))
            .setContentText(content.optString("summary").take(240))
            .setContentIntent(open).setFullScreenIntent(view, true).setDeleteIntent(stop)
            .addAction(0, "关闭提醒", stop).addAction(0, "查看消息", open)
            .setOnlyAlertOnce(true).setOngoing(true).setTimeoutAfter(60_000)
            .setSilent(true)
            .setForegroundServiceBehavior(NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE).build()
        try {
            TextNotifyPresentation.activeToken = token
            TextNotifyPresentation.activePayload = payload
            TextNotifyPresentation.deadlineMillis = SystemClock.elapsedRealtime() + 60_000
            if (Build.VERSION.SDK_INT >= 34) {
                startForeground(TextNotifyPresentation.ID, notification,
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_SHORT_SERVICE)
            } else startForeground(TextNotifyPresentation.ID, notification)
            active = true
            if (!cue.start(60_000)) {
                finishCue("policy_denied")
                return START_NOT_STICKY
            }
            // Bounded CPU lifetime only; no screen wake, system volume, or DND override.
            wakeLock = getSystemService(PowerManager::class.java)
                .newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "AWiki:TextNotify")
                .apply { acquire(65_000) }
            handler.postDelayed(timeout, 60_000)
            if (RemotePushPresentationState.isActivityResumed()) {
                startActivity(Intent(this, TextNotifyAlertActivity::class.java)
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK).putExtra("token", token).putExtra("payload", payload))
            }
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
        TextNotifyPresentation.activeToken = null
        TextNotifyPresentation.activePayload = null
        TextNotifyPresentation.deadlineMillis = 0
        handler.removeCallbacks(timeout)
        cue.stop()
        wakeLock?.let { if (it.isHeld) it.release() }
        wakeLock = null
        stopForeground(STOP_FOREGROUND_REMOVE)
        if (reason == "timeout" || reason == "system_timeout" || reason == "policy_denied" || reason == "failure") payload?.let { TextNotifyPresentation.showPassive(this, it) }
        stopSelf()
        Log.i("AwikiContinuousService", "stopped reason=$reason elapsed=${SystemClock.elapsedRealtime()}")
    }

    override fun onDestroy() {
        active = false
        TextNotifyPresentation.activeToken = null
        TextNotifyPresentation.activePayload = null
        TextNotifyPresentation.deadlineMillis = 0
        handler.removeCallbacks(timeout)
        cue.stop()
        wakeLock?.let { if (it.isHeld) it.release() }
        wakeLock = null
        super.onDestroy()
    }
}
