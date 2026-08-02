package com.signosoft.signer

import android.os.Bundle
import java.io.File
import java.net.URI

/**
 * Payload delivered with `signed` / `rejected`. Mirrors the query params the web
 * app would otherwise put on its redirect URL.
 */
data class SignedInfo(
    /** Server-side result word: `success` or `rejected`. */
    val result: String,
    /** Numeric document id, as a string. */
    val document: String,
    /**
     * Canonical document identity. Hand this to your own backend so it can fetch
     * the signed PDF with `downloadDoc`. It is not a download link.
     */
    val documentToken: String,
    /** Language the ceremony ran in. */
    val lang: String,
    /** Signatures this signer completed. */
    val signaturesSigned: Int,
    /** Signatures assigned to this signer in total. */
    val signaturesTotal: Int,
    val lastSignerFirstName: String,
    val lastSignerLastName: String,
    val lastSignerEmail: String,
    /**
     * Remote URL for the signed PDF. Present when the backend provides one — it
     * does not yet, so this is null today. See the integration guide.
     */
    val downloadUrl: String? = null,
    /**
     * Signed PDF written into the host app's cache directory. Distinct from
     * [downloadUrl]: a local file, not a remote link. Null on `rejected`, and
     * null on `signed` when the document could not be fetched or exceeded the
     * bridge size ceiling.
     */
    val signedPdfFile: File? = null,
) {
    internal fun toBundle(): Bundle = Bundle().apply {
        putString(KEY_RESULT, result)
        putString(KEY_DOCUMENT, document)
        putString(KEY_DOCUMENT_TOKEN, documentToken)
        putString(KEY_LANG, lang)
        putInt(KEY_SIGNATURES_SIGNED, signaturesSigned)
        putInt(KEY_SIGNATURES_TOTAL, signaturesTotal)
        putString(KEY_FIRST_NAME, lastSignerFirstName)
        putString(KEY_LAST_NAME, lastSignerLastName)
        putString(KEY_EMAIL, lastSignerEmail)
        putString(KEY_DOWNLOAD_URL, downloadUrl)
        putString(KEY_PDF_PATH, signedPdfFile?.path)
    }

    internal companion object {
        private const val KEY_RESULT = "result"
        private const val KEY_DOCUMENT = "document"
        private const val KEY_DOCUMENT_TOKEN = "documentToken"
        private const val KEY_LANG = "lang"
        private const val KEY_SIGNATURES_SIGNED = "signaturesSigned"
        private const val KEY_SIGNATURES_TOTAL = "signaturesTotal"
        private const val KEY_FIRST_NAME = "lastSignerFirstName"
        private const val KEY_LAST_NAME = "lastSignerLastName"
        private const val KEY_EMAIL = "lastSignerEmail"
        private const val KEY_DOWNLOAD_URL = "downloadUrl"
        private const val KEY_PDF_PATH = "signedPdfPath"

        /**
         * Builds the payload from a `signed` / `rejected` bridge message.
         *
         * Every field is optional on the wire and defaulted here: a completed
         * signature must never be lost to a missing or mistyped field.
         */
        fun fromBridge(data: Map<String, Any?>?, pdfStore: SignedPdfStore): SignedInfo {
            val data = data.orEmpty()
            return SignedInfo(
                result = string(data["result"]),
                document = string(data["document"]),
                documentToken = string(data["documentToken"]),
                lang = string(data["lang"]),
                signaturesSigned = int(data["signaturesSigned"]),
                signaturesTotal = int(data["signaturesTotal"]),
                lastSignerFirstName = string(data["lastSignerFirstName"]),
                lastSignerLastName = string(data["lastSignerLastName"]),
                lastSignerEmail = string(data["lastSignerEmail"]),
                downloadUrl = url(data["downloadUrl"]),
                signedPdfFile = pdfStore.write(
                    base64 = data["pdfBase64"] as? String,
                    fileName = data["pdfFileName"] as? String,
                ),
            )
        }

        fun fromBundle(bundle: Bundle): SignedInfo = SignedInfo(
            result = bundle.getString(KEY_RESULT).orEmpty(),
            document = bundle.getString(KEY_DOCUMENT).orEmpty(),
            documentToken = bundle.getString(KEY_DOCUMENT_TOKEN).orEmpty(),
            lang = bundle.getString(KEY_LANG).orEmpty(),
            signaturesSigned = bundle.getInt(KEY_SIGNATURES_SIGNED),
            signaturesTotal = bundle.getInt(KEY_SIGNATURES_TOTAL),
            lastSignerFirstName = bundle.getString(KEY_FIRST_NAME).orEmpty(),
            lastSignerLastName = bundle.getString(KEY_LAST_NAME).orEmpty(),
            lastSignerEmail = bundle.getString(KEY_EMAIL).orEmpty(),
            downloadUrl = bundle.getString(KEY_DOWNLOAD_URL),
            signedPdfFile = bundle.getString(KEY_PDF_PATH)?.let(::File),
        )

        private fun string(value: Any?): String = value as? String ?: ""

        private fun int(value: Any?): Int = (value as? Number)?.toInt() ?: 0

        /**
         * A download URL the host cannot open is worse than none, so anything
         * empty or scheme-less becomes null.
         */
        private fun url(value: Any?): String? {
            val string = value as? String
            if (string.isNullOrEmpty()) return null
            val parsed = runCatching { URI(string) }.getOrNull() ?: return null
            return if (parsed.scheme != null) string else null
        }
    }
}
