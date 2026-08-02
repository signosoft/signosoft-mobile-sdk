package com.signosoft.signer

/**
 * Machine-readable reason a signing session ended without a signature.
 *
 * [wire] is the format shared with the Swift core's `SignosoftErrorCode` and the
 * Flutter plugin's `SignosoftErrorCode` — keep the three enums in step.
 */
enum class SignosoftErrorCode(val wire: String) {
    /** No bioid token was supplied, or the host rejected it before opening. */
    INVALID_TOKEN("invalidToken"),

    /** `baseUrl` could not be turned into a URL the signer can load. */
    INVALID_BASE_URL("invalidBaseUrl"),

    /**
     * The signing shell could not be reached — wrong host, no network, or the
     * network security configuration refused a cleartext connection.
     */
    LOAD_FAILED("loadFailed"),

    /** The shell was reached but never reported itself ready in time. */
    LOAD_TIMEOUT("loadTimeout"),

    /** The shell loaded and could not establish a session for this token. */
    SESSION_FAILED("sessionFailed"),

    /** A signing session is already on screen. */
    ALREADY_OPEN("alreadyOpen"),

    /** No activity was available to launch the signer from. */
    NO_PRESENTER("noPresenter"),

    /** This platform has no Signosoft signer. */
    UNSUPPORTED_PLATFORM("unsupportedPlatform"),

    /** The Android plugin is not registered in the host app. */
    NOT_REGISTERED("notRegistered"),

    /** Anything not covered above. */
    UNKNOWN("unknown");

    companion object {
        /**
         * Reads a value off the wire. Unrecognised and missing values become
         * [UNKNOWN], so a newer peer never breaks an older one.
         */
        fun fromWire(value: String?): SignosoftErrorCode =
            entries.firstOrNull { it.wire == value } ?: UNKNOWN
    }
}
