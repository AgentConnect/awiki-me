package ai.awiki.awikime.push

internal class RemotePushPresentationPolicy {
    var activityResumed: Boolean = false
    var windowFocused: Boolean = false
    var activeTargetReference: String? = null

    fun shouldShowNotification(extraMap: Map<String, String>?): Boolean {
        if (!activityResumed || !windowFocused) return true
        val expectedTarget = activeTargetReference ?: return true
        val envelope = extraMap ?: return true
        if (envelope["ts"] != expectedTarget) return true
        return envelope["ty"] !in ordinaryMessageTypes
    }

    companion object {
        private val ordinaryMessageTypes = setOf("direct_message", "group_message")
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
