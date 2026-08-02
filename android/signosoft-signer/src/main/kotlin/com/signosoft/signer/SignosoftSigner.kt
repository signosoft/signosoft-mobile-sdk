package com.signosoft.signer

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.ResultReceiver
import androidx.activity.result.contract.ActivityResultContract
import org.json.JSONObject

/**
 * What to open, and how.
 *
 * @param token bioid from `createDocLink`
 * @param baseUrl origin serving the embedded signing shell
 * @param loadTimeoutMillis how long the shell may take to report itself ready
 * @param onDiagnostic optional tap into every bridge message, for debugging only
 */
data class SignosoftSignerRequest(
    val token: String,
    val baseUrl: Uri,
    val loadTimeoutMillis: Long = SignosoftSigner.DEFAULT_LOAD_TIMEOUT_MILLIS,
    val onDiagnostic: ((String, Map<String, Any?>?) -> Unit)? = null,
)

/**
 * Entry point of the Signosoft Mobile SDK for native Android hosts.
 *
 * ```kotlin
 * private val signer = registerForActivityResult(SignosoftSignerContract()) { result -> … }
 * signer.launch(SignosoftSignerRequest(token = bioid, baseUrl = shell))
 * ```
 *
 * Flutter apps should use the `signosoft_signer` plugin instead, which wraps
 * this.
 */
object SignosoftSigner {
    /** How long the shell may take to report itself ready. */
    const val DEFAULT_LOAD_TIMEOUT_MILLIS = 45_000L

    internal const val EXTRA_TOKEN = "com.signosoft.signer.TOKEN"
    internal const val EXTRA_BASE_URL = "com.signosoft.signer.BASE_URL"
    internal const val EXTRA_LOAD_TIMEOUT = "com.signosoft.signer.LOAD_TIMEOUT"
    internal const val EXTRA_DIAGNOSTICS = "com.signosoft.signer.DIAGNOSTICS"
    internal const val EXTRA_RESULT = "com.signosoft.signer.RESULT"

    /**
     * Builds the intent [SignosoftSignerContract] launches. Hosts that manage
     * their own activity results can use it directly with [parseResult].
     */
    fun createIntent(context: Context, request: SignosoftSignerRequest): Intent =
        Intent(context, SignosoftSignerActivity::class.java)
            .putExtra(EXTRA_TOKEN, request.token)
            .putExtra(EXTRA_BASE_URL, request.baseUrl.toString())
            .putExtra(EXTRA_LOAD_TIMEOUT, request.loadTimeoutMillis)
            .putExtra(EXTRA_DIAGNOSTICS, request.onDiagnostic?.let(::DiagnosticReceiver))

    /** Reads the outcome back out of an activity result. */
    fun parseResult(resultCode: Int, intent: Intent?): SignosoftSignerResult {
        if (resultCode != Activity.RESULT_OK) return SignosoftSignerResult.Cancelled
        return signerResultFromBundle(intent?.getBundleExtra(EXTRA_RESULT))
    }

    /** A base URL the WebView cannot load is reported before anything opens. */
    internal fun isUsableBaseUrl(baseUrl: Uri): Boolean =
        !baseUrl.scheme.isNullOrEmpty() && !baseUrl.host.isNullOrEmpty()
}

/**
 * Presents the signing ceremony and reports a typed result.
 *
 * Usable from views (`registerForActivityResult`) and from Compose
 * (`rememberLauncherForActivityResult`) alike.
 */
class SignosoftSignerContract :
    ActivityResultContract<SignosoftSignerRequest, SignosoftSignerResult>() {

    override fun createIntent(context: Context, input: SignosoftSignerRequest): Intent =
        SignosoftSigner.createIntent(context, input)

    override fun parseResult(resultCode: Int, intent: Intent?): SignosoftSignerResult =
        SignosoftSigner.parseResult(resultCode, intent)
}

/**
 * Carries bridge events out of the signing activity while it is still on screen.
 *
 * A `ResultReceiver` rather than a shared object: the activity is a separate
 * component with its own lifecycle, and this is the transport Android provides
 * for exactly that. The payload travels as JSON because a bridge payload is
 * arbitrarily shaped and a [Bundle] is not.
 */
internal class DiagnosticReceiver(
    private val onDiagnostic: (String, Map<String, Any?>?) -> Unit,
) : ResultReceiver(Handler(Looper.getMainLooper())) {

    override fun onReceiveResult(resultCode: Int, resultData: Bundle?) {
        val event = resultData?.getString(KEY_EVENT) ?: return
        val json = resultData.getString(KEY_DATA)
        val data = json?.let { runCatching { JSONObject(it).toMap() }.getOrNull() }
        onDiagnostic(event, data)
    }

    companion object {
        const val KEY_EVENT = "event"
        const val KEY_DATA = "data"
    }
}
