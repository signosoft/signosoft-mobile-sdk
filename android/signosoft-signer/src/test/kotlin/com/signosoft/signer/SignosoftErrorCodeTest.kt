package com.signosoft.signer

import kotlin.test.assertEquals
import org.junit.jupiter.api.Test

class SignosoftErrorCodeTest {
    /**
     * The Swift core, this enum and the Dart `SignosoftErrorCode` share one wire
     * format. Nothing but a comment held the three together, and a rename on any
     * side would surface as `unknown` at the far end rather than as a build
     * failure — so pin the list here.
     */
    @Test
    fun `every wire value matches the Dart and Swift enums`() {
        assertEquals(
            listOf(
                "invalidToken",
                "invalidBaseUrl",
                "loadFailed",
                "loadTimeout",
                "sessionFailed",
                "alreadyOpen",
                "noPresenter",
                "unsupportedPlatform",
                "notRegistered",
                "unknown",
            ),
            SignosoftErrorCode.entries.map { it.wire },
        )
    }

    @Test
    fun `an unrecognised or missing value reads as unknown`() {
        assertEquals(SignosoftErrorCode.ALREADY_OPEN, SignosoftErrorCode.fromWire("alreadyOpen"))
        assertEquals(SignosoftErrorCode.UNKNOWN, SignosoftErrorCode.fromWire("invented-later"))
        assertEquals(SignosoftErrorCode.UNKNOWN, SignosoftErrorCode.fromWire(null))
    }
}
