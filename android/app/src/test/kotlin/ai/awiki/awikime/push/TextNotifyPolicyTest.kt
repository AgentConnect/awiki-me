package ai.awiki.awikime.push
import org.junit.Assert.*
import org.junit.Test

class TextNotifyPolicyTest {
    private val target = "target_abcdefghijklmnopqrstuvwx"
    private val message = "message_abcdefghijklmnopqrstuvwx"
    private fun accepts(now: Long = 1000, expiry: Long = 1120, mid: String = message,
        to: String = target, active: String? = target, level: String = "urgent", enabled: Boolean = true,
        urgent: Boolean = true, version: Long = 7, local: Long = 7) =
        TextNotifyPolicy.accepts(now,expiry,mid,to,active,level,enabled,urgent,version,local)
    @Test fun retainedMessageNavigationChecksIdentityAndExpiryIndependentlyOfConsent() {
        assertTrue(TextNotifyPolicy.canOpen(1000, 2000, target, target))
        assertFalse(TextNotifyPolicy.canOpen(1000, 1000, target, target))
        assertFalse(TextNotifyPolicy.canOpen(1000, 2000, target, null))
        assertFalse(TextNotifyPolicy.canOpen(1000, 2000, target, "target_zyxwvutsrqponmlkjihgfedcba"))
    }
    @Test fun ownedFreshOptedInMessageCanStart() { assertTrue(accepts()) }
    @Test fun oldAndFutureMessagesCannotStart() { assertFalse(accepts(expiry=1000)); assertFalse(accepts(expiry=1121)) }
    @Test fun logoutAccountChangeAndMalformedIdentityCannotStart() {
        assertFalse(accepts(active=null)); assertFalse(accepts(active="target_zyxwvutsrqponmlkjihgfedc")); assertFalse(accepts(mid="bad"))
    }
    @Test fun masterOffUrgentOffAndUnknownVersionFailClosed() {
        assertFalse(accepts(enabled=false)); assertFalse(accepts(urgent=false)); assertFalse(accepts(local=-1)); assertFalse(accepts(version=6)); assertFalse(accepts(version=8))
    }
    @Test fun normalIsAllowedWithoutUrgentConsentAndUnknownLevelsAreRejected() {
        assertTrue(accepts(level="normal", urgent=false)); assertFalse(accepts(level="call"))
    }
}
