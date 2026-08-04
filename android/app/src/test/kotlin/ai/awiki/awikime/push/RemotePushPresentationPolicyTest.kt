package ai.awiki.awikime.push

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class RemotePushPresentationPolicyTest {
    private val policy = RemotePushPresentationPolicy().apply {
        activeTargetReference = TARGET
    }

    @Test
    fun `background notification remains provider presented`() {
        assertTrue(policy.shouldShowNotification(ordinaryEnvelope()))
    }

    @Test
    fun `resumed activity without window focus remains provider presented`() {
        policy.activityResumed = true

        assertTrue(policy.shouldShowNotification(ordinaryEnvelope()))
    }

    @Test
    fun `focused foreground intercepts matching direct and group messages`() {
        policy.activityResumed = true
        policy.windowFocused = true

        assertFalse(policy.shouldShowNotification(ordinaryEnvelope("direct_message")))
        assertFalse(policy.shouldShowNotification(ordinaryEnvelope("group_message")))
    }

    @Test
    fun `foreground fails open for missing mismatched or unsupported envelope`() {
        policy.activityResumed = true
        policy.windowFocused = true

        assertTrue(policy.shouldShowNotification(null))
        assertTrue(policy.shouldShowNotification(mapOf("ty" to "direct_message")))
        assertTrue(
            policy.shouldShowNotification(
                ordinaryEnvelope() + ("ts" to "target_BBBBBBBBBBBBBBBBBBBBBBBB"),
            ),
        )
        assertTrue(policy.shouldShowNotification(ordinaryEnvelope("group_system_event")))
    }

    private fun ordinaryEnvelope(type: String = "group_message") = mapOf(
        "ty" to type,
        "ts" to TARGET,
    )

    companion object {
        private const val TARGET = "target_AAAAAAAAAAAAAAAAAAAAAAAA"
    }
}
