package com.signosoft.signer

import android.webkit.JavascriptInterface

/**
 * The object `HostBridgeService` posts to on Android.
 *
 * WebView calls this on a JavaScript worker thread, never the main thread —
 * [onMessage] is responsible for getting back there.
 */
internal class SignosoftBridge(private val onMessage: (String) -> Unit) {

    @JavascriptInterface
    fun postMessage(payload: String) {
        onMessage(payload)
    }

    companion object {
        /** Must match the name `HostBridgeService` looks for on `window`. */
        const val NAME = "SignosoftAndroid"
    }
}
