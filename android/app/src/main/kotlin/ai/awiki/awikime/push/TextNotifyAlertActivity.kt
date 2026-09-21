package ai.awiki.awikime.push

import android.app.Activity
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
    private val tick = object : Runnable {
        override fun run() {
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
        token = intent.getStringExtra("token")
        payload = intent.getStringExtra("payload")
        if (intent.action == "view") { payload?.let { TextNotifyPresentation.open(this, it) }; finish(); return }
        val content = runCatching { org.json.JSONObject(payload ?: "") }.getOrNull()
        if (content == null) { finish(); return }
        if (token == null || token != TextNotifyPresentation.activeToken) { finish(); return }
        if (Build.VERSION.SDK_INT >= 27) { setShowWhenLocked(true); setTurnScreenOn(true) }
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
        handler.post(tick)
    }

    @Suppress("DEPRECATION")
    override fun onBackPressed() { stopAndExit(false) }

    private fun stopAndExit(view: Boolean) {
        startService(Intent(this, TextNotifyAlertService::class.java)
            .setAction("stop").putExtra("token", token))
        if (view) payload?.let { TextNotifyPresentation.open(this, it) }
        finish()
    }

    override fun onDestroy() { handler.removeCallbacks(tick); super.onDestroy() }
}
