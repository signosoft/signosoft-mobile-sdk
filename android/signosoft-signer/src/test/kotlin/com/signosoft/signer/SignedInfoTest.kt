package com.signosoft.signer

import java.io.File
import kotlin.test.assertEquals
import kotlin.test.assertNull
import org.junit.jupiter.api.Test

class SignedInfoTest {
    /**
     * Writing PDFs is out of scope here — a ceiling of zero refuses every
     * document, so these tests never touch the file system.
     */
    private val noPdfStore = SignedPdfStore(File("."), maximumBytes = 0)

    @Test
    fun `reads every field`() {
        val info = SignedInfo.fromBridge(
            mapOf(
                "result" to "success",
                "document" to "12345",
                "documentToken" to "doc-token",
                "lang" to "cs",
                "signaturesSigned" to 2,
                "signaturesTotal" to 2,
                "lastSignerFirstName" to "Jan",
                "lastSignerLastName" to "Novák",
                "lastSignerEmail" to "jan@example.com",
            ),
            noPdfStore,
        )

        assertEquals("success", info.result)
        assertEquals("12345", info.document)
        assertEquals("doc-token", info.documentToken)
        assertEquals("cs", info.lang)
        assertEquals(2, info.signaturesSigned)
        assertEquals(2, info.signaturesTotal)
        assertEquals("Jan", info.lastSignerFirstName)
        assertEquals("Novák", info.lastSignerLastName)
        assertEquals("jan@example.com", info.lastSignerEmail)
    }

    @Test
    fun `defaults missing and mistyped fields`() {
        val info = SignedInfo.fromBridge(
            mapOf("documentToken" to 99, "signaturesSigned" to "two"),
            noPdfStore,
        )

        assertEquals("", info.documentToken)
        assertEquals(0, info.signaturesSigned)
        assertEquals("", info.lastSignerEmail)
    }

    @Test
    fun `a doubled int from the wire is coerced, not dropped`() {
        val info = SignedInfo.fromBridge(mapOf("signaturesTotal" to 3.0), noPdfStore)

        assertEquals(3, info.signaturesTotal)
    }

    @Test
    fun `handles a null payload`() {
        val info = SignedInfo.fromBridge(null, noPdfStore)

        assertEquals("", info.result)
        assertNull(info.downloadUrl)
        assertNull(info.signedPdfFile)
    }

    @Test
    fun `downloadUrl is null unless it is usable`() {
        fun url(value: Any?): String? =
            SignedInfo.fromBridge(mapOf("downloadUrl" to value), noPdfStore).downloadUrl

        assertNull(url(null))
        assertNull(url(""))
        assertNull(url("/relative/path.pdf"))
        assertNull(url(1234))
        assertEquals("https://example.com/a.pdf", url("https://example.com/a.pdf"))
    }
}
