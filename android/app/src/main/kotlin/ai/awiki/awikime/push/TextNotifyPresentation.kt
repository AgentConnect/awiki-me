package ai.awiki.awikime.push

import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Handler
import android.os.Looper
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import org.json.JSONObject

/** The only presenter for User Service-authorized text Notify provider envelopes. */
internal object TextNotifyPresentation {
    const val ID = 924042
    var activeToken: String? = null
    var deadlineMillis: Long = 0
    var activePayload: String? = null
    private const val PREFS = "text_notify_v1"
    private val main = Handler(Looper.getMainLooper())
    private fun prefs(c: Context) = c.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    @Synchronized fun setTarget(c: Context, target: String?) {
        val p = prefs(c)
        if (p.getString("target", null) == target) return
        p.edit().putString("target", target).putBoolean("enabled", false)
            .putBoolean("urgent", false).putLong("version", -1).remove("local_mutes").remove("server_mutes").remove("block_all").remove("block_urgent").commit()
        stop(c)
        NotificationManagerCompat.from(c).cancel(ID)
    }

    @Synchronized fun configure(c: Context, values: Map<*, *>): Boolean {
        val p = prefs(c)
        if (values["target"] != p.getString("target", null)) return false
        val enabled = values["enabled"] as? Boolean ?: return false
        val urgent = values["urgent_enabled"] as? Boolean ?: return false
        val version = (values["version"] as? Number)?.toLong() ?: return false
        if (version < 0 || version < p.getLong("version", -1)) return false
        val muted = (values["muted_identities"] as? List<*>)?.filterIsInstance<String>()?.toSet() ?: emptySet()
        val editor = p.edit()
        if (values["local_disable"] == true) {
            if (!enabled) editor.putBoolean("block_all", true)
            if (!urgent) editor.putBoolean("block_urgent", true)
        }
        if (values["explicit_save"] == true) {
            editor.putBoolean("block_all", !enabled).putBoolean("block_urgent", !urgent)
        }
        val saved = editor.putStringSet("server_mutes", muted).putBoolean("enabled", enabled).putBoolean("urgent", urgent)
            .putLong("version", version).commit()
        if (!enabled || !urgent || activePayload?.let { !allows(c, it, true) } == true) stop(c)
        if (!enabled) NotificationManagerCompat.from(c).cancel(ID)
        return saved
    }

    fun effectiveSettings(c: Context, target: String?): Map<String, Any>? {
        val p = prefs(c)
        if (target == null || target != p.getString("target", null)) return null
        return mapOf("enabled" to (p.getBoolean("enabled", false) && !p.getBoolean("block_all", false)),
            "urgent_enabled" to (p.getBoolean("urgent", false) && !p.getBoolean("block_urgent", false)),
            "version" to p.getLong("version", -1))
    }

    fun allows(c: Context, raw: String, urgent: Boolean): Boolean {
        val envelope = runCatching { JSONObject(raw).getJSONObject("extraMap") }.getOrNull() ?: return false
        val notify = envelope.optJSONObject("notify") ?: return false
        val p = prefs(c)
        val identity = envelope.optString("ir")
        if (identity in (p.getStringSet("local_mutes", emptySet()) ?: emptySet()) ||
            identity in (p.getStringSet("server_mutes", emptySet()) ?: emptySet())) return false
        return envelope.optString("ts") == p.getString("target", null) &&
            p.getBoolean("enabled", false) && !p.getBoolean("block_all", false) &&
            (!urgent || (p.getBoolean("urgent", false) && !p.getBoolean("block_urgent", false))) &&
            notify.optLong("preference_version", -2) == p.getLong("version", -1)
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
                policyPrefs.getString("target", null), level, policyPrefs.getBoolean("enabled", false),
                policyPrefs.getBoolean("urgent", false), notify.optLong("preference_version", -2),
                policyPrefs.getLong("version", -1)) ||
            !allows(c, body, level == "urgent")) return true
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
            if (!allows(c, body, level == "urgent")) return@post
            if (level == "normal") {
                if (activeToken == null && !RemotePushPresentationState.isActivityResumed()) showPassive(c, body, silent = false)
            } else if (android.os.Build.VERSION.SDK_INT < 26) {
                showPassive(c, body)
            } else if (activeToken == null) {
                val last = p.getLong("last_urgent_at", 0)
                if (now - last < 60) { showPassive(c, body); return@post }
                if (!p.edit().putLong("last_urgent_at", now).commit()) return@post
                try { c.startForegroundService(Intent(c, TextNotifyAlertService::class.java)
                    .putExtra("token", token).putExtra("payload", body)) }
                catch (_: RuntimeException) { showPassive(c, body) }
            }
        }
        return true
    }

    @Synchronized fun mute(c: Context, values: Map<*, *>): Boolean {
        val p = prefs(c)
        if (values["target"] != p.getString("target", null)) return false
        val peer = values["identity"] as? String ?: return false
        if (!Regex("^identity_[A-Za-z0-9_-]{24}$").matches(peer)) return false
        val muted = values["muted"] as? Boolean ?: return false
        val set = (p.getStringSet("local_mutes", emptySet()) ?: emptySet()).toMutableSet()
        if (muted) set.add(peer) else set.remove(peer)
        if (!p.edit().putStringSet("local_mutes", set).commit()) return false
        if (activePayload?.let { !allows(c, it, true) } == true) stop(c)
        return true
    }

    fun stop(c: Context) {
        if (activeToken != null) main.post { c.stopService(Intent(c, TextNotifyAlertService::class.java)) }
    }

    fun showPassive(c: Context, raw: String, silent: Boolean = true) {
        if (!allows(c, raw, urgent = false) || !NotificationManagerCompat.from(c).areNotificationsEnabled()) return
        val p = JSONObject(raw)
        val token = p.getJSONObject("extraMap").getString("mid")
        val view = PendingIntent.getActivity(c, token.hashCode(),
            Intent(c, TextNotifyAlertActivity::class.java).setAction("view")
                .putExtra("payload", raw).putExtra("token", token),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        val notice = NotificationCompat.Builder(c, "awiki_me_messages")
            .setSmallIcon(c.applicationInfo.icon).setContentTitle(p.optString("title").take(80))
            .setContentText(p.optString("summary").take(240)).setContentIntent(view)
            .setAutoCancel(true).setOnlyAlertOnce(true).setSilent(silent).build()
        runCatching { NotificationManagerCompat.from(c).notify(ID, notice) }
    }

    fun open(c: Context, raw: String) {
        // Settings stop new alerts, not navigation to an already received message.
        val payload = runCatching { JSONObject(raw) }.getOrNull() ?: return
        val extra = payload.optJSONObject("extraMap") ?: return
        if (!TextNotifyPolicy.canOpen(System.currentTimeMillis() / 1000,
            extra.optLong("exp"), extra.optString("ts"), prefs(c).getString("target", null))) return
        val token = extra.optString("ts") + ":" + extra.optString("mid")
        if (activeToken == token) stop(c)
        RemotePushEventBridge.emit(c, "notification_opened", mapOf(
            "title" to payload.optString("title"), "summary" to payload.optString("summary"),
            "extraMap" to payload.getJSONObject("extraMap").toString()))
        val launch = c.packageManager.getLaunchIntentForPackage(c.packageName) ?: return
        c.startActivity(launch.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP))
    }
}
