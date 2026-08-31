package com.signosoft.signer

import android.app.Activity
import android.net.Uri
import android.os.Bundle
import android.os.ResultReceiver
import android.util.Base64
import androidx.test.core.app.ApplicationProvider
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import org.robolectric.android.controller.ActivityController
import org.robolectric.annotation.Config
import org.robolectric.shadows.ShadowLooper

/**
 * The bridge is the SDK's whole contract with the signing shell, and until now
 * it was tested only as a parser ([BridgeMessageTest]) — never as it actually
 * behaves inside the activity. This is the Kotlin counterpart of the Swift
 * core's view-controller suite.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class SignosoftSignerActivityBridgeTest {

    private val token = "a-secret-bioid"

    /** Everything the shell sends arrives as a JSON string, never an object. */
    private fun payload(event: String, data: Map<String, Any?>? = null): String =
        JSONObject(mapOf("event" to event, "data" to data?.let(::JSONObject)))
            .toString()

    private fun launch(
        baseUrl: String = "https://example.test/mobilesdk/",
        timeoutMillis: Long = SignosoftSigner.DEFAULT_LOAD_TIMEOUT_MILLIS,
        diagnostics: ((String, String?) -> Unit)? = null,
    ): ActivityController<SignosoftSignerActivity> {
        val request = SignosoftSignerRequest(
            token = token,
            baseUrl = Uri.parse(baseUrl),
            loadTimeoutMillis = timeoutMillis,
        )
        val intent = SignosoftSigner.createIntent(
            ApplicationProvider.getApplicationContext(),
            request,
        )
        if (diagnostics != null) {
            intent.putExtra(
                SignosoftSigner.EXTRA_DIAGNOSTICS,
                object : ResultReceiver(null) {
                    override fun onReceiveResult(resultCode: Int, resultData: Bundle?) {
                        diagnostics(
                            resultData?.getString(DiagnosticReceiver.KEY_EVENT).orEmpty(),
                            resultData?.getString(DiagnosticReceiver.KEY_DATA),
                        )
                    }
                },
            )
        }
        return Robolectric.buildActivity(SignosoftSignerActivity::class.java, intent).setup()
    }

    /** Drives the bridge exactly as the WebView does: a JSON string. */
    private fun ActivityController<SignosoftSignerActivity>.post(payload: String) {
        val bridge = SignosoftBridge { p -> get().runOnUiThread { deliver(p) } }
        bridge.postMessage(payload)
        ShadowLooper.idleMainLooper()
    }

    private fun ActivityController<SignosoftSignerActivity>.deliver(payload: String) {
        val method = SignosoftSignerActivity::class.java
            .getDeclaredMethod("onBridgeMessage", String::class.java)
            .apply { isAccessible = true }
        method.invoke(get(), payload)
    }

    private fun resultOf(activity: Activity): SignosoftSignerResult {
        val shadow = shadowOf(activity)
        return SignosoftSigner.parseResult(shadow.resultCode, shadow.resultIntent)
    }

    // MARK: - Every outcome the shell can report

    @Test
    fun `a signed event becomes Signed and carries the document token`() {
        val c = launch()
        c.post(payload("signed", mapOf("documentToken" to "doc-1", "signaturesSigned" to 1)))

        val result = resultOf(c.get())
        assertTrue("got $result", result is SignosoftSignerResult.Signed)
        assertEquals("doc-1", (result as SignosoftSignerResult.Signed).info.documentToken)
    }

    @Test
    fun `a rejected event becomes Rejected`() {
        val c = launch()
        c.post(payload("rejected", mapOf("documentToken" to "doc-2")))
        assertTrue(resultOf(c.get()) is SignosoftSignerResult.Rejected)
    }

    @Test
    fun `a cancelled event becomes Cancelled`() {
        val c = launch()
        c.post(payload("cancelled"))
        assertEquals(SignosoftSignerResult.Cancelled, resultOf(c.get()))
    }

    @Test
    fun `an error event becomes Failed with the shell's message`() {
        val c = launch()
        c.post(payload("error", mapOf("message" to "The document link is invalid")))

        val result = resultOf(c.get())
        assertTrue("got $result", result is SignosoftSignerResult.Failed)
        result as SignosoftSignerResult.Failed
        assertEquals(SignosoftErrorCode.SESSION_FAILED, result.code)
        assertTrue(result.message.contains("document link is invalid"))
    }

    @Test
    fun `an outcome with no documentToken is a failure, not a signature`() {
        // The token is the only handle the host has on the document. A blank
        // one turns a completed ceremony into a backend call for nothing.
        val c = launch()
        c.post(payload("signed", mapOf("documentToken" to "", "signaturesSigned" to 1)))

        val result = resultOf(c.get())
        assertTrue("expected Failed, got $result", result is SignosoftSignerResult.Failed)
        assertEquals(
            SignosoftErrorCode.SESSION_FAILED,
            (result as SignosoftSignerResult.Failed).code,
        )
    }

    @Test
    fun `ready is not a terminal outcome`() {
        val c = launch()
        c.post(payload("ready"))
        assertEquals(
            "ready must not finish the ceremony",
            Activity.RESULT_CANCELED,
            shadowOf(c.get()).resultCode,
        )
        assertTrue(!c.get().isFinishing)
    }

    @Test
    fun `an unrecognised event is ignored rather than guessed at`() {
        val c = launch()
        c.post(payload("someFutureEvent", mapOf("documentToken" to "doc-3")))
        assertTrue(!c.get().isFinishing)
    }

    @Test
    fun `malformed payloads do not crash the ceremony`() {
        val c = launch()
        c.post("not json at all")
        c.post("{}")
        c.post("""{"event":null}""")
        assertTrue(!c.get().isFinishing)
    }

    // MARK: - Reporting exactly once

    @Test
    fun `only the first terminal event is reported`() {
        val c = launch()
        c.post(payload("signed", mapOf("documentToken" to "first")))
        c.post(payload("cancelled"))
        c.post(payload("signed", mapOf("documentToken" to "second")))

        val result = resultOf(c.get())
        assertEquals("first", (result as SignosoftSignerResult.Signed).info.documentToken)
    }

    @Test
    fun `the back button after a signature does not overwrite it`() {
        val c = launch()
        c.post(payload("signed", mapOf("documentToken" to "doc-4")))
        c.get().onBackPressedDispatcher.onBackPressed()
        assertTrue(resultOf(c.get()) is SignosoftSignerResult.Signed)
    }

    // MARK: - The load watchdog

    @Test
    fun `the shell not becoming ready in time fails with loadTimeout`() {
        val c = launch(timeoutMillis = 45_000)
        ShadowLooper.idleMainLooper(45_000, java.util.concurrent.TimeUnit.MILLISECONDS)

        val result = resultOf(c.get())
        assertTrue("expected Failed, got $result", result is SignosoftSignerResult.Failed)
        assertEquals(
            SignosoftErrorCode.LOAD_TIMEOUT,
            (result as SignosoftSignerResult.Failed).code,
        )
    }

    @Test
    fun `ready cancels the watchdog`() {
        val c = launch(timeoutMillis = 45_000)
        c.post(payload("ready"))
        ShadowLooper.idleMainLooper(60_000, java.util.concurrent.TimeUnit.MILLISECONDS)
        assertTrue("the watchdog fired after ready", !c.get().isFinishing)
    }

    @Test
    fun `a terminal outcome cancels the watchdog`() {
        val c = launch(timeoutMillis = 45_000)
        c.post(payload("cancelled"))
        ShadowLooper.idleMainLooper(60_000, java.util.concurrent.TimeUnit.MILLISECONDS)
        assertEquals(SignosoftSignerResult.Cancelled, resultOf(c.get()))
    }

    // MARK: - Diagnostics must never leak

    @Test
    fun `the signed PDF never reaches the diagnostic tap as bytes`() {
        val pdf = Base64.encodeToString(ByteArray(4096) { 0x41 }, Base64.NO_WRAP)
        val seen = mutableListOf<Pair<String, String?>>()
        val c = launch(diagnostics = { e, d -> seen += e to d })

        c.post(payload("signed", mapOf("documentToken" to "doc-5", "pdfBase64" to pdf)))

        val dump = seen.joinToString { "${it.first} ${it.second}" }
        assertTrue("the diagnostic carried the PDF bytes: $dump", !dump.contains(pdf))
        assertTrue("the diagnostic should report a length instead", dump.contains("pdfBase64Length"))
    }

    @Test
    fun `no diagnostic ever carries the bioid`() {
        val seen = mutableListOf<Pair<String, String?>>()
        val c = launch(diagnostics = { e, d -> seen += e to d })

        c.post(payload("ready"))
        c.post(payload("signed", mapOf("documentToken" to "doc-6")))

        val dump = seen.joinToString { "${it.first} ${it.second}" }
        assertTrue("a diagnostic leaked the token: $dump", !dump.contains(token))
    }

    @Test
    fun `no failure message ever carries the bioid`() {
        val c = launch(baseUrl = "notaurl")
        val result = resultOf(c.get()) as SignosoftSignerResult.Failed
        assertTrue("the message leaked the token: ${result.message}", !result.message.contains(token))
    }

    @Test
    fun `diagnostics are silent when the host did not ask for them`() {
        // No receiver on the intent at all: the activity must not assume one.
        val c = launch()
        c.post(payload("ready"))
        c.post(payload("signed", mapOf("documentToken" to "doc-7")))
        assertTrue(resultOf(c.get()) is SignosoftSignerResult.Signed)
    }

    // MARK: - The intent contract hosts drive themselves

    @Test
    fun `createIntent and parseResult round trip every outcome`() {
        val store = SignedPdfStore(
            java.io.File(System.getProperty("java.io.tmpdir"), "signosoft-test-pdfs"),
        )
        val cases = listOf(
            SignosoftSignerResult.Cancelled,
            SignosoftSignerResult.Failed(SignosoftErrorCode.LOAD_TIMEOUT, "timed out"),
            SignosoftSignerResult.Signed(SignedInfo.fromBridge(mapOf("documentToken" to "d"), store)),
            SignosoftSignerResult.Rejected(SignedInfo.fromBridge(mapOf("documentToken" to "d"), store)),
        )
        for (case in cases) {
            val intent = android.content.Intent()
                .putExtra(SignosoftSigner.EXTRA_RESULT, case.toBundle())
            assertEquals(case, SignosoftSigner.parseResult(Activity.RESULT_OK, intent))
        }
    }

    @Test
    fun `a result-less activity result reads as Cancelled`() {
        // A ceremony torn down without reporting is exactly what closing looks
        // like, and nothing changed server-side.
        assertEquals(
            SignosoftSignerResult.Cancelled,
            SignosoftSigner.parseResult(Activity.RESULT_CANCELED, null),
        )
        assertEquals(
            SignosoftSignerResult.Cancelled,
            SignosoftSigner.parseResult(Activity.RESULT_OK, null),
        )
    }

    @Test
    fun `createIntent carries the request onto the intent`() {
        val request = SignosoftSignerRequest(
            token = "tok",
            baseUrl = Uri.parse("https://shell.test/"),
            loadTimeoutMillis = 1234,
        )
        val intent = SignosoftSigner.createIntent(
            ApplicationProvider.getApplicationContext(),
            request,
        )
        assertEquals("tok", intent.getStringExtra(SignosoftSigner.EXTRA_TOKEN))
        assertEquals("https://shell.test/", intent.getStringExtra(SignosoftSigner.EXTRA_BASE_URL))
        assertEquals(1234, intent.getLongExtra(SignosoftSigner.EXTRA_LOAD_TIMEOUT, -1))
        assertNull(intent.getParcelableExtra(SignosoftSigner.EXTRA_DIAGNOSTICS))
    }
}
