package ai.awiki.awikime

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class AliveBackgroundUrgentPolicyTest {
    @Test
    fun `exact alive background with high channel and FSI access requests full screen`() {
        assertEquals(
            AliveBackgroundUrgentDecision.FULL_SCREEN,
            decide(),
        )
    }

    @Test
    fun `Android 14 FSI denial and user reduced channel use fallback`() {
        assertEquals(
            AliveBackgroundUrgentDecision.FALLBACK,
            decide(fullScreenAccess = "denied"),
        )
        assertEquals(
            AliveBackgroundUrgentDecision.FALLBACK,
            decide(channelState = "userReduced"),
        )
    }

    @Test
    fun `foreground detached permission and channel fences suppress independently`() {
        assertEquals(
            AliveBackgroundUrgentDecision.SUPPRESS_FOREGROUND,
            decide(activityResumed = true),
        )
        assertEquals(
            AliveBackgroundUrgentDecision.SUPPRESS_DETACHED,
            decide(flutterAndPushAttached = false),
        )
        assertEquals(
            AliveBackgroundUrgentDecision.SUPPRESS_PERMISSION,
            decide(notificationsAllowed = false),
        )
        for (state in listOf("blocked", "unavailable")) {
            assertEquals(
                AliveBackgroundUrgentDecision.SUPPRESS_CHANNEL,
                decide(channelState = state),
            )
        }
    }

    @Test
    fun `contract keeps one stable notification ID and never bypasses DND`() {
        val nativeId = 7301
        assertEquals(nativeId, AliveBackgroundUrgentContract.notificationId(nativeId))
        assertEquals(nativeId, AliveBackgroundUrgentContract.contentRequestCode(nativeId))
        assertTrue(
            AliveBackgroundUrgentContract.fullScreenRequestCode(nativeId) !=
                AliveBackgroundUrgentContract.contentRequestCode(nativeId),
        )
        assertTrue(
            AliveBackgroundUrgentContract.deleteRequestCode(nativeId) !=
                AliveBackgroundUrgentContract.contentRequestCode(nativeId),
        )
        assertFalse(AliveBackgroundUrgentPolicy.BYPASS_DND)
        assertEquals(30_000L, AliveBackgroundUrgentPolicy.MAX_CUE_DURATION_MILLIS)
        assertEquals("awiki_me_urgent_v2", AliveBackgroundUrgentNotificationController.URGENT_CHANNEL_ID)
    }

    @Test
    fun `only opaque message references are accepted`() {
        assertTrue(
            AliveBackgroundUrgentContract.isOpaqueMessageReference(
                "message_AAAAAAAAAAAAAAAAAAAAAAAA",
            ),
        )
        assertFalse(AliveBackgroundUrgentContract.isOpaqueMessageReference("conversation-1"))
        assertFalse(AliveBackgroundUrgentContract.isOpaqueMessageReference("did:wba:owner"))
    }

    @Test
    fun `two different urgent submissions stop the old surface before replacement`() {
        val firstNativeId = 7301
        val secondNativeId = 7302
        assertEquals(
            firstNativeId,
            AliveBackgroundUrgentContract.replacementNativeId(
                firstNativeId,
                secondNativeId,
            ),
        )
        assertEquals(
            null,
            AliveBackgroundUrgentContract.replacementNativeId(
                firstNativeId,
                firstNativeId,
            ),
        )

        val order = mutableListOf<String>()
        val firstSurface = AliveBackgroundUrgentSession(
            cancel = { reason -> order += "first:${reason.name}" },
            emitOpaqueOpen = { order += "unexpected-open" },
        )
        val replacement = AliveBackgroundUrgentContract.replacementNativeId(
            firstNativeId,
            secondNativeId,
        )
        if (replacement != null) {
            firstSurface.stop(AliveBackgroundUrgentStopReason.REPLACED)
        }
        order += "second:registered"

        assertEquals(listOf("first:REPLACED", "second:registered"), order)
        assertEquals(AliveBackgroundUrgentStopReason.REPLACED, firstSurface.stopReason)
    }

    @Test
    fun `all dismiss timeout resume fence and process stops are idempotent`() {
        for (reason in AliveBackgroundUrgentStopReason.entries.filter {
            it != AliveBackgroundUrgentStopReason.ACTION
        }) {
            var cancels = 0
            var opens = 0
            val session = AliveBackgroundUrgentSession(
                cancel = { captured ->
                    assertEquals(reason, captured)
                    cancels += 1
                },
                emitOpaqueOpen = { opens += 1 },
            )
            session.stop(reason)
            session.stop(AliveBackgroundUrgentStopReason.PROCESS)
            assertEquals(reason, session.stopReason)
            assertEquals(1, cancels)
            assertEquals(0, opens)
        }
    }

    @Test
    fun `act now cancels first and opens canonical target exactly once`() {
        val order = mutableListOf<String>()
        val session = AliveBackgroundUrgentSession(
            cancel = { reason -> order += "cancel:${reason.name}" },
            emitOpaqueOpen = { order += "open" },
        )
        session.stop(AliveBackgroundUrgentStopReason.ACTION, openTarget = true)
        session.stop(AliveBackgroundUrgentStopReason.TIMEOUT)
        assertEquals(listOf("cancel:ACTION", "open"), order)
    }

    private fun decide(
        activityResumed: Boolean = false,
        flutterAndPushAttached: Boolean = true,
        notificationsAllowed: Boolean = true,
        channelState: String = "high",
        fullScreenAccess: String = "allowed",
    ) = AliveBackgroundUrgentPolicy.decide(
        activityResumed = activityResumed,
        flutterAndPushAttached = flutterAndPushAttached,
        notificationsAllowed = notificationsAllowed,
        channelState = channelState,
        fullScreenAccess = fullScreenAccess,
    )
}
