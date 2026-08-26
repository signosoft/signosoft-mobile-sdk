package com.signosoft.signer

import android.app.Activity
import android.net.Uri
import android.view.ViewGroup
import android.webkit.WebView
import androidx.test.core.app.ApplicationProvider
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config

/**
 * The activity is the only part of this core with a lifecycle, and the part a
 * pure unit test cannot reach. Robolectric runs it on the JVM.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class SignosoftSignerActivityTest {

    private fun request(
        token: String = "a-bioid",
        baseUrl: String = "https://example.test/mobilesdk/",
    ) = SignosoftSignerRequest(token = token, baseUrl = Uri.parse(baseUrl))

    private fun intentFor(request: SignosoftSignerRequest) =
        SignosoftSigner.createIntent(ApplicationProvider.getApplicationContext(), request)

    private fun resultOf(activity: Activity): SignosoftSignerResult {
        val shadow = shadowOf(activity)
        return SignosoftSigner.parseResult(shadow.resultCode, shadow.resultIntent)
    }

    private fun webViewIn(activity: Activity): WebView {
        val root = activity.findViewById<ViewGroup>(android.R.id.content)
        fun find(group: ViewGroup): WebView? {
            for (i in 0 until group.childCount) {
                when (val child = group.getChildAt(i)) {
                    is WebView -> return child
                    is ViewGroup -> find(child)?.let { return it }
                }
            }
            return null
        }
        return requireNotNull(find(root)) { "the ceremony has no WebView" }
    }

    @Test
    fun `the WebView is detached from the view tree before it is destroyed`() {
        // Regression: destroy() on a WebView that is still attached is undefined
        // behaviour — WebView logs "destroy() called while WebView is still
        // attached to window" and the renderer can go down under the compositor.
        val controller = Robolectric.buildActivity(
            SignosoftSignerActivity::class.java,
            intentFor(request()),
        ).setup()

        val webView = webViewIn(controller.get())
        assertTrue("precondition: the WebView starts attached", webView.parent != null)

        controller.destroy()

        assertNull("the WebView must be detached before destroy()", webView.parent)
    }

    @Test
    fun `the system back button reports Cancelled`() {
        val controller = Robolectric.buildActivity(
            SignosoftSignerActivity::class.java,
            intentFor(request()),
        ).setup()

        controller.get().onBackPressedDispatcher.onBackPressed()

        assertEquals(SignosoftSignerResult.Cancelled, resultOf(controller.get()))
        assertTrue(controller.get().isFinishing)
    }

    @Test
    fun `an unusable baseUrl fails before anything is loaded`() {
        val controller = Robolectric.buildActivity(
            SignosoftSignerActivity::class.java,
            intentFor(request(baseUrl = "notaurl")),
        ).setup()

        val result = resultOf(controller.get())
        assertTrue("expected Failed, got $result", result is SignosoftSignerResult.Failed)
        assertEquals(
            SignosoftErrorCode.INVALID_BASE_URL,
            (result as SignosoftSignerResult.Failed).code,
        )
        assertTrue(controller.get().isFinishing)
    }

    @Test
    fun `an empty token fails without opening the shell`() {
        val controller = Robolectric.buildActivity(
            SignosoftSignerActivity::class.java,
            intentFor(request(token = "")),
        ).setup()

        val result = resultOf(controller.get())
        assertTrue("expected Failed, got $result", result is SignosoftSignerResult.Failed)
        assertEquals(
            SignosoftErrorCode.INVALID_TOKEN,
            (result as SignosoftSignerResult.Failed).code,
        )
    }

    @Test
    fun `no error message ever carries the bioid`() {
        // The token is a bearer credential: anyone holding it can sign the
        // document. It must not reach a message a host might log.
        val secret = "super-secret-bioid"
        val controller = Robolectric.buildActivity(
            SignosoftSignerActivity::class.java,
            intentFor(request(token = secret, baseUrl = "notaurl")),
        ).setup()

        val result = resultOf(controller.get()) as SignosoftSignerResult.Failed
        assertTrue(
            "the message leaked the token: ${result.message}",
            !result.message.contains(secret),
        )
    }
}
