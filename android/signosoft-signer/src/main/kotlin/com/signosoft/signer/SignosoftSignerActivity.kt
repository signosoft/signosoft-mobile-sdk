package com.signosoft.signer

import android.Manifest
import android.content.Intent
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.graphics.Color
import android.graphics.drawable.GradientDrawable
import android.net.Uri
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.ResultReceiver
import android.util.TypedValue
import android.view.Gravity
import android.view.ViewGroup
import android.webkit.PermissionRequest
import android.webkit.RenderProcessGoneDetail
import android.webkit.ValueCallback
import android.webkit.WebChromeClient
import android.webkit.WebResourceError
import android.webkit.WebResourceRequest
import android.webkit.WebResourceResponse
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.FrameLayout
import android.widget.ProgressBar
import android.widget.TextView
import androidx.activity.ComponentActivity
import androidx.activity.OnBackPressedCallback
import androidx.activity.result.contract.ActivityResultContracts
import androidx.core.view.ViewCompat
import androidx.core.view.WindowInsetsCompat

/**
 * Hosts the embedded Angular shell and translates its bridge messages into
 * [SignosoftSignerResult].
 *
 * Public so a host that manages presentation itself can launch it directly;
 * most hosts want [SignosoftSignerContract].
 */
class SignosoftSignerActivity : ComponentActivity() {

    private lateinit var webView: WebView
    private lateinit var spinner: ProgressBar

    private var token = ""
    private lateinit var baseUrl: Uri
    private var loadTimeoutMillis = SignosoftSigner.DEFAULT_LOAD_TIMEOUT_MILLIS
    private var diagnostics: ResultReceiver? = null

    private val pdfStore by lazy { SignedPdfStore(cacheDir) }
    private val main = Handler(Looper.getMainLooper())
    private var timeout: Runnable? = null
    private var didFinish = false

    /** Storage partition for this ceremony; null where WebView cannot make one. */
    private var profileName: String? = null

    private var pendingPermission: PermissionRequest? = null
    private var pendingFileChooser: ValueCallback<Array<Uri>>? = null

    private val permissionLauncher =
        registerForActivityResult(ActivityResultContracts.RequestMultiplePermissions()) { granted ->
            val request = pendingPermission ?: return@registerForActivityResult
            pendingPermission = null
            // A permission the host app never declared comes back denied without
            // any UI, which is the right answer: the SDK cannot declare usage on
            // the host's behalf.
            if (granted.isNotEmpty() && granted.values.all { it }) {
                request.grant(request.resources)
            } else {
                request.deny()
            }
        }

    private val fileChooserLauncher =
        registerForActivityResult(ActivityResultContracts.StartActivityForResult()) { result ->
            val callback = pendingFileChooser ?: return@registerForActivityResult
            pendingFileChooser = null
            callback.onReceiveValue(
                WebChromeClient.FileChooserParams.parseResult(result.resultCode, result.data)
            )
        }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        token = intent.getStringExtra(SignosoftSigner.EXTRA_TOKEN).orEmpty()
        baseUrl = Uri.parse(intent.getStringExtra(SignosoftSigner.EXTRA_BASE_URL).orEmpty())
        loadTimeoutMillis = intent.getLongExtra(
            SignosoftSigner.EXTRA_LOAD_TIMEOUT,
            SignosoftSigner.DEFAULT_LOAD_TIMEOUT_MILLIS,
        )
        diagnostics = intentResultReceiver()

        setContentView(buildContentView())
        onBackPressedDispatcher.addCallback(
            this,
            object : OnBackPressedCallback(true) {
                override fun handleOnBackPressed() = finish(SignosoftSignerResult.Cancelled)
            },
        )

        loadSigner()
    }

    override fun onDestroy() {
        cancelTimeout()
        if (::webView.isInitialized) {
            webView.removeJavascriptInterface(SignosoftBridge.NAME)
            webView.stopLoading()
            // destroy() on a WebView that is still in the view tree is
            // undefined behaviour: WebView logs "destroy() called while
            // WebView is still attached to window" and the renderer process
            // can be torn down under the compositor, which takes the host
            // app's process with it. Detach first, then destroy.
            webView.webChromeClient = null
            (webView.parent as? ViewGroup)?.removeView(webView)
            webView.destroy()
            // After destroy(), never before: a partition still in use cannot be
            // deleted. This is what keeps the ceremony's cookies, storage and
            // cache from outliving it.
            SignerProfile.release(profileName)
        }
        super.onDestroy()
    }

    // MARK: - Views

    private fun buildContentView(): ViewGroup {
        val root = FrameLayout(this).apply { setBackgroundColor(Color.WHITE) }

        webView = WebView(this).apply {
            layoutParams = FrameLayout.LayoutParams(MATCH_PARENT, MATCH_PARENT)
            settings.javaScriptEnabled = true
            settings.domStorageEnabled = true
            settings.mediaPlaybackRequiresUserGesture = false
            // Before any load: the partition has to be in place before the
            // shell writes its first cookie.
            profileName = SignerProfile.isolate(
                this,
                SignerProfile.newName(java.util.UUID.randomUUID().toString()),
            )
            webViewClient = SignerWebViewClient()
            webChromeClient = SignerWebChromeClient()
            addJavascriptInterface(
                SignosoftBridge { payload -> main.post { onBridgeMessage(payload) } },
                SignosoftBridge.NAME,
            )
        }
        // Lets you attach Chrome DevTools to the WebView. Only ever in a
        // debuggable host — a release build must not expose the ceremony.
        if (applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE != 0) {
            WebView.setWebContentsDebuggingEnabled(true)
        }
        root.addView(webView)

        spinner = ProgressBar(this).apply {
            layoutParams = FrameLayout.LayoutParams(WRAP_CONTENT, WRAP_CONTENT, Gravity.CENTER)
        }
        root.addView(spinner)

        root.addView(buildCloseButton())

        // From Android 15 the window is edge to edge whether it asks or not, and
        // the shell would render under the status bar.
        ViewCompat.setOnApplyWindowInsetsListener(root) { view, insets ->
            val bars = insets.getInsets(WindowInsetsCompat.Type.systemBars())
            view.setPadding(bars.left, bars.top, bars.right, bars.bottom)
            insets
        }
        return root
    }

    private fun buildCloseButton(): TextView = TextView(this).apply {
        val size = dp(36)
        layoutParams = FrameLayout.LayoutParams(size, size, Gravity.TOP or Gravity.END).apply {
            topMargin = dp(8)
            marginEnd = dp(12)
        }
        text = "✕"
        gravity = Gravity.CENTER
        setTextColor(Color.BLACK)
        setTextSize(TypedValue.COMPLEX_UNIT_SP, 18f)
        contentDescription = "Close"
        background = GradientDrawable().apply {
            shape = GradientDrawable.OVAL
            setColor(Color.argb(217, 255, 255, 255))
        }
        setOnClickListener { finish(SignosoftSignerResult.Cancelled) }
    }

    private fun dp(value: Int): Int = (value * resources.displayMetrics.density).toInt()

    // MARK: - Loading

    private fun loadSigner() {
        if (token.isEmpty()) {
            finish(
                SignosoftSignerResult.Failed(
                    SignosoftErrorCode.INVALID_TOKEN,
                    "A bioid token is required.",
                )
            )
            return
        }
        if (!SignosoftSigner.isUsableBaseUrl(baseUrl)) {
            finish(
                SignosoftSignerResult.Failed(
                    SignosoftErrorCode.INVALID_BASE_URL,
                    "Invalid base URL: $baseUrl",
                )
            )
            return
        }

        // Angular is served from the root; an empty path would produce
        // "host?bioid=..." instead of "host/?bioid=...".
        val url = baseUrl.buildUpon()
            .path(baseUrl.path?.takeIf { it.isNotEmpty() } ?: "/")
            .clearQuery()
            .appendQueryParameter("bioid", token)
            .build()

        startTimeout()
        webView.loadUrl(url.toString())
    }

    /**
     * Without this a wrong `baseUrl` leaves the patient on a blank screen
     * forever: the page never loads, so no bridge event ever arrives.
     */
    private fun startTimeout() {
        if (loadTimeoutMillis <= 0) return
        val runnable = Runnable {
            finish(
                SignosoftSignerResult.Failed(
                    SignosoftErrorCode.LOAD_TIMEOUT,
                    "The signing page did not become ready within " +
                        "${loadTimeoutMillis / 1000}s. Check that baseUrl points at a " +
                        "reachable Signosoft signing shell.",
                )
            )
        }
        timeout = runnable
        main.postDelayed(runnable, loadTimeoutMillis)
    }

    private fun cancelTimeout() {
        timeout?.let(main::removeCallbacks)
        timeout = null
    }

    // MARK: - Bridge

    private fun onBridgeMessage(payload: String) {
        val message = BridgeMessage.from(payload) ?: return

        diagnostics?.send(
            0,
            Bundle().apply {
                putString(DiagnosticReceiver.KEY_EVENT, message.event)
                putString(DiagnosticReceiver.KEY_DATA, message.diagnosticData?.toJsonString())
            },
        )

        when (message.event) {
            "ready" -> {
                cancelTimeout()
                spinner.visibility = android.view.View.GONE
            }
            "signed" ->
                finishWithInfo(message.data, SignosoftSignerResult::Signed)
            "rejected" ->
                finishWithInfo(message.data, SignosoftSignerResult::Rejected)
            "cancelled" -> finish(SignosoftSignerResult.Cancelled)
            "error" -> finish(
                SignosoftSignerResult.Failed(
                    SignosoftErrorCode.SESSION_FAILED,
                    message.data?.get("message") as? String
                        ?: "The signing session could not be established.",
                )
            )
        }
    }

    /**
     * Every other field of [SignedInfo] may safely default — losing a signer's
     * middle name must not lose a signature. `documentToken` may not: it is the
     * only handle the host has on the document, and a blank one turns a
     * completed ceremony into a backend call for nothing. Better a loud failure
     * than a hollow success. The Swift core does the same.
     */
    private fun finishWithInfo(
        data: Map<String, Any?>?,
        makeResult: (SignedInfo) -> SignosoftSignerResult,
    ) {
        val info = SignedInfo.fromBridge(data, pdfStore)
        if (info.documentToken.isEmpty()) {
            finish(
                SignosoftSignerResult.Failed(
                    SignosoftErrorCode.SESSION_FAILED,
                    "The signing shell reported an outcome with no documentToken, " +
                        "so the document cannot be identified.",
                )
            )
            return
        }
        finish(makeResult(info))
    }

    private fun finish(result: SignosoftSignerResult) {
        if (didFinish) return
        didFinish = true
        cancelTimeout()
        setResult(
            RESULT_OK,
            Intent().putExtra(SignosoftSigner.EXTRA_RESULT, result.toBundle()),
        )
        finish()
    }

    @Suppress("DEPRECATION")
    private fun intentResultReceiver(): ResultReceiver? =
        intent.getParcelableExtra(SignosoftSigner.EXTRA_DIAGNOSTICS)

    // MARK: - Navigation

    private inner class SignerWebViewClient : WebViewClient() {
        override fun onReceivedError(
            view: WebView,
            request: WebResourceRequest,
            error: WebResourceError,
        ) {
            if (!request.isForMainFrame) return
            finish(
                SignosoftSignerResult.Failed(
                    SignosoftErrorCode.LOAD_FAILED,
                    "Could not load the signing page. ${error.description}",
                )
            )
        }

        /**
         * A misconfigured `baseUrl` usually answers — with a 404 or a 502 —
         * rather than refusing the connection. WebView renders that as a page
         * and reports no error, so without this the signer sits on the host's
         * error page until the load timeout expires.
         */
        override fun onReceivedHttpError(
            view: WebView,
            request: WebResourceRequest,
            errorResponse: WebResourceResponse,
        ) {
            if (!request.isForMainFrame || errorResponse.statusCode < 400) return
            finish(
                SignosoftSignerResult.Failed(
                    SignosoftErrorCode.LOAD_FAILED,
                    "The signing shell answered HTTP ${errorResponse.statusCode} at " +
                        "${request.url}. Check that baseUrl points at the root of a " +
                        "deployed shell.",
                )
            )
        }

        /**
         * The WebView's renderer can be killed under memory pressure — most
         * plausibly by a large document. Returning true keeps the host app
         * alive; the page is gone either way, so report rather than leave a
         * white screen.
         */
        override fun onRenderProcessGone(view: WebView, detail: RenderProcessGoneDetail): Boolean {
            finish(
                SignosoftSignerResult.Failed(
                    SignosoftErrorCode.LOAD_FAILED,
                    "The signing page stopped unexpectedly, most likely from memory " +
                        "pressure. The signature was not recorded.",
                )
            )
            return true
        }
    }

    // MARK: - Camera, microphone and file inputs

    private inner class SignerWebChromeClient : WebChromeClient() {
        /**
         * Android has no prompt of its own here: the host app must hold the
         * runtime permission before the web origin can be granted one. Only the
         * shell's own origin is ever considered.
         */
        override fun onPermissionRequest(request: PermissionRequest) {
            if (!isShellOrigin(request.origin)) {
                request.deny()
                return
            }

            val permissions = request.resources.mapNotNull(::androidPermissionFor)
            if (permissions.size != request.resources.size) {
                request.deny()
                return
            }
            if (permissions.all(::isGranted)) {
                request.grant(request.resources)
                return
            }

            pendingPermission = request
            permissionLauncher.launch(permissions.toTypedArray())
        }

        override fun onShowFileChooser(
            webView: WebView,
            filePathCallback: ValueCallback<Array<Uri>>,
            fileChooserParams: FileChooserParams,
        ): Boolean {
            // Only one picker at a time; the abandoned one must be answered or
            // the page waits forever.
            pendingFileChooser?.onReceiveValue(null)
            pendingFileChooser = filePathCallback

            return runCatching {
                fileChooserLauncher.launch(fileChooserParams.createIntent())
                true
            }.getOrElse {
                pendingFileChooser = null
                filePathCallback.onReceiveValue(null)
                false
            }
        }
    }

    private fun isShellOrigin(origin: Uri?): Boolean =
        origin != null &&
            origin.scheme == baseUrl.scheme &&
            origin.host == baseUrl.host &&
            origin.port == baseUrl.port

    private fun androidPermissionFor(resource: String): String? = when (resource) {
        PermissionRequest.RESOURCE_VIDEO_CAPTURE -> Manifest.permission.CAMERA
        PermissionRequest.RESOURCE_AUDIO_CAPTURE -> Manifest.permission.RECORD_AUDIO
        else -> null
    }

    private fun isGranted(permission: String): Boolean =
        checkSelfPermission(permission) == PackageManager.PERMISSION_GRANTED

    private companion object {
        const val MATCH_PARENT = ViewGroup.LayoutParams.MATCH_PARENT
        const val WRAP_CONTENT = ViewGroup.LayoutParams.WRAP_CONTENT
    }
}
