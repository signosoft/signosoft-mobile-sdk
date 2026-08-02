import 'package:flutter/foundation.dart';

import 'error_code.dart';

/// Outcome of a signing session. Exhaustively switchable:
///
/// ```dart
/// switch (await SignosoftSigner.open(token: bioid, baseUrl: shell)) {
///   case Signed(:final documentToken, :final signedPdfPath): ...
///   case Rejected(:final documentToken): ...
///   case Cancelled(): ...
///   case Failed(:final code, :final message): ...
/// }
/// ```
@immutable
sealed class SignosoftSignResult {
  const SignosoftSignResult();
}

/// A terminal outcome the server recorded — signed or rejected. Both carry the
/// same document and signer metadata.
@immutable
sealed class SignosoftOutcome extends SignosoftSignResult {
  const SignosoftOutcome({
    required this.result,
    required this.document,
    required this.documentToken,
    required this.lang,
    required this.signaturesSigned,
    required this.signaturesTotal,
    required this.lastSignerFirstName,
    required this.lastSignerLastName,
    required this.lastSignerEmail,
  });

  /// Server-side result word: `success` or `rejected`.
  final String result;

  /// Numeric document id, as a string.
  final String document;

  /// Canonical document identity. Hand this to your own backend so it can fetch
  /// the signed PDF with `downloadDoc`. It is not a download link — do not put
  /// it in a URL and do not show it to a user.
  final String documentToken;

  /// Language the ceremony ran in.
  final String lang;

  /// Signatures this signer completed.
  final int signaturesSigned;

  /// Signatures assigned to this signer in total.
  final int signaturesTotal;

  final String lastSignerFirstName;
  final String lastSignerLastName;
  final String lastSignerEmail;
}

/// Every signature assigned to this signer was completed.
final class Signed extends SignosoftOutcome {
  const Signed({
    required super.result,
    required super.document,
    required super.documentToken,
    required super.lang,
    required super.signaturesSigned,
    required super.signaturesTotal,
    required super.lastSignerFirstName,
    required super.lastSignerLastName,
    required super.lastSignerEmail,
    this.downloadUrl,
    this.signedPdfPath,
  });

  /// Remote URL for the signed PDF. The backend does not mint one yet, so this
  /// is always null today — see the integration guide.
  final Uri? downloadUrl;

  /// Signed PDF written into the app's temporary directory.
  ///
  /// Null when the shell could not fetch the document or it exceeded the bridge
  /// size ceiling. The signature is still valid either way — fetch the PDF with
  /// [documentToken] from your backend.
  final String? signedPdfPath;

  @override
  String toString() =>
      'Signed($documentToken, $signaturesSigned/$signaturesTotal, '
      'pdf: ${signedPdfPath != null})';
}

/// The signer rejected the document. Terminal, and server-side: the link cannot
/// be signed afterwards. Never carries a PDF.
final class Rejected extends SignosoftOutcome {
  const Rejected({
    required super.result,
    required super.document,
    required super.documentToken,
    required super.lang,
    required super.signaturesSigned,
    required super.signaturesTotal,
    required super.lastSignerFirstName,
    required super.lastSignerLastName,
    required super.lastSignerEmail,
  });

  @override
  String toString() => 'Rejected($documentToken)';
}

/// The signer closed the ceremony without finishing. Nothing changed
/// server-side and the token can be opened again.
final class Cancelled extends SignosoftSignResult {
  const Cancelled();

  @override
  String toString() => 'Cancelled()';
}

/// The ceremony could not run to a conclusion. Branch on [code]; show [message]
/// only to developers.
final class Failed extends SignosoftSignResult {
  const Failed(this.code, this.message);

  final SignosoftErrorCode code;
  final String message;

  @override
  String toString() => 'Failed(${code.name}: $message)';
}
