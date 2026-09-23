package ai.awiki.awikime.push

import android.app.KeyguardManager
import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.os.Looper
import android.os.SystemClock
import android.view.View
import android.view.ViewGroup
import android.widget.Button
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Before
import org.junit.After
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import org.robolectric.annotation.LooperMode
import java.time.Duration

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28])
@LooperMode(LooperMode.Mode.PAUSED)
class TextNotifyAlertActivityTest {
    private val app: Context get() = RuntimeEnvironment.getApplication()
    private val keyguard get() = shadowOf(app.getSystemService(KeyguardManager::class.java))
    private val target = "target_abcdefghijklmnopqrstuvwx"
    private val mid = "message_abcdefghijklmnopqrstuvwx"
    private val token = "$target:$mid"
    private val events get() = app.getSharedPreferences("awiki_remote_push_events", Context.MODE_PRIVATE)
    private fun payload() = JSONObject().put("title", "Task").put("summary", "Result")
        .put("extraMap", JSONObject().put("v", 1).put("ty", "direct_message")
            .put("ts", target).put("ir", "identity_abcdefghijklmnopqrstuvwx").put("mid", mid)
            .put("exp", System.currentTimeMillis() / 1000 + 86400)).toString()
    private fun intent(action: String? = null) = Intent(app, TextNotifyAlertActivity::class.java)
        .setAction(action).putExtra("token", token).putExtra("payload", payload())
    private fun button(view: View, text: String): Button? {
        if (view is Button && view.text.toString() == text) return view
        if (view is ViewGroup) for (i in 0 until view.childCount) {
            button(view.getChildAt(i), text)?.let { return it }
        }
        return null
    }
    private fun click(activity: TextNotifyAlertActivity, label: String = "查看消息") {
        checkNotNull(button(activity.window.decorView, label)).performClick()
    }
    private fun queued() = JSONArray(events.getString("pending_events", "[]"))
    private fun assertRoutedOnce(activity: TextNotifyAlertActivity) {
        assertTrue(activity.isFinishing)
        val queue = queued()
        assertEquals(1, queue.length())
        val event = queue.getJSONObject(0)
        assertEquals("notification_opened", event.getString("kind"))
        val extra = JSONObject(event.getJSONObject("payload").getString("extraMap"))
        assertEquals(mid, extra.getString("mid"))
        assertEquals(target, extra.getString("ts"))
        val launch = shadowOf(activity).nextStartedActivity
        assertNotNull(launch)
        assertEquals("ai.awiki.awikime.MainActivity", launch.component!!.className)
        assertNull(shadowOf(activity).nextStartedActivity)
    }

    @Before fun setup() {
        keyguard.setKeyguardLocked(true)
        keyguard.setIsKeyguardSecure(true)
        events.edit().clear().commit()
        TextNotifyPresentation.setTarget(app, target)
        TextNotifyPresentation.activeToken = token
        TextNotifyPresentation.deadlineMillis = SystemClock.elapsedRealtime() + 60000
    }
    @After fun cleanup() {
        TextNotifyPresentation.activeToken = null
        TextNotifyPresentation.pendingToken = null
        keyguard.setKeyguardLocked(true)
    }

    @Test fun lockedViewStopsCueButDoesNotRouteUntilUnlockAndSurvivesCueEnding() {
        val controller = Robolectric.buildActivity(TextNotifyAlertActivity::class.java, intent()).setup()
        val activity = controller.get()
        click(activity)
        val stop = shadowOf(activity).nextStartedService
        assertEquals("stop", stop.action)
        assertEquals(token, stop.getStringExtra("token"))
        assertEquals(0, queued().length())
        assertNull(shadowOf(activity).nextStartedActivity)
        TextNotifyPresentation.activeToken = null // service stops before the user authenticates
        shadowOf(Looper.getMainLooper()).idleFor(Duration.ofSeconds(61))
        assertFalse(activity.isFinishing)
        click(activity) // a double tap must not create a second unlock/navigation request
        keyguard.setKeyguardLocked(false)
        assertRoutedOnce(activity)
        controller.pause().stop().destroy()
    }

    @Test fun cancelledUnlockKeepsViewRetryWithoutRestartingCue() {
        val controller = Robolectric.buildActivity(TextNotifyAlertActivity::class.java, intent()).setup()
        val activity = controller.get()
        click(activity)
        shadowOf(activity).nextStartedService
        TextNotifyPresentation.activeToken = null
        keyguard.setKeyguardLocked(true) // system cancellation callback
        assertFalse(activity.isFinishing)
        assertEquals(0, queued().length())
        assertNull(shadowOf(activity).nextStartedActivity)
        click(activity)
        assertNull(shadowOf(activity).nextStartedService)
        keyguard.setKeyguardLocked(false)
        assertRoutedOnce(activity)
        controller.pause().stop().destroy()
    }

    @Test @Config(sdk = [35])
    fun lockedViewOnModernAndroidStillWaitsForAuthentication() {
        lockedViewStopsCueButDoesNotRouteUntilUnlockAndSurvivesCueEnding()
    }

    @Test fun passiveNotificationActionAlsoRequestsUnlockWithoutAnActiveCue() {
        TextNotifyPresentation.activeToken = null
        val controller = Robolectric.buildActivity(TextNotifyAlertActivity::class.java, intent("view")).setup()
        val activity = controller.get()
        assertFalse(activity.isFinishing)
        assertEquals(0, queued().length())
        assertNull(shadowOf(activity).nextStartedService)
        keyguard.setKeyguardLocked(false)
        assertRoutedOnce(activity)
        controller.pause().stop().destroy()
    }

    @Test fun unlockedViewRoutesImmediately() {
        keyguard.setKeyguardLocked(false)
        val controller = Robolectric.buildActivity(TextNotifyAlertActivity::class.java, intent()).setup()
        click(controller.get())
        assertRoutedOnce(controller.get())
        controller.pause().stop().destroy()
    }

    @Test fun closeDoesNotUnlockOrOpen() {
        val controller = Robolectric.buildActivity(TextNotifyAlertActivity::class.java, intent()).setup()
        click(controller.get(), "关闭提醒")
        assertTrue(controller.get().isFinishing)
        assertEquals("stop", shadowOf(controller.get()).nextStartedService.action)
        keyguard.setKeyguardLocked(false)
        assertEquals(0, queued().length())
        assertNull(shadowOf(controller.get()).nextStartedActivity)
        controller.pause().stop().destroy()
    }

    @Test fun restoredPendingViewRetainsOriginalMessageAfterCueHasStopped() {
        val first = Robolectric.buildActivity(TextNotifyAlertActivity::class.java, intent()).setup()
        click(first.get())
        val state = Bundle()
        first.saveInstanceState(state).pause().stop().destroy()
        keyguard.setKeyguardLocked(true) // callback on destroyed Activity must not navigate
        TextNotifyPresentation.activeToken = null
        val next = Robolectric.buildActivity(TextNotifyAlertActivity::class.java, intent())
            .create(state).start().restoreInstanceState(state).resume().visible()
        assertFalse(next.get().isFinishing)
        assertEquals(0, queued().length())
        keyguard.setKeyguardLocked(false)
        assertRoutedOnce(next.get())
        next.pause().stop().destroy()
    }

    @Test fun accountSwitchWhileUnlockingCannotRouteOldMessage() {
        val controller = Robolectric.buildActivity(TextNotifyAlertActivity::class.java, intent()).setup()
        click(controller.get())
        TextNotifyPresentation.setTarget(app, "target_123456789012345678901234")
        keyguard.setKeyguardLocked(false)
        assertEquals(0, queued().length())
        assertNull(shadowOf(controller.get()).nextStartedActivity)
        controller.pause().stop().destroy()
    }
}
