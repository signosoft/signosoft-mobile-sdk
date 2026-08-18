import 'package:flutter/foundation.dart';
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
    // The result appears at the bottom of the page, which on a phone is behind
    // the keyboard the token was just typed on.
    FocusScope.of(context).unfocus();

    setState(() {
      _busy = true;
      _result = null;
    });

    final result = await SignosoftSigner.open(
      token: _token.text.trim(),
      baseUrl: Uri.parse(_baseUrl.text.trim()),
      // Diagnostics are for debugging an integration, never for product logic —
      // and debug builds only: `debugPrint` survives into a release build, and
      // the payload carries the documentToken and the signer's name and email.
      onDiagnostic: kDebugMode
          ? (d) => debugPrint('signosoft: ${d.event} ${d.data ?? ''}')
          : null,
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
            // Rebuilds on every keystroke so the button below can follow the
            // field: open() with an empty token only ever returns
            // Failed(invalidToken), which reads as a broken SDK.
            ValueListenableBuilder(
              valueListenable: _token,
              builder: (context, token, _) {
                final hasToken = token.text.trim().isNotEmpty;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: _token,
                      autocorrect: false,
                      decoration: const InputDecoration(
                        labelText: 'bioid',
                        helperText:
                            'Your backend mints this with createDocLink.',
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
                        helperText:
                            'Origin serving the Signosoft signing shell.',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: _busy || !hasToken ? null : _sign,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Text(_busy ? 'Signing…' : 'Sign document'),
                      ),
                    ),
                    if (!hasToken) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Paste a bioid above to enable signing.',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ],
                );
              },
            ),
            const SizedBox(height: 24),
            OutcomeView(result: _result),
          ],
        ),
      ),
    );
  }
}

/// Every outcome `open()` can produce, and what an integrator does with it.
///
/// Public so a widget test can render each outcome without a platform channel.
class OutcomeView extends StatelessWidget {
  const OutcomeView({required this.result, super.key});

  final SignosoftSignResult? result;

  @override
  Widget build(BuildContext context) {
    final (title, detail, colour) = switch (result) {
      null => (
        'No result yet',
        'Enter a bioid and tap Sign.',
        Colors.grey.shade700,
      ),
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
          Colors.green.shade900,
        ),
      Rejected(:final documentToken) => (
        'Rejected',
        'The signer refused. This is terminal server-side — the same bioid '
            'cannot be signed afterwards.\n\ndocumentToken: $documentToken',
        Colors.deepOrange.shade900,
      ),
      Cancelled() => (
        'Cancelled',
        'The signer closed the ceremony. Nothing changed; you may open the '
            'same bioid again.',
        Colors.blueGrey.shade700,
      ),
      Failed(:final code, :final message) => (
        'Failed',
        'Branch on the code, not the message.\n\ncode: ${code.name}\n$message',
        Colors.red.shade800,
      ),
    };

    return Card(
      // An elevated Material draws through a physical-shape layer, which
      // ignores the alpha of its colour: passing a translucent tint here paints
      // a solid slab and leaves the title unreadable on it. Blend the tint down
      // to an opaque colour instead of asking the compositor to.
      color: Color.alphaBlend(
        colour.withValues(alpha: 0.08),
        Theme.of(context).colorScheme.surface,
      ),
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
