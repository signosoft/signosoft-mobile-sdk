/// Machine-readable reason a signing session ended without a signature.
///
/// Branch on this rather than on the message — messages are written for humans
/// and their wording changes.
enum SignosoftErrorCode {
  /// No bioid token was supplied, or the host rejected it before opening.
  invalidToken,

  /// `baseUrl` could not be turned into a URL the signer can load.
  invalidBaseUrl,

  /// The signing shell could not be reached — wrong host, no network, or App
  /// Transport Security refused the connection.
  loadFailed,

  /// The shell was reached but never reported itself ready in time.
  loadTimeout,

  /// The shell loaded and could not establish a session for this token: the
  /// link is expired, already used, or unknown to the server.
  sessionFailed,

  /// A signing session is already on screen.
  alreadyOpen,

  /// No view controller was available to present from.
  noPresenter,

  /// This platform has no Signosoft signer. iOS only in this phase.
  unsupportedPlatform,

  /// The iOS plugin is not registered in the host app.
  notRegistered,

  /// Anything not covered above.
  unknown;

  /// Maps the value the native side puts on the wire. Unrecognised and missing
  /// values become [unknown], so a newer native side never breaks an older app.
  static SignosoftErrorCode fromWire(Object? value) {
    for (final code in SignosoftErrorCode.values) {
      if (code.name == value) return code;
    }
    return unknown;
  }
}
