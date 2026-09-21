package ai.awiki.awikime.push

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.os.Looper
import org.json.JSONObject
import org.junit.After
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import org.robolectric.annotation.LooperMode

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28])
@LooperMode(LooperMode.Mode.PAUSED)
class TextNotifyPresentationTest {
    private val c: Context get() = RuntimeEnvironment.getApplication()
    private val manager get() = c.getSystemService(NotificationManager::class.java)
    private val target = "target_abcdefghijklmnopqrstuvwx"
    private val other = "target_123456789012345678901234"
    private val peer = "identity_abcdefghijklmnopqrstuvwx"
    private val first = "message_abcdefghijklmnopqrstuvwx"
    private val second = "message_123456789012345678901234"
    private val prefs get() = c.getSharedPreferences("text_notify_local_v1_$target", Context.MODE_PRIVATE)

    private fun payload(mid: String = first, level: String = "urgent"): String =
        JSONObject().put("awiki_notify", 1).put("title", "Task").put("summary", mid)
            .put("extraMap", JSONObject().put("v", 1).put("ty", "direct_message")
                .put("mid", mid).put("ts", target).put("ir", peer)
                .put("exp", System.currentTimeMillis() / 1000 + 86400)
                .put("notify", JSONObject().put("v", 1).put("level", level)
                    .put("expires_at", System.currentTimeMillis() / 1000 + 120))).toString()

    private fun hydrate(mutes: List<String> = emptyList()) {
        val revision = TextNotifyPresentation.beginMuteSync(c, target)
        assertNotNull(revision)
        assertTrue(TextNotifyPresentation.replaceMutes(c, mapOf(
            "target" to target, "revision" to revision, "identities" to mutes)))
    }

    @Before fun prepare() {
        TextNotifyPresentation.activeToken = null
        TextNotifyPresentation.pendingToken = null
        TextNotifyPresentation.activePayload = null
        c.getSharedPreferences("text_notify_local_binding_v1", Context.MODE_PRIVATE).edit().clear().commit()
        prefs.edit().clear().commit()
        TextNotifyPresentation.setTarget(c, target)
        manager.createNotificationChannel(NotificationChannel("awiki_me_messages", "Messages", NotificationManager.IMPORTANCE_HIGH))
        hydrate()
        assertTrue(TextNotifyPresentation.configure(c, mapOf("target" to target, "enabled" to true, "urgent_enabled" to true)))
    }

    @After fun cleanup() {
        TextNotifyPresentation.activeToken = null
        TextNotifyPresentation.pendingToken = null
        TextNotifyPresentation.activePayload = null
        manager.cancelAll()
        shadowOf(Looper.getMainLooper()).idle()
    }

    @Test fun activeCueRetainsDistinctNormalAndUrgentWithoutReplacingOrExtendingIt() {
        val token = "$target:active"
        TextNotifyPresentation.activeToken = token
        TextNotifyPresentation.deadlineMillis = 60000
        manager.notify(TextNotifyPresentation.ID, Notification.Builder(c, "awiki_me_messages").setContentTitle("Active").build())
        assertTrue(TextNotifyPresentation.receive(c, payload(first, "normal")))
        assertTrue(TextNotifyPresentation.receive(c, payload(second, "urgent")))
        shadowOf(Looper.getMainLooper()).idle()
        val notices = manager.activeNotifications
        assertEquals(3, notices.size)
        assertEquals("Active", notices.single { it.tag == null }.notification.extras.getString(Notification.EXTRA_TITLE))
        val passive = notices.filter { it.tag != null }
        assertEquals(2, passive.map { it.tag }.toSet().size)
        assertNotEquals(passive[0].notification.contentIntent, passive[1].notification.contentIntent)
        passive.forEach {
            assertEquals(0, it.notification.defaults and (Notification.DEFAULT_SOUND or Notification.DEFAULT_VIBRATE))
            assertNull(it.notification.sound)
            assertNull(it.notification.vibrate)
        }
        assertEquals(token, TextNotifyPresentation.activeToken)
        assertEquals(60000L, TextNotifyPresentation.deadlineMillis)
        assertNull(shadowOf(RuntimeEnvironment.getApplication()).nextStartedService)
        // Persistent receipt survives the end of a cue: redelivery cannot ring later.
        TextNotifyPresentation.activeToken = null
        TextNotifyPresentation.receive(c, payload(second))
        shadowOf(Looper.getMainLooper()).idle()
        assertEquals(3, manager.activeNotifications.size)
        assertNull(shadowOf(RuntimeEnvironment.getApplication()).nextStartedService)
    }

    @Test fun pendingServiceAlsoRetainsSecondMessageSilently() {
        TextNotifyPresentation.pendingToken = "$target:pending"
        TextNotifyPresentation.receive(c, payload())
        shadowOf(Looper.getMainLooper()).idle()
        assertEquals(1, manager.activeNotifications.size)
        assertNull(shadowOf(RuntimeEnvironment.getApplication()).nextStartedService)
    }

    @Test fun historicalMuteIsFailClosedUntilCompleteSnapshotAndStillMutedAfterReload() {
        prefs.edit().remove("mutes_ready").remove("local_mutes").commit()
        assertFalse(TextNotifyPresentation.allows(c, payload(), false))
        hydrate(listOf(peer))
        assertFalse(TextNotifyPresentation.allows(c, payload(), false))
        assertTrue(prefs.getBoolean("mutes_ready", false))
        assertEquals(setOf(peer), prefs.getStringSet("local_mutes", emptySet()))
        hydrate()
        assertTrue(TextNotifyPresentation.allows(c, payload(), true))
    }

    @Test fun staleSnapshotCannotReenableAfterNewSnapshotOrAccountSwitch() {
        val stale = TextNotifyPresentation.beginMuteSync(c, target)
        hydrate(listOf(peer))
        assertFalse(TextNotifyPresentation.replaceMutes(c, mapOf(
            "target" to target, "revision" to stale, "identities" to emptyList<String>())))
        val old = TextNotifyPresentation.beginMuteSync(c, target)
        TextNotifyPresentation.setTarget(c, other)
        TextNotifyPresentation.setTarget(c, target)
        assertFalse(TextNotifyPresentation.replaceMutes(c, mapOf(
            "target" to target, "revision" to old, "identities" to emptyList<String>())))
        assertFalse(TextNotifyPresentation.allows(c, payload(), false))
    }

    @Test fun muteMasterOffAndAccountSwitchRemoveOnlyNotifyPassiveSlots() {
        manager.notify(123, Notification.Builder(c, "awiki_me_messages").setContentTitle("Chat").build())
        TextNotifyPresentation.showPassive(c, payload())
        hydrate(listOf(peer))
        assertEquals(listOf(123), manager.activeNotifications.map { it.id })
        hydrate()
        TextNotifyPresentation.showPassive(c, payload())
        TextNotifyPresentation.configure(c, mapOf("target" to target, "enabled" to false, "urgent_enabled" to false))
        assertEquals(listOf(123), manager.activeNotifications.map { it.id })
        TextNotifyPresentation.configure(c, mapOf("target" to target, "enabled" to true, "urgent_enabled" to true))
        TextNotifyPresentation.showPassive(c, payload())
        TextNotifyPresentation.setTarget(c, other)
        assertEquals(listOf(123), manager.activeNotifications.map { it.id })
        assertFalse(TextNotifyPresentation.allows(c, payload(), false))
    }
}
