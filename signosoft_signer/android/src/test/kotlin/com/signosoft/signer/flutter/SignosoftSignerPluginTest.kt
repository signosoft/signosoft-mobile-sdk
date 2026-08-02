package com.signosoft.signer.flutter

import com.signosoft.signer.SignedInfo
import com.signosoft.signer.SignosoftSigner
import java.io.File
import kotlin.test.assertEquals
import kotlin.test.assertNull
import org.junit.jupiter.api.Test

class SignosoftSignerPluginTest {
    private val info = SignedInfo(
        result = "success",
        document = "12345",
        documentToken = "doc-token",
        lang = "cs",
        signaturesSigned = 2,
        signaturesTotal = 2,
        lastSignerFirstName = "Jan",
        lastSignerLastName = "Novák",
        lastSignerEmail = "jan@example.com",
        downloadUrl = null,
        signedPdfFile = File("/tmp/signed.pdf"),
    )

    /** Dart's `parseSignerResult` reads exactly these keys. */
    @Test
    fun `the signed payload carries the keys Dart reads`() {
        assertEquals(
            mapOf(
                "status" to "signed",
                "result" to "success",
                "document" to "12345",
                "documentToken" to "doc-token",
                "lang" to "cs",
                "signaturesSigned" to 2,
                "signaturesTotal" to 2,
                "lastSignerFirstName" to "Jan",
                "lastSignerLastName" to "Novák",
                "lastSignerEmail" to "jan@example.com",
                "downloadUrl" to null,
                "signedPdfPath" to "/tmp/signed.pdf",
            ),
            payloadFor("signed", info),
        )
    }

    @Test
    fun `a missing local pdf arrives as null, not as an empty path`() {
        assertNull(payloadFor("rejected", info.copy(signedPdfFile = null))["signedPdfPath"])
    }

    @Test
    fun `a missing or nonsensical timeout falls back to the default`() {
        assertEquals(12_000L, loadTimeoutOf(12_000))
        assertEquals(SignosoftSigner.DEFAULT_LOAD_TIMEOUT_MILLIS, loadTimeoutOf(null))
        assertEquals(SignosoftSigner.DEFAULT_LOAD_TIMEOUT_MILLIS, loadTimeoutOf(0))
        assertEquals(SignosoftSigner.DEFAULT_LOAD_TIMEOUT_MILLIS, loadTimeoutOf(-1))
    }
}
