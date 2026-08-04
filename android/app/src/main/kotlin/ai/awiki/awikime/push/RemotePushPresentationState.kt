package ai.awiki.awikime.push

import org.json.JSONObject

internal class RemotePushPresentationPolicy {
    var activityResumed: Boolean = false
    // Retained as bridge-owned session/window metadata. Neither value may gate
    // ordinary foreground suppression; Dart fences queued events by opaque target.
    var windowFocused: Boolean = false
    var activeTargetReference: String? = null

    fun shouldShowNotification(extraMap: Map<String, String>?): Boolean {
        if (!activityResumed) return true
        val envelope = resolveEnvelope(extraMap) ?: return true
        if (envelope["ty"] !in ordinaryMessageTypes) return true
        val targetReference = envelope["ts"] ?: return true
        return !targetReferencePattern.matches(targetReference)
    }

    private fun resolveEnvelope(pushData: Map<String, String>?): Map<String, String>? {
        val data = pushData ?: return null
        if (data.containsKey("ty") || data.containsKey("ts")) return data

        // EMAS calls showNotificationNow with its raw Push map. User-defined
        // extras are still encoded in `ext`; the later callbacks receive the
        // already-decoded map. Support both shapes so foreground suppression
        // is decided before the provider builds a system notification.
        val rawEnvelope = data["ext"]?.takeIf { it.length <= MAX_ENVELOPE_LENGTH }
            ?: return null
        return runCatching {
            val json = JSONObject(rawEnvelope)
            mapOf(
                "ty" to json.getString("ty"),
                "ts" to json.getString("ts"),
            )
        }.getOrNull()
    }

    companion object {
        private const val MAX_ENVELOPE_LENGTH = 4096
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
