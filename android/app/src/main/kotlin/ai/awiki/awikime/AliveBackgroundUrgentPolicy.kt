package ai.awiki.awikime

internal enum class AliveBackgroundUrgentDecision {
    FULL_SCREEN,
    FALLBACK,
    SUPPRESS_FOREGROUND,
    SUPPRESS_PERMISSION,
    SUPPRESS_CHANNEL,
    SUPPRESS_DETACHED,
}

internal object AliveBackgroundUrgentPolicy {
    const val MAX_CUE_DURATION_MILLIS = 30_000L
    const val BYPASS_DND = false

    fun decide(
        activityResumed: Boolean,
        flutterAndPushAttached: Boolean,
        notificationsAllowed: Boolean,
        channelState: String,
        fullScreenAccess: String,
    ): AliveBackgroundUrgentDecision {
        if (activityResumed) return AliveBackgroundUrgentDecision.SUPPRESS_FOREGROUND
        if (!flutterAndPushAttached) return AliveBackgroundUrgentDecision.SUPPRESS_DETACHED
        if (!notificationsAllowed) return AliveBackgroundUrgentDecision.SUPPRESS_PERMISSION
        if (channelState == "blocked" || channelState == "unavailable") {
            return AliveBackgroundUrgentDecision.SUPPRESS_CHANNEL
        }
        return if (channelState == "high" && fullScreenAccess == "allowed") {
            AliveBackgroundUrgentDecision.FULL_SCREEN
        } else {
            AliveBackgroundUrgentDecision.FALLBACK
        }
    }
}

internal object AliveBackgroundUrgentContract {
    fun notificationId(nativeId: Int): Int = nativeId

    fun contentRequestCode(nativeId: Int): Int = nativeId

    fun fullScreenRequestCode(nativeId: Int): Int = nativeId xor 0x40000000

    fun deleteRequestCode(nativeId: Int): Int = nativeId xor 0x20000000

    fun replacementNativeId(activeNativeId: Int?, incomingNativeId: Int): Int? =
        activeNativeId?.takeIf { it != incomingNativeId }

    fun isOpaqueMessageReference(value: String): Boolean =
        Regex("^message_[A-Za-z0-9_-]{24}$").matches(value)

}

internal enum class AliveBackgroundUrgentStopReason {
    ACTION,
    DISMISS,
    BACK,
    NOTIFICATION_REMOVED,
    TIMEOUT,
    RESUME,
    FENCE,
    REPLACED,
    PROCESS,
}

/** Idempotent stop boundary shared by every high-interruption exit path. */
internal class AliveBackgroundUrgentSession(
    private val cancel: (AliveBackgroundUrgentStopReason) -> Unit,
    private val emitOpaqueOpen: () -> Unit,
) {
    var stopReason: AliveBackgroundUrgentStopReason? = null
        private set

    fun stop(reason: AliveBackgroundUrgentStopReason, openTarget: Boolean = false) {
        if (stopReason != null) return
        stopReason = reason
        cancel(reason)
        if (openTarget) emitOpaqueOpen()
    }
}
