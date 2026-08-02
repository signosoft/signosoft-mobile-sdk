package com.signosoft.signer

import kotlin.test.assertEquals
import kotlin.test.assertNull
import org.junit.jupiter.api.Test

class BridgeMessageTest {
    @Test
    fun `parses a json body`() {
        val message = BridgeMessage.from("""{"event":"ready"}""")

        assertEquals("ready", message?.event)
        assertNull(message?.data)
    }

    @Test
    fun `parses the payload alongside the event`() {
        val message = BridgeMessage.from("""{"event":"error","data":{"message":"nope"}}""")

        assertEquals("error", message?.event)
        assertEquals("nope", message?.data?.get("message"))
    }

    @Test
    fun `rejects a body without an event`() {
        assertNull(BridgeMessage.from("""{"data":{"x":1}}"""))
        assertNull(BridgeMessage.from("""{"event":42}"""))
    }

    @Test
    fun `rejects a junk body`() {
        assertNull(BridgeMessage.from(null))
        assertNull(BridgeMessage.from(""))
        assertNull(BridgeMessage.from("not json"))
        assertNull(BridgeMessage.from("42"))
    }

    @Test
    fun `diagnostic data replaces the pdf bytes with their length`() {
        val message = BridgeMessage.from(
            """{"event":"signed","data":{"documentToken":"tok","pdfBase64":"AAAA"}}"""
        )

        val diagnostic = message?.diagnosticData
        assertNull(diagnostic?.get("pdfBase64"))
        assertEquals(4, diagnostic?.get("pdfBase64Length"))
        assertEquals("tok", diagnostic?.get("documentToken"))
    }

    @Test
    fun `a json null in the payload arrives as null, not as a sentinel`() {
        val message = BridgeMessage.from("""{"event":"signed","data":{"downloadUrl":null}}""")

        assertNull(message?.data?.get("downloadUrl"))
    }
}
