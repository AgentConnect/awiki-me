package ai.awiki.awikime.push

/** Platform limits only. The caller must first authorize the committed Notify message. */
internal object UrgentCuePolicy {
    data class State(
        val foreground: Boolean,
        val notificationsEnabled: Boolean,
        val channelImportance: Int?,
        val channelHasSound: Boolean,
        val channelVibrates: Boolean,
        val interruptionFilterAllowsAll: Boolean,
        val ringerMode: Int,
        val notificationVolume: Int,
    )

    data class Decision(val allowed: Boolean, val sound: Boolean, val vibration: Boolean)

    fun evaluate(state: State): Decision {
        val allowed = state.foreground && state.notificationsEnabled &&
            (state.channelImportance ?: 0) >= 4
        // Conservative under DND, including priority mode. Never request bypass access.
        val audible = allowed && state.interruptionFilterAllowsAll
        return Decision(
            allowed = allowed,
            sound = audible && state.ringerMode == 2 && state.notificationVolume > 0 &&
                state.channelHasSound,
            vibration = audible && state.ringerMode in 1..2 && state.channelVibrates,
        )
    }
}

/** Monotonic deadline. A second start cannot extend or overlap an active cue. */
internal class UrgentCueWindow {
    var deadlineMillis: Long? = null
        private set

    fun begin(nowMillis: Long, requestedDurationMillis: Long): Boolean {
        if (deadlineMillis != null) return false
        deadlineMillis = nowMillis + requestedDurationMillis.coerceIn(1_000L, 30_000L)
        return true
    }

    fun expired(nowMillis: Long): Boolean = deadlineMillis?.let { nowMillis >= it } ?: false

    fun clear() { deadlineMillis = null }
}
