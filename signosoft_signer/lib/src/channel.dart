import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'models/diagnostic.dart';
import 'models/error_code.dart';
import 'models/sign_result.dart';

/// Method channel shared with `SignosoftSignerPlugin` on iOS and Android.
const MethodChannel signosoftSignerChannel = MethodChannel(
  'com.signosoft.signer',
);

/// Invokes the native signer and translates its reply.
///
/// Kept apart from the public facade so the wire format can be tested without a
/// running platform.
class SignerChannel {
  const SignerChannel([this._channel = signosoftSignerChannel]);

  final MethodChannel _channel;

  Future<SignosoftSignResult> open({
    required String token,
    required Uri baseUrl,
    required Duration loadTimeout,
    void Function(SignosoftDiagnostic diagnostic)? onDiagnostic,
  }) async {
    if (onDiagnostic != null) {
      _channel.setMethodCallHandler((call) async {
        if (call.method == 'diagnostic') {
          // Diagnostics are a debugging aid and must never affect the session:
          // a host callback that throws would otherwise surface as an unhandled
          // async error attributed to the SDK, inside the handler the ceremony's
          // own result travels through.
          try {
            onDiagnostic(parseDiagnostic(call.arguments));
          } catch (_) {}
        }
      });
    }

    try {
      final reply = await _channel.invokeMapMethod<String, Object?>('open', {
        'token': token,
        'baseUrl': baseUrl.toString(),
        'loadTimeoutMs': loadTimeout.inMilliseconds,
        'diagnostics': onDiagnostic != null,
      });
      if (reply == null) {
        return const Failed(
          SignosoftErrorCode.unknown,
          'The signer returned no result.',
        );
      }
      return parseSignerResult(reply);
    } on PlatformException catch (error) {
      return Failed(errorCodeOf(error), error.message ?? 'The signer failed.');
    } on MissingPluginException {
      return const Failed(
        SignosoftErrorCode.notRegistered,
        'The Signosoft signer plugin is not registered in this app. '
        'Rebuild the native app after adding the dependency.',
      );
    } catch (error) {
      // Last resort, and additive on purpose: the branches above carry specific
      // SignosoftErrorCodes that a generic catch would flatten to `unknown`.
      // `open()` is documented never to throw, so a codec error or a reply that
      // cannot be decoded has to come back as a result, not as an exception in
      // the host's `await`.
      return Failed(SignosoftErrorCode.unknown, 'The signer failed. $error');
    } finally {
      if (onDiagnostic != null) {
        _channel.setMethodCallHandler(null);
      }
    }
  }
}

/// Turns the native reply into a result. Tolerates missing and mistyped fields:
/// a completed signature must never be lost to a parsing detail.
@visibleForTesting
SignosoftSignResult parseSignerResult(Map<String, Object?> data) {
  switch (data['status']) {
    case 'signed':
      return Signed(
        result: _string(data['result']),
        document: _string(data['document']),
        documentToken: _string(data['documentToken']),
        lang: _string(data['lang']),
        signaturesSigned: _int(data['signaturesSigned']),
        signaturesTotal: _int(data['signaturesTotal']),
        lastSignerFirstName: _string(data['lastSignerFirstName']),
        lastSignerLastName: _string(data['lastSignerLastName']),
        lastSignerEmail: _string(data['lastSignerEmail']),
        downloadUrl: _uri(data['downloadUrl']),
        signedPdfPath: _nullableString(data['signedPdfPath']),
      );
    case 'rejected':
      return Rejected(
        result: _string(data['result']),
        document: _string(data['document']),
        documentToken: _string(data['documentToken']),
        lang: _string(data['lang']),
        signaturesSigned: _int(data['signaturesSigned']),
        signaturesTotal: _int(data['signaturesTotal']),
        lastSignerFirstName: _string(data['lastSignerFirstName']),
        lastSignerLastName: _string(data['lastSignerLastName']),
        lastSignerEmail: _string(data['lastSignerEmail']),
      );
    case 'cancelled':
      return const Cancelled();
    default:
      return Failed(
        SignosoftErrorCode.unknown,
        'Unexpected signer status: ${data['status']}',
      );
  }
}

/// Reads the machine-readable code the plugin attaches to every error.
@visibleForTesting
SignosoftErrorCode errorCodeOf(PlatformException error) {
  final details = error.details;
  return details is Map
      ? SignosoftErrorCode.fromWire(details['code'])
      : SignosoftErrorCode.unknown;
}

@visibleForTesting
SignosoftDiagnostic parseDiagnostic(Object? arguments) {
  final payload = arguments is Map ? arguments : const <Object?, Object?>{};
  final data = payload['data'];
  return SignosoftDiagnostic(
    event: _string(payload['event']),
    data: data is Map
        ? data.map((key, value) => MapEntry(key.toString(), value))
        : null,
  );
}

String _string(Object? value) => value is String ? value : '';

String? _nullableString(Object? value) =>
    value is String && value.isNotEmpty ? value : null;

int _int(Object? value) => value is num ? value.toInt() : 0;

/// A download URL the host cannot actually open is worse than none, so anything
/// empty, unparseable or scheme-less becomes null.
Uri? _uri(Object? value) {
  if (value is! String || value.isEmpty) return null;
  final parsed = Uri.tryParse(value);
  return parsed != null && parsed.hasScheme ? parsed : null;
}
