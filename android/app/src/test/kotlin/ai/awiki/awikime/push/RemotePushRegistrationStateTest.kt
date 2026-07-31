package ai.awiki.awikime.push

import org.junit.Assert.assertEquals
import org.junit.Test

class RemotePushRegistrationStateTest {
    @Test
    fun `completion permits the next explicit initialization attempt`() {
        val state = RemotePushRegistrationState()

        assertEquals(
            RemotePushRegistrationAction.START,
            state.beginInitialization(),
        )
        assertEquals(
            RemotePushRegistrationAction.JOIN_IN_FLIGHT,
            state.beginInitialization(),
        )

        state.completeFailure()

        assertEquals(
            RemotePushRegistrationAction.START,
            state.beginInitialization(),
        )
        state.completeSuccess()
        assertEquals(
            RemotePushRegistrationAction.START,
            state.beginInitialization(),
        )
    }
}
