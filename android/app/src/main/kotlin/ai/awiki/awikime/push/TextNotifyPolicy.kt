package ai.awiki.awikime.push

/** Pure acceptance gate used by the native presenter before durable consumption. */
internal object TextNotifyPolicy {
    fun canOpen(now: Long, expiresAt: Long, target: String, activeTarget: String?): Boolean =
        expiresAt > now && Regex("^target_[A-Za-z0-9_-]{24}$").matches(target) && target == activeTarget

    fun accepts(now: Long, expiresAt: Long, message: String, target: String,
                activeTarget: String?, level: String, enabled: Boolean,
                urgentEnabled: Boolean, preferenceVersion: Long, localVersion: Long): Boolean =
        expiresAt > now && expiresAt <= now + 120 &&
        Regex("^message_[A-Za-z0-9_-]{24}$").matches(message) &&
        Regex("^target_[A-Za-z0-9_-]{24}$").matches(target) && target == activeTarget &&
        level in setOf("normal", "urgent") && enabled && (level != "urgent" || urgentEnabled) &&
        preferenceVersion >= 0 && preferenceVersion == localVersion
}
