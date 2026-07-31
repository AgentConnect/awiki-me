package ai.awiki.awikime.push

internal object NotificationWakePolicy {
    fun shouldWake(
        isInteractive: Boolean,
        notificationsEnabled: Boolean,
        channelImportance: Int?,
    ): Boolean {
        return !isInteractive &&
            notificationsEnabled &&
            channelImportance != null &&
            channelImportance > 0
    }
}
