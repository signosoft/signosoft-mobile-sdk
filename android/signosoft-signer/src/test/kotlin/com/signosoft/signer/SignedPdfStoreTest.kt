package com.signosoft.signer

import java.io.File
import kotlin.io.encoding.Base64
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.io.TempDir

class SignedPdfStoreTest {
    @TempDir
    lateinit var directory: File

    @Test
    fun `writes decoded bytes`() {
        val payload = "%PDF-1.7 signed".toByteArray()
        val store = SignedPdfStore(directory)

        val file = assertNotNull(store.write(Base64.encode(payload), "report.pdf"))

        assertEquals("report.pdf", file.name)
        assertEquals(payload.toList(), file.readBytes().toList())
    }

    @Test
    fun `returns null rather than throwing on bad input`() {
        val store = SignedPdfStore(directory)

        assertNull(store.write(null, "a.pdf"))
        assertNull(store.write("", "a.pdf"))
        assertNull(store.write("not base64 at all!!", "a.pdf"))
        assertNull(store.write(Base64.encode(ByteArray(0)), "a.pdf"))
    }

    @Test
    fun `refuses documents over the ceiling`() {
        val store = SignedPdfStore(directory, maximumBytes = 8)
        val tooBig = Base64.encode(ByteArray(64) { 0x41 })

        assertNull(store.write(tooBig, "big.pdf"))
    }

    @Test
    fun `the file name cannot escape the directory`() {
        val store = SignedPdfStore(directory)

        val file = assertNotNull(store.write(Base64.encode("x".toByteArray()), "../../evil.pdf"))

        assertEquals(directory.canonicalFile, file.canonicalFile.parentFile)
        assertEquals("evil.pdf", file.name)
    }

    @Test
    fun `safeName falls back for pathological names`() {
        assertEquals("document.pdf", SignedPdfStore.safeName(null))
        assertEquals("document.pdf", SignedPdfStore.safeName(""))
        assertEquals("document.pdf", SignedPdfStore.safeName("/"))
        assertEquals("document.pdf", SignedPdfStore.safeName(".."))
        assertEquals("c.pdf", SignedPdfStore.safeName("a/b/../c.pdf"))
        assertEquals("plain.pdf", SignedPdfStore.safeName("plain.pdf"))
    }
}
