package ai.awiki.awikime

import ai.awiki.awikime.push.RemotePushEventBridge
import ai.awiki.awikime.push.RemotePushPresentationState
import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.media.AudioAttributes
import android.media.RingtoneManager
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.UUID

internal object AliveBackgroundUrgentNotificationController {
    private const val METHOD_CHANNEL =
        "ai.awiki.awikime/alive_background_urgent_notification"
    internal const val URGENT_CHANNEL_ID = "awiki_me_urgent_v2"
    private const val MAX_AGENT_LABEL = 128
    private const val MAX_TASK_NAME = 160
    private const val MAX_SUMMARY = 240
    private const val MAX_OPAQUE_MESSAGE_REFERENCE = 32

    @Volatile
    private var methodChannel: MethodChannel? = null
    @Volatile
    private var activeNativeId: Int? = null
    @Volatile
    private var activeContent: CommittedContent? = null
    @Volatile
    private var activeSurfaceStop: ((AliveBackgroundUrgentStopReason) -> Unit)? = null
    private val timeoutHandler = Handler(Looper.getMainLooper())
    private var timeoutRunnable: Runnable? = null
    @Volatile
    private var urgentCue: StructuredUrgentCueController? = null

    internal data class CommittedContent(
        val nativeId: Int,
        val token: String,
        val agentLabel: String,
        val taskName: String,
        val summary: String,
        val opaqueMessageReference: String,
        val expiresAtEpochSeconds: Long,
    )

    fun attach(context: Context, messenger: BinaryMessenger) {
        val applicationContext = context.applicationContext
        createUrgentChannel(applicationContext)
        methodChannel?.setMethodCallHandler(null)
        methodChannel = MethodChannel(messenger, METHOD_CHANNEL).also { channel ->
            channel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "getState" -> result.success(state(applicationContext))
                    "submit" -> result.success(submit(applicationContext, call))
                    "cancel" -> {
                        val nativeId = (call.arguments as? Map<*, *>)
                            ?.get("native_id") as? Int
                        if (nativeId != null) {
                            cancel(
                                applicationContext,
                                nativeId,
                                AliveBackgroundUrgentStopReason.FENCE,
                            )
                        }
                        result.success(null)
                    }
                    "openFullScreenSettings" -> result.success(
                        openFullScreenSettings(applicationContext),
                    )
                    else -> result.notImplemented()
                }
            }
        }
    }

    fun detach(context: Context) {
        cancelActive(context.applicationContext, AliveBackgroundUrgentStopReason.PROCESS)
        methodChannel?.setMethodCallHandler(null)
        methodChannel = null
    }

    fun content(nativeId: Int, token: String): CommittedContent? =
        activeContent?.takeIf { it.nativeId == nativeId && it.token == token }

    fun registerSurface(
        nativeId: Int,
        stop: (AliveBackgroundUrgentStopReason) -> Unit,
    ): Boolean {
        if (activeNativeId != nativeId || activeContent?.nativeId != nativeId) return false
        activeSurfaceStop = stop
        return true
    }

    fun unregisterSurface(stop: (AliveBackgroundUrgentStopReason) -> Unit) {
        if (activeSurfaceStop === stop) activeSurfaceStop = null
    }

    fun cancelActive(
        context: Context,
        reason: AliveBackgroundUrgentStopReason = AliveBackgroundUrgentStopReason.RESUME,
    ) {
        activeNativeId?.let { cancel(context.applicationContext, it, reason) }
    }

    fun cancel(
        context: Context,
        nativeId: Int,
        reason: AliveBackgroundUrgentStopReason = AliveBackgroundUrgentStopReason.FENCE,
    ) {
        NotificationManagerCompat.from(context).cancel(nativeId)
        if (activeNativeId == nativeId) {
            stopUrgentCue()
            val committedContent = activeContent
            val surfaceStop = activeSurfaceStop
            activeNativeId = null
            activeContent = null
            activeSurfaceStop = null
            timeoutRunnable?.let(timeoutHandler::removeCallbacks)
            timeoutRunnable = null
            surfaceStop?.invoke(reason)
            if (
                committedContent != null &&
                reason != AliveBackgroundUrgentStopReason.ACTION
            ) {
                RemotePushEventBridge.emit(
                    context.applicationContext,
                    "notification_removed",
                    mapOf(
                        "extraMap" to mapOf(
                            "mid" to committedContent.opaqueMessageReference,
                            "exp" to committedContent.expiresAtEpochSeconds,
                        ),
                    ),
                )
            }
        }
    }

    private fun state(context: Context): Map<String, Any> {
        val notificationsAllowed = notificationsAllowed(context)
        val channelState = channelState(context)
        val fullScreenAccess = fullScreenAccess(context)
        return mapOf(
            "platform_supported" to true,
            "native_activity_resumed" to RemotePushPresentationState.isActivityResumed(),
            "flutter_channel_attached" to
                (methodChannel != null && RemotePushEventBridge.isAttached()),
            "notifications_allowed" to notificationsAllowed,
            "channel_state" to channelState,
            "full_screen_access" to fullScreenAccess,
        )
    }

    private fun submit(context: Context, call: MethodCall): String {
        val arguments = call.arguments as? Map<*, *> ?: return "unavailable"
        val nativeId = arguments["native_id"] as? Int ?: return "unavailable"
        val agentLabel = bounded(arguments["agent_label"], MAX_AGENT_LABEL)
            ?: return "unavailable"
        val taskName = bounded(arguments["task_name"], MAX_TASK_NAME)
            ?: return "unavailable"
        val summary = bounded(arguments["summary"], MAX_SUMMARY)
            ?: return "unavailable"
        val opaqueMessageReference = bounded(
            arguments["opaque_message_reference"],
            MAX_OPAQUE_MESSAGE_REFERENCE,
        ) ?: return "unavailable"
        if (!AliveBackgroundUrgentContract.isOpaqueMessageReference(opaqueMessageReference)) {
            return "unavailable"
        }
        val expiresAtEpochSeconds = (arguments["expires_at_epoch_seconds"] as? Number)
            ?.toLong()
            ?: return "unavailable"
        if (expiresAtEpochSeconds <= System.currentTimeMillis() / 1000L) return "unavailable"

        // This is the final native lifecycle fence. MESSAGE callbacks never
        // call submit directly; Dart reaches here only after Core commit and
        // recipient policy. A resumed Activity or detached Flutter/Push bridge
        // invalidates the background owner immediately.
        val decision = AliveBackgroundUrgentPolicy.decide(
            activityResumed = RemotePushPresentationState.isActivityResumed(),
            flutterAndPushAttached = methodChannel != null && RemotePushEventBridge.isAttached(),
            notificationsAllowed = notificationsAllowed(context),
            channelState = channelState(context),
            fullScreenAccess = fullScreenAccess(context),
        )
        when (decision) {
            AliveBackgroundUrgentDecision.SUPPRESS_FOREGROUND -> return "suppressedForeground"
            AliveBackgroundUrgentDecision.SUPPRESS_PERMISSION -> return "suppressedPermission"
            AliveBackgroundUrgentDecision.SUPPRESS_CHANNEL -> return "suppressedChannel"
            AliveBackgroundUrgentDecision.SUPPRESS_DETACHED -> return "suppressedDetached"
            AliveBackgroundUrgentDecision.FULL_SCREEN,
            AliveBackgroundUrgentDecision.FALLBACK,
            -> Unit
        }

        val fullScreenAllowed = decision == AliveBackgroundUrgentDecision.FULL_SCREEN
        val content = CommittedContent(
            nativeId = nativeId,
            token = UUID.randomUUID().toString(),
            agentLabel = agentLabel,
            taskName = taskName,
            summary = summary,
            opaqueMessageReference = opaqueMessageReference,
            expiresAtEpochSeconds = expiresAtEpochSeconds,
        )
        val contentIntent = openIntent(
            context,
            nativeId,
            opaqueMessageReference,
            expiresAtEpochSeconds,
        )
        val fullScreenIntent = fullScreenActivityIntent(
            context = context,
            nativeId = nativeId,
            token = content.token,
        )
        val deleteIntent = deleteIntent(context, nativeId)
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(context, URGENT_CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(context)
        }
        builder
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(taskName)
            .setContentText(summary)
            .setSubText(agentLabel)
            .setContentIntent(contentIntent)
            .setDeleteIntent(deleteIntent)
            .setAutoCancel(true)
            .setOnlyAlertOnce(true)
            .setCategory(Notification.CATEGORY_MESSAGE)
            .setVisibility(Notification.VISIBILITY_PRIVATE)
            .setPriority(Notification.PRIORITY_HIGH)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            builder.setTimeoutAfter(AliveBackgroundUrgentPolicy.MAX_CUE_DURATION_MILLIS)
        }
        if (fullScreenAllowed) {
            builder.setFullScreenIntent(fullScreenIntent, true)
        }
        AliveBackgroundUrgentContract.replacementNativeId(
            activeNativeId,
            nativeId,
        )?.let { previousNativeId ->
            // Close the complete old slot, including a visible Activity,
            // before the replacement becomes active.
            cancel(
                context.applicationContext,
                previousNativeId,
                AliveBackgroundUrgentStopReason.REPLACED,
            )
        }
        activeContent = content
        activeNativeId = nativeId
        NotificationManagerCompat.from(context).notify(
            AliveBackgroundUrgentContract.notificationId(nativeId),
            builder.build(),
        )
        startUrgentCue(context)
        AliveBackgroundSyncScheduler.cancel(context)
        timeoutRunnable?.let(timeoutHandler::removeCallbacks)
        timeoutRunnable = Runnable {
            cancel(
                context.applicationContext,
                nativeId,
                AliveBackgroundUrgentStopReason.TIMEOUT,
            )
        }.also {
            timeoutHandler.postDelayed(
                it,
                AliveBackgroundUrgentPolicy.MAX_CUE_DURATION_MILLIS,
            )
        }
        val submission = if (fullScreenAllowed) "fullScreenRequested" else "fallbackSubmitted"
        android.util.Log.i(
            "AWikiRemotePush",
            "alive_urgent submit decision=$decision submission=$submission",
        )
        return submission
    }

    private fun openIntent(
        context: Context,
        nativeId: Int,
        opaqueMessageReference: String,
        expiresAtEpochSeconds: Long,
    ): PendingIntent {
        val intent = Intent(context, AliveBackgroundUrgentOpenReceiver::class.java).apply {
            action = "${context.packageName}.ALIVE_URGENT_OPEN.$nativeId"
            putExtra(AliveBackgroundUrgentOpenReceiver.EXTRA_NATIVE_ID, nativeId)
            putExtra(
                AliveBackgroundUrgentOpenReceiver.EXTRA_OPAQUE_MESSAGE_REFERENCE,
                opaqueMessageReference,
            )
            putExtra(
                AliveBackgroundUrgentOpenReceiver.EXTRA_EXPIRES_AT_EPOCH_SECONDS,
                expiresAtEpochSeconds,
            )
        }
        return PendingIntent.getBroadcast(
            context,
            AliveBackgroundUrgentContract.contentRequestCode(nativeId),
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    private fun fullScreenActivityIntent(
        context: Context,
        nativeId: Int,
        token: String,
    ): PendingIntent {
        val intent = Intent(context, AliveBackgroundUrgentActivity::class.java).apply {
            action = "${context.packageName}.ALIVE_URGENT.$nativeId"
            putExtra(AliveBackgroundUrgentActivity.EXTRA_NATIVE_ID, nativeId)
            putExtra(AliveBackgroundUrgentActivity.EXTRA_CONTENT_TOKEN, token)
        }
        return PendingIntent.getActivity(
            context,
            AliveBackgroundUrgentContract.fullScreenRequestCode(nativeId),
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    private fun deleteIntent(context: Context, nativeId: Int): PendingIntent {
        val intent = Intent(context, AliveBackgroundUrgentDismissReceiver::class.java).apply {
            action = "${context.packageName}.ALIVE_URGENT_REMOVED.$nativeId"
            putExtra(AliveBackgroundUrgentDismissReceiver.EXTRA_NATIVE_ID, nativeId)
        }
        return PendingIntent.getBroadcast(
            context,
            AliveBackgroundUrgentContract.deleteRequestCode(nativeId),
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    private fun startUrgentCue(context: Context) {
        if (channelState(context) != "high" || !notificationsAllowed(context)) {
            return
        }
        val player = urgentCue ?: StructuredUrgentCueController(context.applicationContext).also {
            urgentCue = it
        }
        player.start(AliveBackgroundUrgentPolicy.MAX_CUE_DURATION_MILLIS)
    }

    private fun stopUrgentCue() {
        urgentCue?.stop()
    }

    private fun createUrgentChannel(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = context.getSystemService(NotificationManager::class.java)
        if (manager.getNotificationChannel(URGENT_CHANNEL_ID) != null) return
        val ringtone = RingtoneManager.getActualDefaultRingtoneUri(
            context,
            RingtoneManager.TYPE_RINGTONE,
        ) ?: Settings.System.DEFAULT_RINGTONE_URI
        val audio = AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_NOTIFICATION_RINGTONE)
            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
            .build()
        val channel = NotificationChannel(
            URGENT_CHANNEL_ID,
            context.getString(R.string.alive_urgent_channel_name),
            NotificationManager.IMPORTANCE_HIGH,
        ).apply {
            description = context.getString(R.string.alive_urgent_channel_description)
            enableVibration(true)
            vibrationPattern = CUE_VIBRATION_PATTERN_MILLIS
            setSound(ringtone, audio)
            setBypassDnd(AliveBackgroundUrgentPolicy.BYPASS_DND)
            lockscreenVisibility = Notification.VISIBILITY_PRIVATE
        }
        manager.createNotificationChannel(channel)
    }

    private fun notificationsAllowed(context: Context): Boolean {
        if (!NotificationManagerCompat.from(context).areNotificationsEnabled()) return false
        return Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
            ContextCompat.checkSelfPermission(
                context,
                Manifest.permission.POST_NOTIFICATIONS,
            ) == PackageManager.PERMISSION_GRANTED
    }

    private fun channelState(context: Context): String {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return "high"
        val channel = context.getSystemService(NotificationManager::class.java)
            .getNotificationChannel(URGENT_CHANNEL_ID) ?: return "unavailable"
        if (channel.importance == NotificationManager.IMPORTANCE_NONE) return "blocked"
        return if (channel.importance >= NotificationManager.IMPORTANCE_HIGH) {
            "high"
        } else {
            "userReduced"
        }
    }

    private fun fullScreenAccess(context: Context): String {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.UPSIDE_DOWN_CAKE) return "allowed"
        return runCatching {
            if (context.getSystemService(NotificationManager::class.java)
                    .canUseFullScreenIntent()
            ) {
                "allowed"
            } else {
                "denied"
            }
        }.getOrElse { "unavailable" }
    }

    private val CUE_VIBRATION_PATTERN_MILLIS = longArrayOf(0L, 700L, 500L, 700L, 1_100L)

    private fun openFullScreenSettings(context: Context): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.UPSIDE_DOWN_CAKE) return false
        return runCatching {
            context.startActivity(
                Intent(Settings.ACTION_MANAGE_APP_USE_FULL_SCREEN_INTENT).apply {
                    data = Uri.parse("package:${context.packageName}")
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                },
            )
            true
        }.getOrDefault(false)
    }

    private fun bounded(value: Any?, maxLength: Int): String? {
        val text = value as? String ?: return null
        if (text.isBlank() || text.trim() != text || text.length > maxLength) return null
        if (text.any { it.code < 0x20 || it.code == 0x7f }) return null
        return text
    }
}
