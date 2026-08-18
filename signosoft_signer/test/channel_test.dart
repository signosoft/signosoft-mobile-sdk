import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:signosoft_signer/signosoft_signer.dart';
import 'package:signosoft_signer/src/channel.dart';

const _fullPayload = <String, Object?>{
  'result': 'success',
  'document': '12345',
  'documentToken': 'doc-token',
  'lang': 'cs',
  'signaturesSigned': 2,
  'signaturesTotal': 2,
  'lastSignerFirstName': 'Jan',
  'lastSignerLastName': 'Novák',
  'lastSignerEmail': 'jan@example.com',
};

void main() {
  // The open() group talks to a mock platform channel, which needs a binding.
  TestWidgetsFlutterBinding.ensureInitialized();

  group('parseSignerResult', () {
    test('reads every field of a signed reply', () {
      final result = parseSignerResult({
        ..._fullPayload,
        'status': 'signed',
        'downloadUrl': 'https://example.com/a.pdf',
        'signedPdfPath': '/tmp/a.pdf',
      });

      expect(result, isA<Signed>());
      final signed = result as Signed;
      expect(signed.result, 'success');
      expect(signed.document, '12345');
      expect(signed.documentToken, 'doc-token');
      expect(signed.lang, 'cs');
      expect(signed.signaturesSigned, 2);
      expect(signed.signaturesTotal, 2);
      expect(signed.lastSignerFirstName, 'Jan');
      expect(signed.lastSignerLastName, 'Novák');
      expect(signed.lastSignerEmail, 'jan@example.com');
      expect(signed.downloadUrl, Uri.parse('https://example.com/a.pdf'));
      expect(signed.signedPdfPath, '/tmp/a.pdf');
    });

    test('reads a rejected reply', () {
      final result = parseSignerResult({..._fullPayload, 'status': 'rejected'});

      expect(result, isA<Rejected>());
      expect((result as Rejected).documentToken, 'doc-token');
    });

    test('reads a cancelled reply', () {
      expect(parseSignerResult({'status': 'cancelled'}), isA<Cancelled>());
    });

    test('an unknown status fails rather than being mistaken for success', () {
      final result = parseSignerResult({'status': 'something-new'});

      expect(result, isA<Failed>());
      expect((result as Failed).code, SignosoftErrorCode.unknown);
      expect(result.message, contains('something-new'));
    });

    test('missing and mistyped fields default instead of throwing', () {
      final result =
          parseSignerResult({
                'status': 'signed',
                'documentToken': 42,
                'signaturesSigned': 'two',
              })
              as Signed;

      expect(result.documentToken, '');
      expect(result.signaturesSigned, 0);
      expect(result.lastSignerEmail, '');
      expect(result.signedPdfPath, isNull);
    });

    test('a doubled int from the wire is coerced, not dropped', () {
      final result =
          parseSignerResult({'status': 'signed', 'signaturesTotal': 3.0})
              as Signed;

      expect(result.signaturesTotal, 3);
    });

    test('an unusable downloadUrl becomes null', () {
      Uri? urlFrom(Object? value) =>
          (parseSignerResult({'status': 'signed', 'downloadUrl': value})
                  as Signed)
              .downloadUrl;

      expect(urlFrom(null), isNull);
      expect(urlFrom(''), isNull);
      expect(urlFrom('/relative/path.pdf'), isNull);
      expect(urlFrom(1234), isNull);
      expect(urlFrom('https://example.com/a.pdf'), isNotNull);
    });

    test('an empty signedPdfPath becomes null', () {
      final result =
          parseSignerResult({'status': 'signed', 'signedPdfPath': ''})
              as Signed;

      expect(result.signedPdfPath, isNull);
    });
  });

  group('errorCodeOf', () {
    test('reads the code the plugin attaches', () {
      final code = errorCodeOf(
        PlatformException(
          code: 'signosoft_error',
          details: {'code': 'alreadyOpen'},
        ),
      );

      expect(code, SignosoftErrorCode.alreadyOpen);
    });

    test('falls back to unknown for absent or unrecognised codes', () {
      expect(
        errorCodeOf(PlatformException(code: 'signosoft_error')),
        SignosoftErrorCode.unknown,
      );
      expect(
        errorCodeOf(
          PlatformException(code: 'x', details: {'code': 'invented-later'}),
        ),
        SignosoftErrorCode.unknown,
      );
    });
  });

  group('SignerChannel.open', () {
    const channel = MethodChannel('com.signosoft.signer.test');
    late TestDefaultBinaryMessenger messenger;

    setUp(() {
      messenger = TestDefaultBinaryMessengerBinding
          .instance
          .defaultBinaryMessenger;
    });

    tearDown(() {
      messenger.setMockMethodCallHandler(channel, null);
      messenger.setMockMessageHandler(channel.name, null);
    });

    Future<SignosoftSignResult> open({
      void Function(SignosoftDiagnostic diagnostic)? onDiagnostic,
    }) => const SignerChannel(channel).open(
      token: 'a' * 64,
      baseUrl: Uri.parse('https://www.signosoft.com/mobilesdk/'),
      loadTimeout: const Duration(seconds: 45),
      onDiagnostic: onDiagnostic,
    );

    /// Delivers a `diagnostic` call the way the plugin does — inbound, on the
    /// same channel the result travels back on.
    Future<void> sendDiagnostic(Map<String, Object?> arguments) =>
        messenger.handlePlatformMessage(
          channel.name,
          channel.codec.encodeMethodCall(
            MethodCall('diagnostic', arguments),
          ),
          null,
        );

    test('open returns Failed rather than throwing when the reply cannot be '
        'decoded', () async {
      // A reply the codec accepts but the wire format does not: not a map, so
      // invokeMapMethod's cast blows up somewhere no `on PlatformException`
      // branch catches it.
      messenger.setMockMethodCallHandler(channel, (call) async => 'not a map');

      final result = await open();

      expect(result, isA<Failed>(), reason: 'open() is documented never to throw');
      expect((result as Failed).code, SignosoftErrorCode.unknown);
    });

    test('a diagnostic callback that throws does not break the session', () async {
      final seen = <String>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        await sendDiagnostic({'event': 'ready'});
        await sendDiagnostic({'event': 'signed', 'data': {'documentToken': 'tok'}});
        return {..._fullPayload, 'status': 'signed'};
      });

      final result = await open(
        onDiagnostic: (diagnostic) {
          seen.add(diagnostic.event);
          throw StateError('the host callback blew up');
        },
      );

      expect(seen, ['ready', 'signed'], reason: 'a throw must not stop later events');
      expect(result, isA<Signed>(), reason: 'the ceremony still reports its result');
      expect((result as Signed).documentToken, 'doc-token');
    });
  });

  group('parseDiagnostic', () {
    test('reads event and data', () {
      final diagnostic = parseDiagnostic({
        'event': 'signed',
        'data': {'documentToken': 'tok', 'pdfBase64Length': 12},
      });

      expect(diagnostic.event, 'signed');
      expect(diagnostic.data?['documentToken'], 'tok');
      expect(diagnostic.data?['pdfBase64Length'], 12);
    });

    test('tolerates a missing payload', () {
      expect(parseDiagnostic({'event': 'ready'}).data, isNull);
      expect(parseDiagnostic(null).event, '');
    });
  });
}
