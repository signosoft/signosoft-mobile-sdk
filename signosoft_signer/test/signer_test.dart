import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:signosoft_signer/signosoft_signer.dart';
import 'package:signosoft_signer/src/channel.dart';

final _baseUrl = Uri.parse('https://embed.example.com');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  /// Stands in for `SignosoftSignerPlugin`. Returns null to leave the channel
  /// unhandled, which is what a missing plugin looks like.
  void mockPlugin(Future<Object?> Function(MethodCall call)? handler) {
    messenger.setMockMethodCallHandler(signosoftSignerChannel, handler);
    addTearDown(
      () => messenger.setMockMethodCallHandler(signosoftSignerChannel, null),
    );
  }

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
  });

  test('passes the token, base URL and timeout to the plugin', () async {
    late MethodCall received;
    mockPlugin((call) async {
      received = call;
      return {'status': 'cancelled'};
    });

    await SignosoftSigner.open(
      token: 'bioid-123',
      baseUrl: _baseUrl,
      loadTimeout: const Duration(seconds: 12),
    );

    expect(received.method, 'open');
    expect(received.arguments, {
      'token': 'bioid-123',
      'baseUrl': 'https://embed.example.com',
      'loadTimeoutMs': 12000,
      'diagnostics': false,
    });
  });

  test('resolves a signed reply', () async {
    mockPlugin(
      (call) async => {
        'status': 'signed',
        'documentToken': 'doc-token',
        'signaturesSigned': 2,
        'signaturesTotal': 2,
        'signedPdfPath': '/tmp/signed.pdf',
      },
    );

    final result = await SignosoftSigner.open(
      token: 'bioid-123',
      baseUrl: _baseUrl,
    );

    expect(result, isA<Signed>());
    expect((result as Signed).signedPdfPath, '/tmp/signed.pdf');
  });

  test('maps a plugin error onto its code', () async {
    mockPlugin(
      (call) async => throw PlatformException(
        code: 'signosoft_error',
        message: 'A signing session is already open.',
        details: {'code': 'alreadyOpen'},
      ),
    );

    final result = await SignosoftSigner.open(
      token: 'bioid-123',
      baseUrl: _baseUrl,
    );

    expect(result, isA<Failed>());
    expect((result as Failed).code, SignosoftErrorCode.alreadyOpen);
    expect(result.message, 'A signing session is already open.');
  });

  test(
    'an unregistered plugin fails with notRegistered, it does not throw',
    () async {
      mockPlugin(null);

      final result = await SignosoftSigner.open(
        token: 'bioid-123',
        baseUrl: _baseUrl,
      );

      expect((result as Failed).code, SignosoftErrorCode.notRegistered);
    },
  );

  test('a null reply fails rather than resolving to nothing', () async {
    mockPlugin((call) async => null);

    final result = await SignosoftSigner.open(
      token: 'bioid-123',
      baseUrl: _baseUrl,
    );

    expect((result as Failed).code, SignosoftErrorCode.unknown);
  });

  test('an empty token never reaches the plugin', () async {
    var invoked = false;
    mockPlugin((call) async {
      invoked = true;
      return {'status': 'cancelled'};
    });

    final result = await SignosoftSigner.open(token: '', baseUrl: _baseUrl);

    expect(invoked, isFalse);
    expect((result as Failed).code, SignosoftErrorCode.invalidToken);
  });

  test('a non-iOS platform fails instead of throwing', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    var invoked = false;
    mockPlugin((call) async {
      invoked = true;
      return null;
    });

    final result = await SignosoftSigner.open(
      token: 'bioid-123',
      baseUrl: _baseUrl,
    );

    expect(invoked, isFalse);
    expect((result as Failed).code, SignosoftErrorCode.unsupportedPlatform);
  });

  test('diagnostics are requested and delivered only when asked for', () async {
    final seen = <SignosoftDiagnostic>[];

    mockPlugin((call) async {
      expect(call.arguments['diagnostics'], isTrue);
      // Stand in for the plugin calling back mid-session.
      await messenger.handlePlatformMessage(
        signosoftSignerChannel.name,
        signosoftSignerChannel.codec.encodeMethodCall(
          const MethodCall('diagnostic', {
            'event': 'ready',
            'data': <String, Object?>{},
          }),
        ),
        (_) {},
      );
      return {'status': 'cancelled'};
    });

    await SignosoftSigner.open(
      token: 'bioid-123',
      baseUrl: _baseUrl,
      onDiagnostic: seen.add,
    );

    expect(seen.single.event, 'ready');
  });
}
