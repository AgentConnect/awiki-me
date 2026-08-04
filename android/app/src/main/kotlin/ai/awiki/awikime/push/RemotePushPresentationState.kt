package ai.awiki.awikime.push

internal class RemotePushPresentationPolicy {
    var activityResumed: Boolean = false
    // Retained as bridge-owned session/window metadata. Neither value may gate
    // ordinary foreground suppression; Dart fences queued events by opaque target.
    var windowFocused: Boolean = false
    var activeTargetReference: String? = null

    fun shouldShowNotification(extraMap: Map<String, String>?): Boolean {
        if (!activityResumed) return true
        val envelope = extraMap ?: return true
        if (envelope["ty"] !in ordinaryMessageTypes) return true
        val targetReference = envelope["ts"] ?: return true
        return !targetReferencePattern.matches(targetReference)
    }

    companion object {
        private val ordinaryMessageTypes = setOf("direct_message", "group_message")
        private val targetReferencePattern = Regex("^target_[A-Za-z0-9_-]{24}$")
    }
}

object RemotePushPresentationState {
    private val policy = RemotePushPresentationPolicy()

    @Synchronized
    fun setActivityResumed(value: Boolean) {
        policy.activityResumed = value
    }

    @Synchronized
    fun setWindowFocused(value: Boolean) {
        policy.windowFocused = value
    }

    @Synchronized
    fun setActiveTargetReference(value: String?) {
        policy.activeTargetReference = value?.takeIf(activeTargetReferencePattern::matches)
    }

    @Synchronized
    fun shouldShowNotification(extraMap: Map<String, String>?): Boolean {
        return policy.shouldShowNotification(extraMap)
    }

    private val activeTargetReferencePattern = Regex("^target_[A-Za-z0-9_-]{24}$")
}
