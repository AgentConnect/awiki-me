package ai.awiki.awikime.push

import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Handler
import android.os.Looper
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import org.json.JSONObject

/** Single presenter for typed Notify intent; consent is device-local and account-scoped. */
internal object TextNotifyPresentation {
    const val ID = 924042
    private const val PASSIVE_ID = 924043
    private const val PASSIVE_PREFIX = "text_notify:"
    var pendingToken: String? = null
    var activeToken: String? = null
    var deadlineMillis: Long = 0
    var activePayload: String? = null
    private const val BINDING = "text_notify_local_binding_v1"
    private val main = Handler(Looper.getMainLooper())
    private fun binding(c: Context) = c.getSharedPreferences(BINDING, Context.MODE_PRIVATE)
    private fun target(c: Context) = binding(c).getString("target", null)
    private fun prefs(c: Context) = c.getSharedPreferences("text_notify_local_v1_" + (target(c) ?: "signed_out"), Context.MODE_PRIVATE)

    @Synchronized fun setTarget(c: Context, target: String?) {
        if (target(c) == target) return
        stop(c)
        cancelPassive(c)
        binding(c).edit().putString("target", target)
            .putLong("mute_revision", binding(c).getLong("mute_revision", 0) + 1).commit()
        prefs(c).edit().putBoolean("mutes_ready", false).commit()
        NotificationManagerCompat.from(c).cancel(ID)
    }

    @Synchronized fun configure(c: Context, values: Map<*, *>): Boolean {
        if (target(c) == null || values["target"] != target(c)) return false
        val enabled = values["enabled"] as? Boolean ?: return false
        val urgent = values["urgent_enabled"] as? Boolean ?: return false
        val saved = prefs(c).edit().putBoolean("enabled", enabled).putBoolean("urgent", urgent).commit()
        if (!enabled || !urgent) stop(c)
        if (!enabled) { NotificationManagerCompat.from(c).cancel(ID); cancelPassive(c) }
        return saved
    }

    fun effectiveSettings(c: Context, requestedTarget: String?): Map<String, Any>? {
        if (requestedTarget == null || requestedTarget != target(c)) return null
        val p = prefs(c)
        return mapOf("enabled" to p.getBoolean("enabled", true), "urgent_enabled" to p.getBoolean("urgent", false), "mutes_ready" to p.getBoolean("mutes_ready", false))
    }

    fun allows(c: Context, raw: String, urgent: Boolean): Boolean {
        val envelope = runCatching { JSONObject(raw).getJSONObject("extraMap") }.getOrNull() ?: return false
        val p = prefs(c)
        if (!p.getBoolean("mutes_ready", false)) return false
        val identity = envelope.optString("ir")
        if (identity in (p.getStringSet("local_mutes", emptySet()) ?: emptySet())) return false
        return target(c) != null && envelope.optString("ts") == target(c) &&
            p.getBoolean("enabled", true) && (!urgent || p.getBoolean("urgent", false))
    }

    /** Only called by the non-exported EMAS receiver; arbitrary intents have no entrypoint. */
    @Synchronized fun receive(c: Context, body: String?): Boolean {
        if (body == null || body.length > 8192) return false
        val payload = runCatching { JSONObject(body) }.getOrNull() ?: return false
        if (payload.optInt("awiki_notify") != 1) return false
        val extra = payload.optJSONObject("extraMap") ?: return true
        val notify = extra.optJSONObject("notify") ?: return true
        val now = System.currentTimeMillis() / 1000
        val expiry = notify.optLong("expires_at", 0)
        val level = notify.optString("level")
        val policyPrefs = prefs(c)
        if (extra.optInt("v") != 1 || extra.optString("ty") != "direct_message" ||
            notify.optInt("v") != 1 || level !in setOf("normal", "urgent") ||
            !TextNotifyPolicy.accepts(now, expiry, extra.optString("mid"), extra.optString("ts"),
                target(c), level, policyPrefs.getBoolean("enabled", true)) ||
            !allows(c, body, urgent = false)) return true
        val token = extra.optString("ts") + ":" + extra.optString("mid")
        val p = prefs(c)
        val receipts = runCatching { JSONObject(p.getString("receipts", "{}")!!) }.getOrDefault(JSONObject())
        // Keep all unexpired identities. At capacity fail closed rather than evict and re-alert.
        for (key in receipts.keys().asSequence().toList()) if (receipts.optLong(key) < now) receipts.remove(key)
        if (receipts.has(token) || receipts.length() >= 1024) return true
        receipts.put(token, now + 86400)
        if (!p.edit().putString("receipts", receipts.toString()).commit()) return true
        main.post {
            RemotePushEventBridge.emit(c, "notification_received", mapOf(
                "title" to payload.optString("title"), "summary" to payload.optString("summary"),
                "extraMap" to extra.toString()))
            if (!allows(c, body, urgent = false)) return@post
            if (activeToken != null || pendingToken != null) {
                showPassive(c, body)
                return@post
            }
            if (!TextNotifyPolicy.continuous(level, prefs(c).getBoolean("urgent", false))) {
                if (activeToken == null && !RemotePushPresentationState.isActivityResumed()) showPassive(c, body, silent = false)
            } else if (android.os.Build.VERSION.SDK_INT < 26) {
                showPassive(c, body)
            } else if (activeToken == null) {
                val last = binding(c).getLong("last_urgent_at", 0)
                if (now - last < 60) { showPassive(c, body); return@post }
                if (!binding(c).edit().putLong("last_urgent_at", now).commit()) return@post
                pendingToken = token
                try { c.startForegroundService(Intent(c, TextNotifyAlertService::class.java)
                    .putExtra("token", token).putExtra("payload", body)) }
                catch (_: RuntimeException) { pendingToken = null; showPassive(c, body) }
            }
        }
        return true
    }

    /** Invalidate before reading/writing the canonical overlay; stale snapshots cannot reopen it. */
    @Synchronized fun beginMuteSync(c: Context, requestedTarget: String?): Long? {
        if (requestedTarget == null || requestedTarget != target(c)) return null
        val revision = binding(c).getLong("mute_revision", 0) + 1
        if (!prefs(c).edit().putBoolean("mutes_ready", false).commit()) return null
        if (!binding(c).edit().putLong("mute_revision", revision).commit()) return null
        return revision
    }

    @Synchronized fun replaceMutes(c: Context, values: Map<*, *>): Boolean {
        if (target(c) == null || values["target"] != target(c)) return false
        val revision = (values["revision"] as? Number)?.toLong() ?: return false
        if (revision != binding(c).getLong("mute_revision", 0)) return false
        val raw = values["identities"] as? List<*> ?: return false
        if (raw.any { it !is String || !Regex("^identity_[A-Za-z0-9_-]{24}$").matches(it) }) return false
        val identities = raw.filterIsInstance<String>().toSet()
        if (!prefs(c).edit().putStringSet("local_mutes", identities)
                .putBoolean("mutes_ready", true).commit()) return false
        if (activePayload?.let { !allows(c, it, true) } == true) stop(c)
        cancelPassive(c, identities)
        return true
    }

    private fun cancelPassive(c: Context, identities: Set<String>? = null) {
        if (android.os.Build.VERSION.SDK_INT < 23) return
        val manager = c.getSystemService(android.app.NotificationManager::class.java)
        manager.activeNotifications.filter { notice ->
            val tag = notice.tag ?: ""
            tag.startsWith(PASSIVE_PREFIX) &&
                (identities == null || identities.any { tag.startsWith("$PASSIVE_PREFIX${target(c)}:$it:") })
        }.forEach { manager.cancel(it.tag, it.id) }
    }

    fun stop(c: Context) {
        if (activeToken != null || pendingToken != null) main.post { pendingToken = null; c.stopService(Intent(c, TextNotifyAlertService::class.java)) }
    }

    fun showPassive(c: Context, raw: String, silent: Boolean = true) {
        if (!allows(c, raw, urgent = false) || !NotificationManagerCompat.from(c).areNotificationsEnabled()) return
        val p = JSONObject(raw)
        val extra = p.getJSONObject("extraMap")
        val token = extra.getString("ts") + ":" + extra.getString("mid")
        val tag = PASSIVE_PREFIX + extra.getString("ts") + ":" + extra.optString("ir") + ":" + extra.getString("mid")
        val view = PendingIntent.getActivity(c, token.hashCode(),
            Intent(c, TextNotifyAlertActivity::class.java).setAction("view")
                .setData(android.net.Uri.parse("awiki-notify:" + tag))
                .putExtra("payload", raw).putExtra("token", token),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        val notice = NotificationCompat.Builder(c, "awiki_me_messages")
            .setSmallIcon(c.applicationInfo.icon).setContentTitle(p.optString("title").take(80))
            .setContentText(p.optString("summary").take(240)).setContentIntent(view)
            .setAutoCancel(true).setTimeoutAfter(86_400_000).setOnlyAlertOnce(true).setSilent(silent).build()
        runCatching { NotificationManagerCompat.from(c).notify(tag, PASSIVE_ID, notice) }
    }

    fun open(c: Context, raw: String) {
        // Settings stop new alerts, not navigation to an already received message.
        val payload = runCatching { JSONObject(raw) }.getOrNull() ?: return
        val extra = payload.optJSONObject("extraMap") ?: return
        if (!TextNotifyPolicy.canOpen(System.currentTimeMillis() / 1000,
            extra.optLong("exp"), extra.optString("ts"), target(c))) return
        val token = extra.optString("ts") + ":" + extra.optString("mid")
        NotificationManagerCompat.from(c).cancel(
            PASSIVE_PREFIX + extra.getString("ts") + ":" + extra.optString("ir") + ":" + extra.getString("mid"), PASSIVE_ID)
        if (activeToken == token) stop(c)
        RemotePushEventBridge.emit(c, "notification_opened", mapOf(
            "title" to payload.optString("title"), "summary" to payload.optString("summary"),
            "extraMap" to payload.getJSONObject("extraMap").toString()))
        val launch = c.packageManager.getLaunchIntentForPackage(c.packageName) ?: return
        c.startActivity(launch.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP))
    }
}
