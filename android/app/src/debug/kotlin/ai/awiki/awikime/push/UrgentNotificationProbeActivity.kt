package ai.awiki.awikime.push

import android.app.Activity
import android.app.Notification
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import android.view.View
import android.widget.Button
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import androidx.core.view.ViewCompat
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import ai.awiki.awikime.MainActivity

/** Local platform probe, not an IM message or evidence of provider delivery. */
class UrgentNotificationProbeActivity : Activity() {
    private var foreground = false
    private lateinit var cue: ForegroundUrgentCueController
    private lateinit var status: TextView

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        actionBar?.hide()
        WindowCompat.setDecorFitsSystemWindows(window, false)
        cue = ForegroundUrgentCueController(this) { foreground }
        UrgentNotificationChannel.ensureCreated(this)
        val column = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(32, 72, 32, 32)
        }
        column.addView(TextView(this).apply {
            text = "紧急提醒 · 本机能力验证\n仅验证 Android 通道与声振，不代表远端消息已送达。"
            textSize = 20f
        })
        status = TextView(this).apply { textSize = 16f }
        column.addView(status)
        fun action(label: String, block: () -> Unit) {
            column.addView(Button(this).apply {
                text = label
                setOnClickListener { block() }
            })
        }
        action("开始前台提醒（最多30秒）") { refresh("start=${cue.start()}") }
        action("再次触发（不得延长）") { refresh("repeat_start=${cue.start()}") }
        action("停止提醒") { cue.stop(); refresh("stopped") }
        action("发送本机系统通知") { postLocalNotification(); refresh("local_notification_submitted") }
        action("重复同一系统通知") { postLocalNotification(); refresh("same_local_id_submitted") }
        action("清除本机测试通知") {
            getSystemService(NotificationManager::class.java).cancel(PROBE_ID)
            refresh("local_notification_cleared")
        }
        action("系统紧急通道设置") {
            startActivity(Intent(Settings.ACTION_CHANNEL_NOTIFICATION_SETTINGS).apply {
                putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
                putExtra(Settings.EXTRA_CHANNEL_ID, UrgentNotificationChannel.ID)
            })
        }
        action("返回 AWiki Me") {
            cue.stop()
            startActivity(Intent(this, MainActivity::class.java))
            finish()
        }
        val scroll = ScrollView(this).apply { addView(column) }
        ViewCompat.setOnApplyWindowInsetsListener(scroll) { view, insets ->
            val bars = insets.getInsets(WindowInsetsCompat.Type.systemBars())
            view.setPadding(bars.left, bars.top, bars.right, bars.bottom)
            insets
        }
        scroll.systemUiVisibility = View.SYSTEM_UI_FLAG_LIGHT_STATUS_BAR
        setContentView(scroll)
    }

    override fun onResume() {
        super.onResume()
        foreground = true
        refresh("ready")
    }

    override fun onPause() { foreground = false; cue.stop(); super.onPause() }
    override fun onDestroy() { cue.stop(); super.onDestroy() }

    private fun refresh(result: String) {
        val state = cue.readState()
        val decision = UrgentCuePolicy.evaluate(state)
        status.text = "$result\n通知权限=${state.notificationsEnabled} 通道等级=${state.channelImportance}\n" +
            "系统铃声模式=${state.ringerMode} 通知音量=${state.notificationVolume} 勿扰放行=${state.interruptionFilterAllowsAll}\n" +
            "允许前台层=${decision.allowed} 请求声音=${decision.sound} 请求振动=${decision.vibration}\n" +
            "实际听到/感到仍需现场确认。"
    }

    private fun postLocalNotification() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val pending = PendingIntent.getActivity(this, 0, Intent(this, javaClass),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        val notification = Notification.Builder(this, UrgentNotificationChannel.ID)
            .setSmallIcon(applicationInfo.icon)
            .setContentTitle("AWiki 紧急提醒本机测试")
            .setContentText("这是本机通道验证，没有发送任务消息。")
            .setContentIntent(pending)
            .setOnlyAlertOnce(true)
            .setAutoCancel(true)
            .build()
        getSystemService(NotificationManager::class.java).notify(PROBE_ID, notification)
    }

    companion object { private const val PROBE_ID = 924021 }
}
