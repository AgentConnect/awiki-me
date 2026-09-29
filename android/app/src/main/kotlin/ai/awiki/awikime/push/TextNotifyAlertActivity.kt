package ai.awiki.awikime.push

import android.app.Activity
import android.app.KeyguardManager
import android.content.Intent
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.view.Gravity
import android.view.WindowManager
import android.widget.Button
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import androidx.core.view.ViewCompat
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat

/** Task reminder UI; View routes through Core-backed push message resolution. */
class TextNotifyAlertActivity : Activity() {
    private val handler = Handler(Looper.getMainLooper())
    private var token: String? = null
    private var payload: String? = null
    private lateinit var countdown: TextView
    private var viewing = false
    private var dismissPending = false
    private var opened = false
    private var openOnResume = false
    private var generation = 0
    private var credentialRequestCode: Int? = null
    private val tick = object : Runnable {
        override fun run() {
            if (viewing) return
            if (token == null || token != TextNotifyPresentation.activeToken) {
                finish()
                return
            }
            val remaining = (TextNotifyPresentation.deadlineMillis - SystemClock.elapsedRealtime())
                .coerceAtLeast(0)
            countdown.text = "${(remaining + 999) / 1000} 秒后自动停止"
            handler.postDelayed(this, 250)
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val restoredIntent = Intent(intent)
        if (savedInstanceState?.containsKey("payload") == true) {
            restoredIntent.putExtra("token", savedInstanceState.getString("token"))
                .putExtra("payload", savedInstanceState.getString("payload"))
        }
        bindIntent(restoredIntent, savedInstanceState?.getBoolean("viewing") == true)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        // Re-delivery must not replace an in-flight unlock for the same message.
        if (token == intent.getStringExtra("token") && payload == intent.getStringExtra("payload")) {
            if (intent.action == "view") requestOpen()
            return
        }
        bindIntent(intent)
    }

    private fun bindIntent(next: Intent, restoredViewing: Boolean = false) {
        generation++ // Fence callbacks belonging to the previous reminder.
        handler.removeCallbacks(tick)
        setIntent(next)
        token = next.getStringExtra("token")
        payload = next.getStringExtra("payload")
        dismissPending = false
        credentialRequestCode = null
        opened = false
        viewing = restoredViewing || next.action == "view"
        openOnResume = viewing
        val content = runCatching { org.json.JSONObject(payload ?: "") }.getOrNull()
        if (content == null) { finish(); return }
        if (!viewing && (token == null || token != TextNotifyPresentation.activeToken)) { finish(); return }
        if (Build.VERSION.SDK_INT >= 27) { setShowWhenLocked(true); setTurnScreenOn(true) }
        else {
            @Suppress("DEPRECATION")
            window.addFlags(WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON)
        }
        actionBar?.hide()
        WindowCompat.setDecorFitsSystemWindows(window, false)
        fun dp(value: Int) = (value * resources.displayMetrics.density).toInt()
        val column = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER_HORIZONTAL
            setPadding(dp(28), dp(32), dp(28), dp(32))
        }
        fun text(value: String, size: Float, color: Int = Color.WHITE): TextView = TextView(this).apply {
            text = value; textSize = size; setTextColor(color); gravity = Gravity.CENTER
            setPadding(0, dp(12), 0, dp(12))
        }
        column.addView(text("AWiki · 紧急提醒", 18f, Color.rgb(255, 192, 87)))
        column.addView(TextView(this), LinearLayout.LayoutParams(1, 0, 1f))
        column.addView(ImageView(this).apply {
            setImageResource(applicationInfo.icon)
            contentDescription = "AWiki"
        }, LinearLayout.LayoutParams(dp(88), dp(88)))
        column.addView(text(content.optString("title").take(80), 30f).apply { setTypeface(null, Typeface.BOLD) })
        column.addView(text(content.optString("summary").take(240), 20f))
        column.addView(text("查看消息后，请回到电脑继续处理任务。", 14f, Color.LTGRAY))
        countdown = text("", 16f, Color.LTGRAY)
        column.addView(countdown)
        column.addView(TextView(this), LinearLayout.LayoutParams(1, 0, 1f))
        val buttons = LinearLayout(this).apply { gravity = Gravity.CENTER }
        fun button(label: String, color: Int, view: Boolean) = Button(this).apply {
            text = label; textSize = 17f; setTextColor(Color.WHITE); isAllCaps = false
            background = GradientDrawable().apply { setColor(color); cornerRadius = dp(36).toFloat() }
            setOnClickListener { stopAndExit(view) }
        }
        buttons.addView(button("关闭提醒", Color.rgb(191, 72, 77), false),
            LinearLayout.LayoutParams(0, dp(68), 1f).apply { marginEnd = dp(12) })
        buttons.addView(button("查看消息", Color.rgb(43, 150, 103), true),
            LinearLayout.LayoutParams(0, dp(68), 1f).apply { marginStart = dp(12) })
        column.addView(buttons, LinearLayout.LayoutParams(-1, -2))
        val scroll = ScrollView(this).apply {
            isFillViewport = true
            background = GradientDrawable(GradientDrawable.Orientation.TOP_BOTTOM,
                intArrayOf(Color.rgb(36, 53, 48), Color.rgb(22, 23, 19)))
            addView(column)
        }
        ViewCompat.setOnApplyWindowInsetsListener(scroll) { view, insets ->
            val bars = insets.getInsets(WindowInsetsCompat.Type.systemBars())
            view.setPadding(bars.left, bars.top, bars.right, bars.bottom)
            insets
        }
        setContentView(scroll)
        if (!viewing) handler.post(tick)
    }

    override fun onResume() {
        super.onResume()
        if (openOnResume) {
            openOnResume = false
            requestOpen()
        }
    }

    override fun onSaveInstanceState(outState: Bundle) {
        outState.putBoolean("viewing", viewing)
        outState.putString("token", token)
        outState.putString("payload", payload)
        super.onSaveInstanceState(outState)
    }

    @Suppress("DEPRECATION")
    override fun onBackPressed() { stopAndExit(false) }

    private fun stopAndExit(view: Boolean) {
        if (view) requestOpen()
        else {
            stopMatchingCue()
            finish()
        }
    }

    private fun stopMatchingCue() {
        if (token != null && token == TextNotifyPresentation.activeToken) {
            startService(Intent(this, TextNotifyAlertService::class.java)
                .setAction("stop").putExtra("token", token))
        }
    }

    private fun requestOpen() {
        if (dismissPending || opened || isFinishing || isDestroyed) return
        viewing = true
        handler.removeCallbacks(tick)
        stopMatchingCue()
        val keyguard = getSystemService(KeyguardManager::class.java)
        if (!keyguard.isKeyguardLocked) { openAfterUnlock(); return }
        countdown.text = "请先解锁手机，再查看消息"
        dismissPending = true
        val requestGeneration = generation
        if (Build.VERSION.SDK_INT >= 26) {
            keyguard.requestDismissKeyguard(this, object : KeyguardManager.KeyguardDismissCallback() {
                override fun onDismissSucceeded() {
                    if (requestGeneration != generation) return
                    dismissPending = false
                    openAfterUnlock()
                }
                override fun onDismissCancelled() { if (requestGeneration == generation) unlockNotCompleted() }
                override fun onDismissError() { if (requestGeneration == generation) unlockNotCompleted() }
            })
        } else {
            // Android 7: let the system authenticate; never disable or bypass the lock.
            @Suppress("DEPRECATION")
            val unlock = keyguard.createConfirmDeviceCredentialIntent("查看 AWiki 消息", null)
            if (unlock != null) {
                credentialRequestCode = 4101 + generation
                startActivityForResult(unlock, credentialRequestCode!!)
            }
            else unlockNotCompleted()
        }
    }

    private fun unlockNotCompleted() {
        dismissPending = false
        if (!isFinishing && !isDestroyed) countdown.text = "尚未解锁，点击查看消息可重试"
    }

    private fun openAfterUnlock() {
        if (opened || isFinishing || isDestroyed) return
        if (getSystemService(KeyguardManager::class.java).isKeyguardLocked) {
            unlockNotCompleted()
            return
        }
        opened = true
        payload?.let { TextNotifyPresentation.open(this, it) }
        finish()
    }

    @Deprecated("Legacy Android credential result")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == credentialRequestCode) {
            credentialRequestCode = null
            dismissPending = false
            if (resultCode == RESULT_OK) openAfterUnlock() else unlockNotCompleted()
        }
    }

    override fun onDestroy() { handler.removeCallbacks(tick); super.onDestroy() }
}
