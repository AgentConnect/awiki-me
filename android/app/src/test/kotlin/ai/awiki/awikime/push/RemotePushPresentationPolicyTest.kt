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
    fun `resumed activity intercepts ordinary messages without window focus`() {
        policy.activityResumed = true

        assertFalse(policy.shouldShowNotification(ordinaryEnvelope()))
    }

    @Test
    fun `resumed activity intercepts ordinary message from raw EMAS ext`() {
        policy.activityResumed = true

        assertFalse(policy.shouldShowNotification(rawEmasPush("direct_message")))
        assertFalse(policy.shouldShowNotification(rawEmasPush("group_message")))
    }

    @Test
    fun `focused foreground intercepts matching direct and group messages`() {
        policy.activityResumed = true
        policy.windowFocused = true

        assertFalse(policy.shouldShowNotification(ordinaryEnvelope("direct_message")))
        assertFalse(policy.shouldShowNotification(ordinaryEnvelope("group_message")))
    }

    @Test
    fun `focused foreground intercepts ordinary messages for another local account`() {
        policy.activityResumed = true
        policy.windowFocused = true

        assertFalse(
            policy.shouldShowNotification(
                ordinaryEnvelope() + ("ts" to "target_BBBBBBBBBBBBBBBBBBBBBBBB"),
            ),
        )
    }

    @Test
    fun `foreground intercepts ordinary messages before target fence is installed`() {
        policy.activityResumed = true
        policy.windowFocused = true
        policy.activeTargetReference = null

        assertFalse(policy.shouldShowNotification(ordinaryEnvelope()))
    }

    @Test
    fun `foreground fails open for missing malformed or unsupported envelope`() {
        policy.activityResumed = true
        policy.windowFocused = true

        assertTrue(policy.shouldShowNotification(null))
        assertTrue(policy.shouldShowNotification(mapOf("ty" to "direct_message")))
        assertTrue(
            policy.shouldShowNotification(
                ordinaryEnvelope() + ("ts" to "target_invalid"),
            ),
        )
        assertTrue(policy.shouldShowNotification(ordinaryEnvelope("group_system_event")))
        assertTrue(policy.shouldShowNotification(mapOf("ext" to "not-json")))
        assertTrue(
            policy.shouldShowNotification(
                mapOf("ext" to "{\"ty\":\"direct_message\",\"ts\":\"target_invalid\"}"),
            ),
        )
        assertTrue(policy.shouldShowNotification(rawEmasPush("group_system_event")))
    }

    private fun ordinaryEnvelope(type: String = "group_message") = mapOf(
        "ty" to type,
        "ts" to TARGET,
    )

    private fun rawEmasPush(type: String) = mapOf(
        "type" to "1",
        "title" to "Sender",
        "content" to "Preview",
        "ext" to "{\"v\":\"1\",\"ty\":\"$type\",\"ts\":\"$TARGET\"}",
    )

    companion object {
        private const val TARGET = "target_AAAAAAAAAAAAAAAAAAAAAAAA"
    }
}
