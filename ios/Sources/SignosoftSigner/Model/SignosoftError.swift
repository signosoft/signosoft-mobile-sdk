import Foundation

/// Machine-readable reason a signing session ended without a signature.
///
/// Raw values are the wire format shared with the Flutter plugin's
/// `SignosoftErrorCode` — keep the two enums in step.
public enum SignosoftErrorCode: String, Sendable, CaseIterable {
    /// No bioid token was supplied, or the host rejected it before opening.
    case invalidToken
    /// `baseURL` could not be turned into a URL the signer can load.
    case invalidBaseUrl
    /// The signing shell could not be reached — wrong host, no network, or App
    /// Transport Security refused the connection.
    case loadFailed
    /// The shell was reached but never reported itself ready in time.
    case loadTimeout
    /// The shell loaded and could not establish a session for this token.
    case sessionFailed
    /// A signing session is already on screen.
    case alreadyOpen
    /// No view controller was available to present from.
    case noPresenter
    /// This platform has no Signosoft signer.
    case unsupportedPlatform
    /// The iOS plugin is not registered in the host app.
    case notRegistered
    /// Anything not covered above.
    case unknown
}

public struct SignosoftError: LocalizedError, Equatable {
    /// Branch on this. [message] is for developers, not for users.
    public let code: SignosoftErrorCode
    public let message: String

    public init(code: SignosoftErrorCode, message: String) {
        self.code = code
        self.message = message
    }

    public var errorDescription: String? { message }
}
