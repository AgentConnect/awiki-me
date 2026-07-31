package ai.awiki.awikime.push

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import com.alibaba.sdk.android.push.CommonCallback
import com.alibaba.sdk.android.push.noonesdk.PushServiceFactory
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject
import java.util.UUID

object RemotePushEventBridge {
    private const val CHANNEL_NAME = "ai.awiki.awikime/remote_push_events"
    private const val PREFERENCES_NAME = "awiki_remote_push_events"
    private const val EVENTS_KEY = "pending_events"
    private const val MAX_PENDING_EVENTS = 32
    private const val MAX_PENDING_AGE_MS = 24 * 60 * 60 * 1000L
    private const val MAX_PERSISTED_STRING_LENGTH = 256
    private val PERSISTED_ENVELOPE_KEYS = setOf(
        "v",
        "eid",
        "ty",
        "ts",
        "ir",
        "tr",
        "mid",
        "exp",
    )

    private val mainHandler = Handler(Looper.getMainLooper())
    private val registrationLock = Any()
    private val registrationState = RemotePushRegistrationState()
    private val pendingInitializationResults = mutableListOf<MethodChannel.Result>()
    @Volatile
    private var channel: MethodChannel? = null

    fun attach(context: Context, messenger: BinaryMessenger) {
        val applicationContext = context.applicationContext
        channel = MethodChannel(messenger, CHANNEL_NAME).also { methodChannel ->
            methodChannel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "isConfigured" -> result.success(
                        ai.awiki.awikime.BuildConfig.AWIKI_EMAS_ENABLED,
                    )
                    "initialize" -> initializePush(applicationContext, result)
                    "getAppId" -> result.success(
                        if (ai.awiki.awikime.BuildConfig.AWIKI_EMAS_ENABLED) {
                            ai.awiki.awikime.BuildConfig.AWIKI_EMAS_APP_KEY
                        } else {
                            ""
                        },
                    )
                    "getDeviceId" -> {
                        try {
                            val deviceId = readyDeviceId() ?: ""
                            if (
                                ai.awiki.awikime.BuildConfig.DEBUG &&
                                ai.awiki.awikime.BuildConfig.AWIKI_EMAS_LOG_DEVICE_ID
                            ) {
                                Log.d("AWikiRemotePush", "EMAS DeviceId: $deviceId")
                            }
                            result.success(deviceId)
                        } catch (error: Throwable) {
                            result.error("get_device_id_failed", error.javaClass.simpleName, null)
                        }
                    }
                    "createNotificationChannel" -> createNotificationChannel(
                        applicationContext,
                        call.arguments as? Map<*, *>,
                        result,
                    )
                    "wakeNotificationScreen" -> {
                        NotificationScreenWakeController.wakeIfNeeded(applicationContext)
                        result.success(null)
                    }
                    "loadPendingEvents" -> result.success(load(applicationContext))
                    "acknowledgePendingEvents" -> {
                        val deliveryIds = (call.arguments as? List<*>)
                            ?.filterIsInstance<String>()
                            ?.toSet()
                            ?: emptySet()
                        acknowledge(applicationContext, deliveryIds)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }

    private fun initializePush(context: Context, result: MethodChannel.Result) {
        if (!ai.awiki.awikime.BuildConfig.AWIKI_EMAS_ENABLED) {
            result.success(mapOf("code" to "configuration_disabled"))
            return
        }
        try {
            if (readyDeviceId() != null) {
                result.success(mapOf("code" to "10000"))
                return
            }

            val registrationAction = synchronized(registrationLock) {
                if (readyDeviceId() != null) {
                    mainHandler.post { result.success(mapOf("code" to "10000")) }
                    return@synchronized RemotePushRegistrationAction.RETURN_SUCCESS
                }
                val action = registrationState.beginInitialization()
                if (action == RemotePushRegistrationAction.RETURN_SUCCESS) {
                    mainHandler.post { result.success(mapOf("code" to "10000")) }
                } else {
                    pendingInitializationResults.add(result)
                }
                action
            }
            if (registrationAction != RemotePushRegistrationAction.START) {
                return
            }

            PushServiceFactory.getCloudPushService().register(
                context,
                object : CommonCallback {
                    override fun onSuccess(response: String?) {
                        completeRegistrationSuccess(context)
                    }

                    override fun onFailed(errorCode: String?, errorMessage: String?) {
                        if (errorCode == "PUSH_20110" && readyDeviceId() != null) {
                            completeRegistrationSuccess(context)
                            return
                        }
                        val safeErrorCode = errorCode
                            ?.takeIf { it.matches(Regex("[A-Za-z0-9_-]{1,32}")) }
                            ?: "registration_failed"
                        Log.e(
                            "AWikiRemotePush",
                            "EMAS registration failed code=$safeErrorCode",
                        )
                        completeRegistrationFailure(
                            errorCode = errorCode ?: "registration_failed",
                            errorMessage = errorMessage,
                        )
                    }
                },
            )
        } catch (error: Throwable) {
            completeRegistrationFailure(
                errorCode = "native_exception",
                errorMessage = error.javaClass.simpleName,
            )
        }
    }

    private fun readyDeviceId(): String? {
        return runCatching {
            PushServiceFactory.getCloudPushService().deviceId
                ?.trim()
                ?.takeIf { it.isNotEmpty() }
        }.getOrNull()
    }

    private fun completeRegistrationSuccess(context: Context) {
        Log.i("AWikiRemotePush", "EMAS registration succeeded")
        val results = synchronized(registrationLock) {
            registrationState.completeSuccess()
            pendingInitializationResults.toList().also {
                pendingInitializationResults.clear()
            }
        }
        emit(context, "registration_changed", emptyMap())
        mainHandler.post {
            results.forEach { it.success(mapOf("code" to "10000")) }
        }
    }

    private fun completeRegistrationFailure(
        errorCode: String,
        errorMessage: String?,
    ) {
        val response = mapOf(
            "code" to errorCode,
            "errorMsg" to errorMessage,
        )
        val results = synchronized(registrationLock) {
            registrationState.completeFailure()
            pendingInitializationResults.toList().also {
                pendingInitializationResults.clear()
            }
        }
        mainHandler.post {
            results.forEach { it.success(response) }
        }
    }

    private fun createNotificationChannel(
        context: Context,
        arguments: Map<*, *>?,
        result: MethodChannel.Result,
    ) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            result.success(mapOf("code" to "10005"))
            return
        }
        val id = arguments?.get("id") as? String
        val name = arguments?.get("name") as? String
        val description = arguments?.get("description") as? String
        if (id.isNullOrBlank() || name.isNullOrBlank()) {
            result.success(
                mapOf("code" to "10001", "errorMsg" to "channel id and name are required"),
            )
            return
        }
        val manager = context.getSystemService(NotificationManager::class.java)
        val channel = NotificationChannel(id, name, NotificationManager.IMPORTANCE_MAX).apply {
            this.description = description
            enableVibration(true)
            setShowBadge(true)
        }
        manager.createNotificationChannel(channel)
        result.success(mapOf("code" to "10000"))
    }

    fun detach() {
        channel?.setMethodCallHandler(null)
        channel = null
    }

    fun emit(context: Context, kind: String, payload: Map<String, Any?>) {
        val event = mapOf(
            "delivery_id" to UUID.randomUUID().toString(),
            "kind" to kind,
            "payload" to payload,
            "received_at_ms" to System.currentTimeMillis(),
        )
        val applicationContext = context.applicationContext
        persist(applicationContext, event)
        val activeChannel = channel
        if (activeChannel == null) {
            return
        }
        mainHandler.post {
            activeChannel.invokeMethod(
                "onRemotePushEvents",
                listOf(event),
                object : MethodChannel.Result {
                    override fun success(result: Any?) = Unit

                    override fun error(code: String, message: String?, details: Any?) = Unit

                    override fun notImplemented() = Unit
                },
            )
        }
    }

    @Synchronized
    private fun persist(context: Context, event: Map<String, Any?>) {
        val safeEvent = eventForPersistence(event) ?: return
        val preferences = context.getSharedPreferences(PREFERENCES_NAME, Context.MODE_PRIVATE)
        val existing = runCatching {
            JSONArray(preferences.getString(EVENTS_KEY, "[]"))
        }.getOrElse { JSONArray() }
        val now = System.currentTimeMillis()
        val existingEvents = buildList {
            for (index in 0 until existing.length()) {
                val value = existing.optJSONObject(index) ?: continue
                val existingEvent = eventForPersistence(jsonObjectToMap(value)) ?: continue
                val receivedAt = existingEvent["received_at_ms"] as? Number ?: continue
                if (now - receivedAt.toLong() > MAX_PENDING_AGE_MS) continue
                add(existingEvent)
            }
        }.takeLast(MAX_PENDING_EVENTS - 1)
        val retained = JSONArray()
        for (existingEvent in existingEvents) {
            retained.put(JSONObject(existingEvent))
        }
        retained.put(JSONObject(safeEvent))
        preferences.edit().putString(EVENTS_KEY, retained.toString()).commit()
    }

    @Synchronized
    private fun load(context: Context): List<Map<String, Any?>> {
        val preferences = context.getSharedPreferences(PREFERENCES_NAME, Context.MODE_PRIVATE)
        val stored = runCatching {
            JSONArray(preferences.getString(EVENTS_KEY, "[]"))
        }.getOrElse { JSONArray() }
        val now = System.currentTimeMillis()
        val events = buildList {
            for (index in 0 until stored.length()) {
                val value = stored.optJSONObject(index) ?: continue
                val event = eventForPersistence(jsonObjectToMap(value)) ?: continue
                val receivedAt = event["received_at_ms"] as? Number ?: continue
                if (now - receivedAt.toLong() > MAX_PENDING_AGE_MS) continue
                add(event)
            }
        }
        preferences.edit().putString(EVENTS_KEY, JSONArray(events).toString()).commit()
        return events
    }

    @Synchronized
    private fun acknowledge(context: Context, deliveryIds: Set<String>) {
        if (deliveryIds.isEmpty()) return
        val preferences = context.getSharedPreferences(PREFERENCES_NAME, Context.MODE_PRIVATE)
        val stored = runCatching {
            JSONArray(preferences.getString(EVENTS_KEY, "[]"))
        }.getOrElse { JSONArray() }
        val retained = JSONArray()
        for (index in 0 until stored.length()) {
            val event = stored.optJSONObject(index) ?: continue
            if (event.optString("delivery_id") !in deliveryIds) {
                retained.put(event)
            }
        }
        preferences.edit().putString(EVENTS_KEY, retained.toString()).commit()
    }

    private fun eventForPersistence(event: Map<String, Any?>): Map<String, Any?>? {
        val kind = event["kind"] as? String ?: return null
        val deliveryId = boundedString(event["delivery_id"]) ?: return null
        if (kind != "notification_opened" && kind != "message_received") {
            return null
        }
        val sourcePayload = event["payload"] as? Map<*, *> ?: emptyMap<Any?, Any?>()
        val safePayload = buildMap<String, Any?> {
            boundedString(sourcePayload["msgId"])?.let { put("msgId", it) }
            sanitizeEnvelope(sourcePayload["extraMap"])
                .takeIf { it.isNotEmpty() }
                ?.let { put("extraMap", it) }
        }
        val receivedAt = event["received_at_ms"] as? Number ?: return null
        return mapOf(
            "delivery_id" to deliveryId,
            "kind" to kind,
            "payload" to safePayload,
            "received_at_ms" to receivedAt.toLong(),
        )
    }

    private fun sanitizeEnvelope(value: Any?): Map<String, Any?> {
        val source = when (value) {
            is Map<*, *> -> value.entries.associate { it.key.toString() to it.value }
            is String -> runCatching { jsonObjectToMap(JSONObject(value)) }.getOrNull()
            else -> null
        } ?: return emptyMap()
        return buildMap {
            for (key in PERSISTED_ENVELOPE_KEYS) {
                val safeValue = when (val candidate = source[key]) {
                    is String -> candidate.take(MAX_PERSISTED_STRING_LENGTH)
                    is Number, is Boolean -> candidate
                    else -> null
                }
                if (safeValue != null) put(key, safeValue)
            }
        }
    }

    private fun boundedString(value: Any?): String? {
        return (value as? String)
            ?.takeIf { it.isNotBlank() }
            ?.take(MAX_PERSISTED_STRING_LENGTH)
    }

    private fun jsonObjectToMap(value: JSONObject): Map<String, Any?> {
        return buildMap {
            val keys = value.keys()
            while (keys.hasNext()) {
                val key = keys.next()
                put(key, jsonValue(value.opt(key)))
            }
        }
    }

    private fun jsonValue(value: Any?): Any? {
        return when (value) {
            JSONObject.NULL -> null
            is JSONObject -> jsonObjectToMap(value)
            is JSONArray -> buildList {
                for (index in 0 until value.length()) {
                    add(jsonValue(value.opt(index)))
                }
            }
            else -> value
        }
    }
}
