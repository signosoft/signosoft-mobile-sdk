import 'package:flutter/foundation.dart';

import 'channel.dart';
import 'models/diagnostic.dart';
import 'models/error_code.dart';
import 'models/sign_result.dart';

/// Entry point of the Signosoft Mobile SDK.
abstract final class SignosoftSigner {
  static const SignerChannel _channel = SignerChannel();

  /// Opens the Signosoft signature ceremony full screen and resolves once the
  /// signer is done.
  ///
  /// [token] is the `bioid` your backend obtained from `createDocLink`. One
  /// `bioid` authorises one signature: a document with several signature fields
  /// needs one token, and one call to this method, per field.
  ///
  /// [baseUrl] is the origin serving the Signosoft embedded signing shell. It
  /// must be an `https://` origin with a host. Plain `http://` is accepted only
  /// for `localhost`, `*.localhost`, `127.0.0.1`, `::1` and `10.0.2.2` while
  /// developing; anything else resolves to
  /// [SignosoftErrorCode.invalidBaseUrl] immediately, before the signer appears.
  /// A public `http://` origin is rejected outright, and could not complete a
  /// signature anyway: it is not a secure context, so WebCrypto does not exist
  /// there.
  ///
  /// [loadTimeout] bounds how long the shell may take to become interactive
  /// before the session gives up with [SignosoftErrorCode.loadTimeout].
  ///
  /// [onDiagnostic] receives raw bridge messages; it is for debugging an
  /// integration, not for product logic. A callback that throws cannot affect
  /// the session.
  ///
  /// Never throws. Every failure resolves to [Failed] with a
  /// [SignosoftErrorCode] you can branch on, including anything unanticipated,
  /// which arrives as [SignosoftErrorCode.unknown].
  ///
  /// An outcome the shell reports with no `documentToken` resolves to
  /// [Failed] with [SignosoftErrorCode.sessionFailed] rather than [Signed] —
  /// the token is the only handle you have on the document.
  static Future<SignosoftSignResult> open({
    required String token,
    required Uri baseUrl,
    Duration loadTimeout = const Duration(seconds: 45),
    void Function(SignosoftDiagnostic diagnostic)? onDiagnostic,
  }) {
    if (defaultTargetPlatform != TargetPlatform.iOS) {
      return Future.value(
        const Failed(
          SignosoftErrorCode.unsupportedPlatform,
          'The Signosoft signer is available on iOS only in this phase.',
        ),
      );
    }
    if (token.isEmpty) {
      return Future.value(
        const Failed(
          SignosoftErrorCode.invalidToken,
          'A bioid token is required.',
        ),
      );
    }

    return _channel.open(
      token: token,
      baseUrl: baseUrl,
      loadTimeout: loadTimeout,
      onDiagnostic: onDiagnostic,
    );
  }
}
