package ai.awiki.awikime

import ai.awiki.awikime.push.RemotePushEventBridge
import android.app.Notification
import io.flutter.embedding.engine.FlutterEngineCache
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.work.CoroutineWorker
import androidx.work.ForegroundInfo
import androidx.work.WorkerParameters
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.delay

/**
 * Legal background execution window after an EMAS MESSAGE dirty hint.
 * The worker is not a presentation owner: it only keeps the process runnable
 * and asks the already-attached Flutter coordinator to drain persisted hints.
 */
class AliveBackgroundSyncWorker(
    appContext: Context,
    params: WorkerParameters,
) : CoroutineWorker(appContext, params) {
    override suspend fun getForegroundInfo(): ForegroundInfo {
        return foregroundInfo(applicationContext)
    }

    override suspend fun doWork(): Result {
        setForeground(foregroundInfo(applicationContext))
        wakeCachedFlutterEngine()
        Log.i("AWikiRemotePush", "alive_background_sync worker_start")
        val deadline = System.currentTimeMillis() + SYNC_WINDOW_MS
        var lastPending = -1
        while (System.currentTimeMillis() < deadline) {
            if (isStopped) {
                break
            }
            val pending = RemotePushEventBridge.replayPending(applicationContext)
            if (pending != lastPending) {
                Log.i("AWikiRemotePush", "alive_background_sync replay pending=$pending")
                lastPending = pending
            }
            if (pending == 0 && lastPending == 0) {
                break
            }
            delay(REPLAY_INTERVAL_MS)
        }
        Log.i("AWikiRemotePush", "alive_background_sync worker_stop")
        return Result.success()
    }

    companion object {
        private const val CHANNEL_ID = "awiki_me_sync_keepalive_v3"
        private const val NOTIFICATION_ID = 274472
        private const val SYNC_WINDOW_MS = 20_000L
        private const val REPLAY_INTERVAL_MS = 1_500L

        private suspend fun wakeCachedFlutterEngine() {
            val engine = FlutterEngineCache.getInstance().get(MainActivity.CACHED_ENGINE_ID)
            if (engine == null) {
                Log.i("AWikiRemotePush", "alive_background_sync engine=missing")
                return
            }
            if (Looper.myLooper() == Looper.getMainLooper()) {
                applyInactive(engine)
                return
            }
            val done = CompletableDeferred<Unit>()
            Handler(Looper.getMainLooper()).post {
                try {
                    applyInactive(engine)
                } finally {
                    done.complete(Unit)
                }
            }
            done.await()
        }

        private fun applyInactive(engine: io.flutter.embedding.engine.FlutterEngine) {
            try {
                // LifecycleChannel is @UiThread. Keep the isolate runnable
                // without claiming Activity resume.
                engine.lifecycleChannel.appIsInactive()
                Log.i("AWikiRemotePush", "alive_background_sync engine=inactive")
            } catch (error: Throwable) {
                Log.w("AWikiRemotePush", "alive_background_sync engine wake failed", error)
            }
        }

        fun foregroundInfo(context: Context): ForegroundInfo {
            val notification = syncNotification(context)
            return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                ForegroundInfo(
                    NOTIFICATION_ID,
                    notification,
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC,
                )
            } else {
                ForegroundInfo(NOTIFICATION_ID, notification)
            }
        }

        private fun syncNotification(context: Context): Notification {
            val manager = context.getSystemService(NotificationManager::class.java)
            if (manager?.getNotificationChannel(CHANNEL_ID) == null) {
                manager?.createNotificationChannel(
                    NotificationChannel(
                        CHANNEL_ID,
                        context.getString(R.string.alive_sync_keepalive_channel_name),
                        NotificationManager.IMPORTANCE_MIN,
                    ).apply {
                        description = context.getString(
                            R.string.alive_sync_keepalive_channel_description,
                        )
                        setSound(null, null)
                        enableVibration(false)
                        setShowBadge(false)
                    },
                )
            }
            return NotificationCompat.Builder(context, CHANNEL_ID)
                .setSmallIcon(R.mipmap.ic_launcher)
                .setContentTitle(context.getString(R.string.app_name))
                .setContentText(context.getString(R.string.alive_sync_keepalive_text))
                .setSilent(true)
                .setOngoing(true)
                .setPriority(NotificationCompat.PRIORITY_MIN)
                .setCategory(NotificationCompat.CATEGORY_SERVICE)
                .setForegroundServiceBehavior(NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE)
                .build()
        }
    }
}
