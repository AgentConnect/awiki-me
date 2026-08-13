package ai.awiki.awikime.push

import org.json.JSONObject

/**
 * Gate 2 is intentionally a negative safety seam.  It documents the delivery
 * facts observed by the existing EMAS callbacks and makes it impossible for a
 * later receiver change to treat either callback as an approved cold-process
 * renderer transport without replacing this gate with named-device evidence.
 *
 * No ticket is trusted or rendered here.  In particular, this class must not
 * become a second agent-message parser or a background notification owner.
 */
internal enum class BackgroundUrgentTransportCallback {
    emasMessage,
    emasNotice,
}

internal enum class BackgroundUrgentTransportBlocker {
    messageDoesNotDeliverWhenProcessTerminated,
    noticeIsProviderPresented,
}

internal data class BackgroundUrgentTransportVerdict(
    val callback: BackgroundUrgentTransportCallback,
    val blocker: BackgroundUrgentTransportBlocker,
    val appOwnedRendererMayStart: Boolean = false,
)

internal object BackgroundUrgentTransportGate {
    fun evaluate(callback: BackgroundUrgentTransportCallback): BackgroundUrgentTransportVerdict {
        return when (callback) {
            BackgroundUrgentTransportCallback.emasMessage -> BackgroundUrgentTransportVerdict(
                callback = callback,
                blocker = BackgroundUrgentTransportBlocker.messageDoesNotDeliverWhenProcessTerminated,
            )
            BackgroundUrgentTransportCallback.emasNotice -> BackgroundUrgentTransportVerdict(
                callback = callback,
                blocker = BackgroundUrgentTransportBlocker.noticeIsProviderPresented,
            )
        }
    }
}

/**
 * Parses only the deliberately content-free test marker.  It never parses a
 * message, task name, sender, route, or presentation ticket.  The marker is
 * useful for a future named-device spike, but cannot unlock renderer behavior.
 */
internal object IsolatedTransportProbeMarker {
    private const val markerKey = "awiki_transport_probe"
    private const val markerValue = "v1"
    private const val probeIdKey = "probe_id"
    private val probeIdPattern = Regex("^[A-Za-z0-9_-]{8,64}$")

    fun isPresent(extraMap: Map<String, String>?): Boolean {
        val map = extraMap ?: return false
        val source = if (map.containsKey(markerKey)) {
            map
        } else {
            map["ext"]
                ?.takeIf { it.length <= 1024 }
                ?.let(::parseJsonObject)
                ?: return false
        }
        if (source.keys != setOf(markerKey, probeIdKey)) return false
        return source[markerKey] == markerValue &&
            probeIdPattern.matches(source[probeIdKey].orEmpty())
    }

    private fun parseJsonObject(raw: String): Map<String, String>? {
        return runCatching {
            val objectValue = JSONObject(raw)
            buildMap {
                val keys = objectValue.keys()
                while (keys.hasNext()) {
                    val key = keys.next()
                    val value = objectValue.opt(key) as? String ?: return@runCatching null
                    put(key, value)
                }
            }
        }.getOrNull()
    }
}

/**
 * Native-only, low-cardinality diagnostic.  It intentionally does not retain
 * the probe identifier or provider payload, so a production log cannot become
 * an alternate notification data store.
 */
internal data class BackgroundUrgentTransportDiagnostic(
    val verdict: BackgroundUrgentTransportVerdict,
    val isolatedProbeMarkerPresent: Boolean,
)

internal object BackgroundUrgentTransportDiagnostics {
    fun fromMessageCallback(): BackgroundUrgentTransportDiagnostic {
        return BackgroundUrgentTransportDiagnostic(
            verdict = BackgroundUrgentTransportGate.evaluate(
                BackgroundUrgentTransportCallback.emasMessage,
            ),
            isolatedProbeMarkerPresent = false,
        )
    }

    fun fromNoticeCallback(extraMap: Map<String, String>?): BackgroundUrgentTransportDiagnostic {
        return BackgroundUrgentTransportDiagnostic(
            verdict = BackgroundUrgentTransportGate.evaluate(
                BackgroundUrgentTransportCallback.emasNotice,
            ),
            isolatedProbeMarkerPresent = IsolatedTransportProbeMarker.isPresent(extraMap),
        )
    }
}
