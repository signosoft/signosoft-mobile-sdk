import 'package:flutter/material.dart';
import 'package:signosoft_signer/signosoft_signer.dart';

void main() => runApp(const ExampleApp());

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Signosoft signer example',
    theme: ThemeData(colorSchemeSeed: const Color(0xFF3B4CCA)),
    home: const SignPage(),
  );
}

class SignPage extends StatefulWidget {
  const SignPage({super.key});

  @override
  State<SignPage> createState() => _SignPageState();
}

class _SignPageState extends State<SignPage> {
  /// A bioid your backend obtained from `createDocLink`.
  final _token = TextEditingController();

  /// Origin serving the Signosoft embedded signing shell. Prefilled with the
  /// hosted one; change it for a tenant-specific origin or a local build.
  final _baseUrl = TextEditingController(
    text: 'https://www.signosoft.com/mobilesdk/',
  );

  SignosoftSignResult? _result;
  bool _busy = false;

  @override
  void dispose() {
    _token.dispose();
    _baseUrl.dispose();
    super.dispose();
  }

  Future<void> _sign() async {
    setState(() {
      _busy = true;
      _result = null;
    });

    final result = await SignosoftSigner.open(
      token: _token.text.trim(),
      baseUrl: Uri.parse(_baseUrl.text.trim()),
      // Diagnostics are for debugging an integration, never for product logic.
      onDiagnostic: (d) => debugPrint('signosoft: ${d.event} ${d.data ?? ''}'),
    );

    if (!mounted) return;
    setState(() {
      _result = result;
      _busy = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Signosoft signer example')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            TextField(
              controller: _token,
              autocorrect: false,
              decoration: const InputDecoration(
                labelText: 'bioid',
                helperText: 'Your backend mints this with createDocLink.',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _baseUrl,
              autocorrect: false,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                labelText: 'baseUrl',
                hintText: 'https://…',
                helperText: 'Origin serving the Signosoft signing shell.',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _busy ? null : _sign,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(_busy ? 'Signing…' : 'Sign document'),
              ),
            ),
            const SizedBox(height: 24),
            _Outcome(result: _result),
          ],
        ),
      ),
    );
  }
}

/// Every outcome `open()` can produce, and what an integrator does with it.
class _Outcome extends StatelessWidget {
  const _Outcome({required this.result});

  final SignosoftSignResult? result;

  @override
  Widget build(BuildContext context) {
    final (title, detail, colour) = switch (result) {
      null => ('No result yet', 'Enter a bioid and tap Sign.', Colors.grey),
      Signed(
        :final documentToken,
        :final signaturesSigned,
        :final signaturesTotal,
        :final signedPdfPath,
      ) =>
        (
          'Signed',
          'Attach the document to the patient record. Your backend fetches it '
              'with downloadDoc using documentToken.\n\n'
              'documentToken: $documentToken\n'
              'signatures: $signaturesSigned/$signaturesTotal\n'
              'local copy: ${signedPdfPath ?? "not delivered — fetch it server-side"}',
          Colors.green,
        ),
      Rejected(:final documentToken) => (
        'Rejected',
        'The signer refused. This is terminal server-side — the same bioid '
            'cannot be signed afterwards.\n\ndocumentToken: $documentToken',
        Colors.orange,
      ),
      Cancelled() => (
        'Cancelled',
        'The signer closed the ceremony. Nothing changed; you may open the '
            'same bioid again.',
        Colors.blueGrey,
      ),
      Failed(:final code, :final message) => (
        'Failed',
        'Branch on the code, not the message.\n\ncode: ${code.name}\n$message',
        Colors.red,
      ),
    };

    return Card(
      color: colour.withValues(alpha: 0.08),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: colour,
              ),
            ),
            const SizedBox(height: 8),
            SelectableText(detail),
          ],
        ),
      ),
    );
  }
}
