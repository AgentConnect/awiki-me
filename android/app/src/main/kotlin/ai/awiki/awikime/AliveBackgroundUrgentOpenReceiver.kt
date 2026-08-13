package ai.awiki.awikime

import ai.awiki.awikime.push.RemotePushEventBridge
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

class AliveBackgroundUrgentOpenReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val nativeId = intent.getIntExtra(EXTRA_NATIVE_ID, -1)
        val opaqueReference = intent.getStringExtra(EXTRA_OPAQUE_MESSAGE_REFERENCE)
        val expiresAt = intent.getLongExtra(EXTRA_EXPIRES_AT_EPOCH_SECONDS, -1L)
        open(context, nativeId, opaqueReference, expiresAt)
    }

    companion object {
        const val EXTRA_NATIVE_ID = "native_id"
        const val EXTRA_OPAQUE_MESSAGE_REFERENCE = "opaque_message_reference"
        const val EXTRA_EXPIRES_AT_EPOCH_SECONDS = "expires_at_epoch_seconds"

        fun open(
            context: Context,
            nativeId: Int,
            opaqueReference: String?,
            expiresAtEpochSeconds: Long,
        ) {
            if (
                nativeId < 0 ||
                opaqueReference == null ||
                !AliveBackgroundUrgentContract.isOpaqueMessageReference(opaqueReference) ||
                expiresAtEpochSeconds <= System.currentTimeMillis() / 1000L
            ) {
                return
            }
            AliveBackgroundUrgentNotificationController.cancel(
                context.applicationContext,
                nativeId,
                AliveBackgroundUrgentStopReason.ACTION,
            )
            RemotePushEventBridge.emit(
                context.applicationContext,
                "notification_opened",
                mapOf(
                    "extraMap" to mapOf(
                        "mid" to opaqueReference,
                        "exp" to expiresAtEpochSeconds,
                    ),
                ),
            )
            val launch = context.packageManager.getLaunchIntentForPackage(context.packageName)
                ?: Intent(context, MainActivity::class.java)
            launch.addFlags(
                Intent.FLAG_ACTIVITY_NEW_TASK or
                    Intent.FLAG_ACTIVITY_CLEAR_TOP or
                    Intent.FLAG_ACTIVITY_SINGLE_TOP,
            )
            context.startActivity(launch)
        }
    }
}
