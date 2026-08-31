package com.signosoft.signer

import android.webkit.WebView
import androidx.webkit.Profile
import androidx.webkit.ProfileStore
import androidx.webkit.WebViewCompat
import androidx.webkit.WebViewFeature

/**
 * Keeps a ceremony's cookies, local storage and HTTP cache out of the host
 * app's own WebView storage, and deletes them when the ceremony ends.
 *
 * The Swift core does this with one line — `WKWebViewConfiguration`'s
 * `websiteDataStore = .nonPersistent()`. Android has no such switch. Its
 * `CookieManager`, `WebStorage` and `WebView.clearCache` are **process wide**:
 * an SDK that called them to tidy up after itself would delete the host app's
 * data too, which is worse than leaving its own behind.
 *
 * What Android does offer is [ProfileStore] — named storage partitions, each
 * with its own cookies, local storage and cache. A ceremony gets one of its
 * own and it is deleted afterwards, which is the same guarantee iOS makes.
 *
 * The API needs WebView 114 or newer, which is not a `minSdk` question — the
 * WebView provider updates independently of the OS. Where it is missing,
 * [isolate] reports so rather than reaching for the process-wide calls, and
 * the ceremony runs in the host's default partition exactly as before. That
 * case is documented in the integration guide's privacy section.
 */
internal object SignerProfile {

    /** Marks the profiles this SDK owns, so a sweep never touches the host's. */
    private const val PREFIX = "signosoft-ceremony-"

    /** Whether this device's WebView can partition storage at all. */
    val isSupported: Boolean
        get() = WebViewFeature.isFeatureSupported(WebViewFeature.MULTI_PROFILE)

    /**
     * Puts [webView] in a storage partition of its own and returns its name,
     * or null if this WebView cannot partition storage.
     *
     * Any partition left behind by an earlier ceremony is deleted first: a
     * process killed mid-ceremony never gets to run [release], and without the
     * sweep those would accumulate forever.
     */
    fun isolate(webView: WebView, name: String): String? {
        if (!isSupported) return null
        return runCatching {
            sweep(keep = name)
            ProfileStore.getInstance().getOrCreateProfile(name)
            WebViewCompat.setProfile(webView, name)
            name
        }.getOrNull()
    }

    /**
     * Deletes the ceremony's partition. Call after the WebView is destroyed —
     * a profile still in use cannot be deleted, and that is reported by
     * throwing.
     *
     * A failure here is not worth surfacing to the host: the signature is
     * already reported by this point, and the next ceremony's sweep collects
     * whatever is left.
     */
    fun release(name: String?) {
        if (name == null || !isSupported) return
        runCatching { ProfileStore.getInstance().deleteProfile(name) }
    }

    /** Deletes every partition this SDK owns except [keep]. */
    private fun sweep(keep: String?) {
        val store = ProfileStore.getInstance()
        store.allProfileNames
            .filter { it.startsWith(PREFIX) && it != keep && it != Profile.DEFAULT_PROFILE_NAME }
            .forEach { runCatching { store.deleteProfile(it) } }
    }

    /** A name no other ceremony will pick. */
    fun newName(seed: String): String = PREFIX + seed
}
