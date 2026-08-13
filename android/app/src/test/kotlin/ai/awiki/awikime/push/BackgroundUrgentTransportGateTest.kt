package ai.awiki.awikime.push

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class BackgroundUrgentTransportGateTest {
    @Test
    fun `EMAS MESSAGE stays blocked for a terminated process`() {
        val diagnostic = BackgroundUrgentTransportDiagnostics.fromMessageCallback()

        assertEquals(
            BackgroundUrgentTransportBlocker.messageDoesNotDeliverWhenProcessTerminated,
            diagnostic.verdict.blocker,
        )
        assertFalse(diagnostic.verdict.appOwnedRendererMayStart)
        assertFalse(diagnostic.isolatedProbeMarkerPresent)
    }

    @Test
    fun `EMAS NOTICE stays blocked because the provider owns presentation`() {
        val diagnostic = BackgroundUrgentTransportDiagnostics.fromNoticeCallback(
            mapOf(
                "ext" to """{"awiki_transport_probe":"v1","probe_id":"probe_12345678"}""",
            ),
        )

        assertEquals(
            BackgroundUrgentTransportBlocker.noticeIsProviderPresented,
            diagnostic.verdict.blocker,
        )
        assertFalse(diagnostic.verdict.appOwnedRendererMayStart)
        assertTrue(diagnostic.isolatedProbeMarkerPresent)
    }

    @Test
    fun `probe parser rejects message content and unknown fields`() {
        assertFalse(
            IsolatedTransportProbeMarker.isPresent(
                mapOf(
                    "awiki_transport_probe" to "v1",
                    "probe_id" to "probe_12345678",
                    "task_name" to "must-not-parse",
                ),
            ),
        )
        assertFalse(
            IsolatedTransportProbeMarker.isPresent(
                mapOf("ext" to "not-json"),
            ),
        )
    }
}
