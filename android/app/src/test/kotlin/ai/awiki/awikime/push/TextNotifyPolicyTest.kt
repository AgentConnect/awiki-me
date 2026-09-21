package ai.awiki.awikime.push
import org.junit.Assert.*
import org.junit.Test

class TextNotifyPolicyTest {
    private val target = "target_abcdefghijklmnopqrstuvwx"
    private val message = "message_abcdefghijklmnopqrstuvwx"
    private fun accepts(now: Long = 1000, expiry: Long = 1120, mid: String = message,
        to: String = target, active: String? = target, level: String = "urgent", enabled: Boolean = true) =
        TextNotifyPolicy.accepts(now,expiry,mid,to,active,level,enabled)
    @Test fun retainedMessageNavigationChecksIdentityAndExpiryIndependentlyOfConsent() {
        assertTrue(TextNotifyPolicy.canOpen(1000, 2000, target, target))
        assertFalse(TextNotifyPolicy.canOpen(1000, 1000, target, target))
        assertFalse(TextNotifyPolicy.canOpen(1000, 2000, target, null))
        assertFalse(TextNotifyPolicy.canOpen(1000, 2000, target, "target_zyxwvutsrqponmlkjihgfedcba"))
    }
    @Test fun ownedFreshOptedInMessageCanStart() { assertTrue(accepts()) }
    @Test fun oldAndFutureMessagesCannotStart() { assertFalse(accepts(expiry=1000)); assertFalse(accepts(expiry=1151)) }
    @Test fun freshMessageSurvivesFiveSecondClockLagAndOneSecondDelivery() {
        assertTrue(accepts(now=996, expiry=1120))
        assertTrue(accepts(expiry=1150))
        assertFalse(accepts(expiry=1151))
        assertFalse(accepts(expiry=999))
    }
    @Test fun logoutAccountChangeAndMalformedIdentityCannotStart() {
        assertFalse(accepts(active=null)); assertFalse(accepts(active="target_zyxwvutsrqponmlkjihgfedc")); assertFalse(accepts(mid="bad"))
    }
    @Test fun masterOffRejectsEveryNotifyLevel() {
        assertFalse(accepts(enabled=false)); assertFalse(accepts(level="normal", enabled=false))
    }
    @Test fun urgentOffFallsBackToNormalPresentationAndUnknownLevelsAreRejected() {
        assertTrue(accepts(level="urgent"))
        assertFalse(TextNotifyPolicy.continuous("urgent", false))
        assertTrue(TextNotifyPolicy.continuous("urgent", true))
        assertFalse(TextNotifyPolicy.continuous("normal", true))
        assertFalse(accepts(level="call"))
    }
}
