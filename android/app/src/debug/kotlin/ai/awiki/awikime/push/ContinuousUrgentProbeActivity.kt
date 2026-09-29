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
import ai.awiki.awikime.MainActivity
import androidx.core.view.ViewCompat
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat

/** Remote-triggered Debug presentation, never an IM conversation or a real phone call. */
class ContinuousUrgentProbeActivity : Activity() {
    private val handler = Handler(Looper.getMainLooper())
    private var token: String? = null
    private lateinit var countdown: TextView
    private val tick = object : Runnable {
        override fun run() {
            if (token == null || token != ContinuousUrgentServiceProbe.activeToken) {
                finish()
                return
            }
            val remaining = (ContinuousUrgentServiceProbe.deadlineMillis - SystemClock.elapsedRealtime())
                .coerceAtLeast(0)
            countdown.text = "${(remaining + 999) / 1000} 秒后自动停止"
            handler.postDelayed(this, 250)
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        token = intent.getStringExtra("token")
        if (token == null || token != ContinuousUrgentServiceProbe.activeToken) { finish(); return }
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
        column.addView(text("AWiki Notify", 30f).apply { setTypeface(null, Typeface.BOLD) })
        column.addView(text("有一项任务需要你查看", 20f))
        column.addView(text("持续声振与自动弹出验证\n这是本机测试，不会执行任务操作。", 14f, Color.LTGRAY))
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
        startService(Intent(this, ContinuousUrgentProbeService::class.java)
            .setAction("stop").putExtra("token", token))
        // The prototype opens the App only. Real conversation routing remains a separate gate.
        if (view) startActivity(Intent(this, MainActivity::class.java))
        finish()
    }

    override fun onDestroy() { handler.removeCallbacks(tick); super.onDestroy() }
}
