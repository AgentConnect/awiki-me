package ai.awiki.awikime.push

/** Pure acceptance gate used by the native presenter before durable consumption. */
internal object TextNotifyPolicy {
    // Server creates a 120-second expiry. Permit a bounded device clock lag, never an expired message.
    const val MAX_CLOCK_SKEW_SECONDS = 30L

    fun canOpen(now: Long, expiresAt: Long, target: String, activeTarget: String?): Boolean =
        expiresAt > now && Regex("^target_[A-Za-z0-9_-]{24}$").matches(target) && target == activeTarget

    fun continuous(level: String, urgentEnabled: Boolean): Boolean = level == "urgent" && urgentEnabled

    fun accepts(now: Long, expiresAt: Long, message: String, target: String,
                activeTarget: String?, level: String, enabled: Boolean): Boolean =
        expiresAt > now && expiresAt <= now + 120 + MAX_CLOCK_SKEW_SECONDS &&
        Regex("^message_[A-Za-z0-9_-]{24}$").matches(message) &&
        Regex("^target_[A-Za-z0-9_-]{24}$").matches(target) && target == activeTarget &&
        level in setOf("normal", "urgent") && enabled
}
