package com.signosoft.signer.flutter

import android.app.Activity
import android.content.Intent
import android.net.Uri
import com.signosoft.signer.SignedInfo
import com.signosoft.signer.SignosoftErrorCode
import com.signosoft.signer.SignosoftSigner
import com.signosoft.signer.SignosoftSignerRequest
import com.signosoft.signer.SignosoftSignerResult
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry.ActivityResultListener

/** Bridges the Dart `SignosoftSigner` API onto [SignosoftSigner]. */
class SignosoftSignerPlugin :
    FlutterPlugin,
    MethodChannel.MethodCallHandler,
    ActivityAware,
    ActivityResultListener {

    private lateinit var channel: MethodChannel
    private var binding: ActivityPluginBinding? = null
    private var pending: MethodChannel.Result? = null

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(flutterPluginBinding.binaryMessenger, CHANNEL_NAME)
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        this.binding = binding
        binding.addActivityResultListener(this)
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) =
        onAttachedToActivity(binding)

    override fun onDetachedFromActivityForConfigChanges() = onDetachedFromActivity()

    override fun onDetachedFromActivity() {
        binding?.removeActivityResultListener(this)
        binding = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method != "open") {
            result.notImplemented()
            return
        }

        val token = call.argument<String>("token")
        if (token.isNullOrEmpty()) {
            result.fail(SignosoftErrorCode.INVALID_TOKEN, "A bioid token is required.")
            return
        }
        val baseUrl = call.argument<String>("baseUrl")?.let(Uri::parse)
        if (baseUrl == null || !SignosoftSigner.isUsableBaseUrl(baseUrl)) {
            result.fail(SignosoftErrorCode.INVALID_BASE_URL, "A valid baseUrl is required.")
            return
        }
        val activity = binding?.activity
        if (activity == null) {
            result.fail(SignosoftErrorCode.NO_PRESENTER, "No activity available to open the signer.")
            return
        }
        if (pending != null) {
            result.fail(SignosoftErrorCode.ALREADY_OPEN, "A signing session is already open.")
            return
        }

        pending = result
        val request = SignosoftSignerRequest(
            token = token,
            baseUrl = baseUrl,
            loadTimeoutMillis = loadTimeoutOf(call.argument<Number>("loadTimeoutMs")),
            // Diagnostics cost a channel round trip per bridge event, so they
            // are only forwarded when Dart asked for them.
            onDiagnostic = if (call.argument<Boolean>("diagnostics") == true) {
                { event, data -> channel.invokeMethod("diagnostic", mapOf("event" to event, "data" to data)) }
            } else {
                null
            },
        )
        activity.startActivityForResult(
            SignosoftSigner.createIntent(activity, request),
            REQUEST_CODE,
        )
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != REQUEST_CODE) return false
        val result = pending ?: return true
        pending = null

        when (val outcome = SignosoftSigner.parseResult(resultCode, data)) {
            is SignosoftSignerResult.Signed -> result.success(payloadFor("signed", outcome.info))
            is SignosoftSignerResult.Rejected -> result.success(payloadFor("rejected", outcome.info))
            SignosoftSignerResult.Cancelled -> result.success(mapOf("status" to "cancelled"))
            is SignosoftSignerResult.Failed -> result.fail(outcome.code, outcome.message)
        }
        return true
    }

    /**
     * Dart branches on `details["code"]`; the message is only ever shown to a
     * developer.
     */
    private fun MethodChannel.Result.fail(code: SignosoftErrorCode, message: String) =
        error("signosoft_error", message, mapOf("code" to code.wire))

    private companion object {
        const val CHANNEL_NAME = "com.signosoft.signer"
        const val REQUEST_CODE = 0x5165
    }
}

/** A missing or nonsensical timeout falls back to the core's default. */
internal fun loadTimeoutOf(value: Number?): Long {
    val milliseconds = value?.toLong() ?: 0
    return if (milliseconds > 0) milliseconds else SignosoftSigner.DEFAULT_LOAD_TIMEOUT_MILLIS
}

/** The reply Dart's `parseSignerResult` reads. Keys are shared with iOS. */
internal fun payloadFor(status: String, info: SignedInfo): Map<String, Any?> = mapOf(
    "status" to status,
    "result" to info.result,
    "document" to info.document,
    "documentToken" to info.documentToken,
    "lang" to info.lang,
    "signaturesSigned" to info.signaturesSigned,
    "signaturesTotal" to info.signaturesTotal,
    "lastSignerFirstName" to info.lastSignerFirstName,
    "lastSignerLastName" to info.lastSignerLastName,
    "lastSignerEmail" to info.lastSignerEmail,
    "downloadUrl" to info.downloadUrl,
    "signedPdfPath" to info.signedPdfFile?.path,
)
