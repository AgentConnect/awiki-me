package ai.awiki.awikime.push

import org.junit.Assert.*
import org.junit.Test

class UrgentCuePolicyTest {
    private val enabled = UrgentCuePolicy.State(true, true, 4, true, true, true, 2, 5)

    @Test fun `foreground cue follows independent channel sound and vibration choices`() {
        assertEquals(UrgentCuePolicy.Decision(true, true, true), UrgentCuePolicy.evaluate(enabled))
        assertEquals(UrgentCuePolicy.Decision(true, false, true),
            UrgentCuePolicy.evaluate(enabled.copy(channelHasSound = false)))
        assertEquals(UrgentCuePolicy.Decision(true, true, false),
            UrgentCuePolicy.evaluate(enabled.copy(channelVibrates = false)))
    }

    @Test fun `background permission denial disabled downgraded and missing channels forbid cue`() {
        for (state in listOf(enabled.copy(foreground = false),
            enabled.copy(notificationsEnabled = false), enabled.copy(channelImportance = 0),
            enabled.copy(channelImportance = 2), enabled.copy(channelImportance = 3),
            enabled.copy(channelImportance = null))) {
            assertEquals(UrgentCuePolicy.Decision(false, false, false), UrgentCuePolicy.evaluate(state))
        }
    }

    @Test fun `DND and silent never use the foreground player to bypass system policy`() {
        for (state in listOf(enabled.copy(interruptionFilterAllowsAll = false),
            enabled.copy(ringerMode = 0), enabled.copy(ringerMode = -1))) {
            assertEquals(UrgentCuePolicy.Decision(true, false, false), UrgentCuePolicy.evaluate(state))
        }
        assertEquals(UrgentCuePolicy.Decision(true, false, true),
            UrgentCuePolicy.evaluate(enabled.copy(ringerMode = 1)))
        assertEquals(UrgentCuePolicy.Decision(true, false, true),
            UrgentCuePolicy.evaluate(enabled.copy(notificationVolume = 0)))
    }

    @Test fun `repeated starts cannot move the thirty second deadline`() {
        val window = UrgentCueWindow()
        assertTrue(window.begin(10_000, 90_000))
        assertFalse(window.begin(35_000, 90_000))
        assertEquals(40_000L, window.deadlineMillis)
        assertFalse(window.expired(39_999))
        assertTrue(window.expired(40_000))
    }

    @Test fun `stop releases active window and invalid short durations are bounded`() {
        val window = UrgentCueWindow()
        assertTrue(window.begin(10_000, -1))
        assertEquals(11_000L, window.deadlineMillis)
        window.clear()
        assertFalse(window.expired(50_000))
        assertTrue(window.begin(50_000, 30_000))
        assertEquals(80_000L, window.deadlineMillis)
    }
}
