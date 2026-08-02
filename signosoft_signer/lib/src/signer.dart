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
  /// [token] is the `bioid` your backend obtained from `createDocLink`.
  /// [baseUrl] is the origin serving the Signosoft embedded signing shell.
  /// [loadTimeout] bounds how long the shell may take to become interactive
  /// before the session gives up with [SignosoftErrorCode.loadTimeout].
  /// [onDiagnostic] receives raw bridge messages; it is for debugging an
  /// integration, not for product logic.
  ///
  /// Never throws. Every failure resolves to [Failed] with a
  /// [SignosoftErrorCode] you can branch on.
  static Future<SignosoftSignResult> open({
    required String token,
    required Uri baseUrl,
    Duration loadTimeout = const Duration(seconds: 45),
    void Function(SignosoftDiagnostic diagnostic)? onDiagnostic,
  }) {
    if (defaultTargetPlatform != TargetPlatform.iOS &&
        defaultTargetPlatform != TargetPlatform.android) {
      return Future.value(
        const Failed(
          SignosoftErrorCode.unsupportedPlatform,
          'The Signosoft signer is available on iOS and Android only.',
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
