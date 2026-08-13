package ai.awiki.awikime

import android.app.Activity
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView

class AliveBackgroundUrgentActivity : Activity() {
    private val timeoutHandler = Handler(Looper.getMainLooper())
    private var nativeId: Int = -1
    private var session: AliveBackgroundUrgentSession? = null
    private val externalStop: (AliveBackgroundUrgentStopReason) -> Unit = { reason ->
        runOnUiThread {
            session?.stop(reason)
            if (!isFinishing) finish()
        }
    }
    private val timeout = Runnable {
        session?.stop(AliveBackgroundUrgentStopReason.TIMEOUT)
        finish()
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
        } else {
            @Suppress("DEPRECATION")
            window.addFlags(
                android.view.WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                    android.view.WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON,
            )
        }
        window.statusBarColor = BACKGROUND
        window.navigationBarColor = BACKGROUND

        nativeId = intent.getIntExtra(EXTRA_NATIVE_ID, -1)
        val token = intent.getStringExtra(EXTRA_CONTENT_TOKEN)
        val content = if (nativeId >= 0 && !token.isNullOrBlank()) {
            AliveBackgroundUrgentNotificationController.content(nativeId, token)
        } else {
            null
        }
        if (content == null) {
            finish()
            return
        }
        session = AliveBackgroundUrgentSession(
            cancel = { reason ->
                AliveBackgroundUrgentNotificationController.cancel(
                    applicationContext,
                    nativeId,
                    reason,
                )
            },
            emitOpaqueOpen = {
                AliveBackgroundUrgentOpenReceiver.open(
                    applicationContext,
                    nativeId,
                    content.opaqueMessageReference,
                    content.expiresAtEpochSeconds,
                )
            },
        )
        if (!AliveBackgroundUrgentNotificationController.registerSurface(nativeId, externalStop)) {
            session = null
            finish()
            return
        }
        setContentView(buildContent(content))
        timeoutHandler.postDelayed(timeout, AliveBackgroundUrgentPolicy.MAX_CUE_DURATION_MILLIS)
    }

    @Deprecated("Deprecated in Java")
    override fun onBackPressed() {
        session?.stop(AliveBackgroundUrgentStopReason.BACK)
        finish()
    }

    override fun onDestroy() {
        timeoutHandler.removeCallbacks(timeout)
        AliveBackgroundUrgentNotificationController.unregisterSurface(externalStop)
        session?.stop(AliveBackgroundUrgentStopReason.PROCESS)
        super.onDestroy()
    }

    private fun buildContent(
        content: AliveBackgroundUrgentNotificationController.CommittedContent,
    ): View {
        val column = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER_HORIZONTAL
            setPadding(dp(24), dp(14), dp(24), dp(28))
            setBackgroundColor(BACKGROUND)
        }

        column.addView(label(getString(R.string.alive_urgent_back), TEXT_PRIMARY).apply {
            gravity = Gravity.START or Gravity.CENTER_VERTICAL
            setPadding(0, dp(10), 0, dp(10))
            setOnClickListener {
                session?.stop(AliveBackgroundUrgentStopReason.DISMISS)
                finish()
            }
        }, matchWrap())

        column.addView(label(getString(R.string.alive_urgent_title), AMBER, bold = true).apply {
            gravity = Gravity.CENTER
            setPadding(0, dp(22), 0, dp(14))
        }, matchWrap())

        column.addView(identityRings(content.agentLabel), linearCentered(dp(248), dp(248)))

        column.addView(label(content.agentLabel, Color.WHITE, bold = true).apply {
            gravity = Gravity.CENTER
            maxLines = 1
        }, matchWrap())
        column.addView(label(getString(R.string.alive_urgent_skill_agent), TEXT_MUTED).apply {
            gravity = Gravity.CENTER
            setPadding(0, dp(5), 0, dp(18))
        }, matchWrap())

        column.addView(label(content.taskName, AMBER, bold = true).apply {
            gravity = Gravity.CENTER
            maxLines = 2
            setPadding(0, 0, 0, dp(8))
        }, matchWrap())
        column.addView(label(content.summary, TEXT_PRIMARY, bold = true).apply {
            gravity = Gravity.CENTER
            maxLines = 4
            setPadding(0, 0, 0, dp(14))
        }, matchWrap())
        column.addView(label(getString(R.string.alive_urgent_not_voice_call), TEXT_MUTED).apply {
            gravity = Gravity.CENTER
            setPadding(0, 0, 0, dp(14))
        }, matchWrap())

        column.addView(label(getString(R.string.alive_urgent_cue_stops), TEXT_SECONDARY).apply {
            gravity = Gravity.CENTER
            setPadding(dp(16), dp(12), dp(16), dp(12))
            background = roundedStroke(AMBER, 13f)
        }, linearCentered(ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT))

        column.addView(actionRow(), matchWrap().apply { topMargin = dp(34) })

        return ScrollView(this).apply {
            isFillViewport = true
            setBackgroundColor(BACKGROUND)
            addView(column, ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT)
        }
    }

    private fun identityRings(agentLabel: String): FrameLayout {
        val initial = agentLabel.trim().firstOrNull()?.uppercase() ?: "A"
        return FrameLayout(this).apply {
            for ((size, alpha) in listOf(230 to 0x10, 200 to 0x22, 166 to 0x35, 132 to 0x52)) {
                addView(View(context).apply {
                    background = GradientDrawable().apply {
                        shape = GradientDrawable.OVAL
                        setColor(if (size == 230) Color.argb(alpha, 255, 180, 0) else Color.TRANSPARENT)
                        setStroke(dp(1), Color.argb(alpha, 184, 129, 0))
                    }
                }, frameCentered(dp(size), dp(size)))
            }
            addView(label(initial, Color.rgb(107, 67, 0), bold = true).apply {
                gravity = Gravity.CENTER
                background = oval(Color.rgb(243, 226, 197))
            }, frameCentered(dp(82), dp(82)))
        }
    }

    private fun actionRow(): LinearLayout = LinearLayout(this).apply {
        orientation = LinearLayout.HORIZONTAL
        gravity = Gravity.CENTER
        addView(actionColumn("×", R.string.alive_urgent_ignore, RED) {
            session?.stop(AliveBackgroundUrgentStopReason.DISMISS)
            finish()
        }, LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f))
        addView(actionColumn("✓", R.string.alive_urgent_act_now, BLUE) {
            session?.stop(AliveBackgroundUrgentStopReason.ACTION, openTarget = true)
            finish()
        }, LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f))
    }

    private fun actionColumn(
        symbol: String,
        labelResource: Int,
        color: Int,
        onClick: () -> Unit,
    ): LinearLayout = LinearLayout(this).apply {
        orientation = LinearLayout.VERTICAL
        gravity = Gravity.CENTER_HORIZONTAL
        addView(label(symbol, Color.WHITE, bold = true).apply {
            gravity = Gravity.CENTER
            background = oval(color)
            contentDescription = getString(labelResource)
            setOnClickListener { onClick() }
        }, linearCentered(dp(72), dp(72)))
        addView(label(getString(labelResource), TEXT_PRIMARY).apply {
            gravity = Gravity.CENTER
            setPadding(0, dp(10), 0, 0)
        }, linearCentered(ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT))
    }

    private fun label(value: String, color: Int, bold: Boolean = false) = TextView(this).apply {
        text = value
        textSize = 14f
        setTextColor(color)
        typeface = if (bold) Typeface.DEFAULT_BOLD else Typeface.DEFAULT
    }

    private fun roundedStroke(color: Int, radius: Float) = GradientDrawable().apply {
        shape = GradientDrawable.RECTANGLE
        cornerRadius = dp(radius.toInt()).toFloat()
        setColor(Color.TRANSPARENT)
        setStroke(dp(1), color)
    }

    private fun oval(color: Int) = GradientDrawable().apply {
        shape = GradientDrawable.OVAL
        setColor(color)
    }

    private fun matchWrap() = LinearLayout.LayoutParams(
        ViewGroup.LayoutParams.MATCH_PARENT,
        ViewGroup.LayoutParams.WRAP_CONTENT,
    )

    private fun frameCentered(width: Int, height: Int) =
        FrameLayout.LayoutParams(width, height, Gravity.CENTER)

    private fun linearCentered(width: Int, height: Int) =
        LinearLayout.LayoutParams(width, height).apply { gravity = Gravity.CENTER_HORIZONTAL }

    private fun dp(value: Int): Int = (value * resources.displayMetrics.density).toInt()

    companion object {
        const val EXTRA_NATIVE_ID = "native_id"
        const val EXTRA_CONTENT_TOKEN = "content_token"
        private val BACKGROUND = Color.rgb(22, 23, 19)
        private val AMBER = Color.rgb(255, 180, 0)
        private val TEXT_PRIMARY = Color.rgb(241, 232, 215)
        private val TEXT_SECONDARY = Color.rgb(216, 203, 183)
        private val TEXT_MUTED = Color.rgb(184, 173, 154)
        private val RED = Color.rgb(233, 52, 52)
        private val BLUE = Color.rgb(9, 141, 218)
    }
}
