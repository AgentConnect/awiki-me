package ai.awiki.awikime.push

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class NotificationWakePolicyTest {
    @Test
    fun `wakes only for a visible notification on a non-interactive device`() {
        assertTrue(
            NotificationWakePolicy.shouldWake(
                isInteractive = false,
                notificationsEnabled = true,
                channelImportance = 5,
            ),
        )
        assertFalse(
            NotificationWakePolicy.shouldWake(
                isInteractive = true,
                notificationsEnabled = true,
                channelImportance = 5,
            ),
        )
        assertFalse(
            NotificationWakePolicy.shouldWake(
                isInteractive = false,
                notificationsEnabled = false,
                channelImportance = 5,
            ),
        )
        assertFalse(
            NotificationWakePolicy.shouldWake(
                isInteractive = false,
                notificationsEnabled = true,
                channelImportance = 0,
            ),
        )
        assertFalse(
            NotificationWakePolicy.shouldWake(
                isInteractive = false,
                notificationsEnabled = true,
                channelImportance = null,
            ),
        )
    }
}
