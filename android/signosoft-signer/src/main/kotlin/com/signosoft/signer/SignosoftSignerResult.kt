package com.signosoft.signer

import android.os.Bundle

/**
 * How a signing session ended. Delivered exactly once per session.
 *
 * ```kotlin
 * when (result) {
 *     is SignosoftSignerResult.Signed -> result.info.documentToken
 *     is SignosoftSignerResult.Rejected -> …
 *     SignosoftSignerResult.Cancelled -> …
 *     is SignosoftSignerResult.Failed -> result.code
 * }
 * ```
 */
sealed interface SignosoftSignerResult {
    /** Every signature assigned to this signer was completed. */
    data class Signed(val info: SignedInfo) : SignosoftSignerResult

    /** The signer rejected the document. Terminal and server-side. */
    data class Rejected(val info: SignedInfo) : SignosoftSignerResult

    /** The signer closed the ceremony. Nothing changed server-side. */
    data object Cancelled : SignosoftSignerResult

    /**
     * The ceremony could not run to a conclusion. Branch on [code]; [message] is
     * for developers, not for users.
     */
    data class Failed(
        val code: SignosoftErrorCode,
        val message: String,
    ) : SignosoftSignerResult
}

private const val KEY_STATUS = "status"
private const val KEY_CODE = "code"
private const val KEY_MESSAGE = "message"

internal fun SignosoftSignerResult.toBundle(): Bundle = when (this) {
    is SignosoftSignerResult.Signed -> info.toBundle().apply { putString(KEY_STATUS, "signed") }
    is SignosoftSignerResult.Rejected -> info.toBundle().apply { putString(KEY_STATUS, "rejected") }
    SignosoftSignerResult.Cancelled -> Bundle().apply { putString(KEY_STATUS, "cancelled") }
    is SignosoftSignerResult.Failed -> Bundle().apply {
        putString(KEY_STATUS, "failed")
        putString(KEY_CODE, code.wire)
        putString(KEY_MESSAGE, message)
    }
}

/**
 * A bundle that is missing or unrecognised reads as [SignosoftSignerResult.Cancelled]:
 * the activity was torn down without reporting, which is exactly what closing
 * the ceremony looks like, and nothing changed server-side.
 */
internal fun signerResultFromBundle(bundle: Bundle?): SignosoftSignerResult {
    if (bundle == null) return SignosoftSignerResult.Cancelled
    return when (bundle.getString(KEY_STATUS)) {
        "signed" -> SignosoftSignerResult.Signed(SignedInfo.fromBundle(bundle))
        "rejected" -> SignosoftSignerResult.Rejected(SignedInfo.fromBundle(bundle))
        "failed" -> SignosoftSignerResult.Failed(
            SignosoftErrorCode.fromWire(bundle.getString(KEY_CODE)),
            bundle.getString(KEY_MESSAGE) ?: "The signing session failed.",
        )
        else -> SignosoftSignerResult.Cancelled
    }
}
