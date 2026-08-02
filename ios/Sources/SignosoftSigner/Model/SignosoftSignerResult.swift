import Foundation

/// How a signing session ended. Delivered exactly once per session.
public enum SignosoftSignerResult {
    /// Every signature assigned to this signer was completed.
    case signed(SignedInfo)
    /// The signer rejected the document. Terminal and server-side.
    case rejected(SignedInfo)
    /// The signer closed the ceremony. Nothing changed server-side.
    case cancelled
    /// The ceremony could not run to a conclusion. Always a `SignosoftError`
    /// when it originates inside the SDK, so `as? SignosoftError` yields a
    /// `SignosoftErrorCode`.
    case error(Error)
}
