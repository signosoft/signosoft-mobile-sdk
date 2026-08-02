package com.signosoft.signer

import org.json.JSONArray
import org.json.JSONObject

/**
 * One message from the embedded shell.
 *
 * Deliberately free of WebView types so the wire format can be tested off
 * device; the activity hands it the raw `@JavascriptInterface` argument.
 */
internal class BridgeMessage private constructor(
    val event: String,
    val data: Map<String, Any?>?,
) {
    /**
     * The payload with the signed PDF bytes elided, cheap enough to log.
     * Diagnostics must never carry megabytes of base64 back across the bridge.
     */
    val diagnosticData: Map<String, Any?>?
        get() {
            val data = data ?: return null
            val base64 = data["pdfBase64"] as? String ?: return data
            return data - "pdfBase64" + ("pdfBase64Length" to base64.length)
        }

    companion object {
        /**
         * Android delivers the payload as a JSON string — `@JavascriptInterface`
         * carries strings, not objects, which is why `HostBridgeService`
         * stringifies before posting.
         */
        fun from(body: String?): BridgeMessage? {
            if (body.isNullOrEmpty()) return null
            val payload = runCatching { JSONObject(body) }.getOrNull() ?: return null
            val event = payload.opt("event") as? String ?: return null
            return BridgeMessage(event, payload.optJSONObject("data")?.toMap())
        }
    }
}

/** `JSONObject.NULL` is a sentinel object, not null, and would leak into payloads. */
internal fun JSONObject.toMap(): Map<String, Any?> =
    keys().asSequence().associateWith { unwrapJson(get(it)) }

internal fun JSONArray.toList(): List<Any?> = (0 until length()).map { unwrapJson(get(it)) }

private fun unwrapJson(value: Any?): Any? = when (value) {
    JSONObject.NULL -> null
    is JSONObject -> value.toMap()
    is JSONArray -> value.toList()
    else -> value
}

/** Diagnostics cross the activity boundary as JSON, so they need the way back. */
internal fun Map<String, Any?>.toJsonString(): String = JSONObject(this).toString()
