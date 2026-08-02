import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:signosoft_signer/signosoft_signer.dart';

import 'config.dart';
import 'medicly_logo.dart';

const _patientName = 'Anna Nováková';
const _patientDob = '14 Mar 1978';
const _patientMrn = 'MRN 884-201-7';

class ReportScreen extends StatefulWidget {
  const ReportScreen({super.key});

  @override
  State<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends State<ReportScreen> {
  SignosoftSignResult? _result;
  bool _busy = false;

  String? get _signedPdfPath =>
      _result is Signed ? (_result as Signed).signedPdfPath : null;

  Future<void> _sign() async {
    if (_busy || !kIsConfigured) return;
    setState(() => _busy = true);

    final result = await SignosoftSigner.open(
      token: kBioId,
      baseUrl: Uri.parse(kEmbeddedBaseUrl),
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
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        centerTitle: false,
        titleSpacing: 24,
        toolbarHeight: 104,
        title: const MediclyLogo(),
        actions: const [
          Padding(padding: EdgeInsets.only(right: 24), child: _ClinicianChip()),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(
            height: 1,
            color: Colors.black.withValues(alpha: 0.06),
          ),
        ),
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 900;
          final viewer = _DocumentViewer(signedPdfPath: _signedPdfPath);
          final panel = _SidePanel(
            showSignButton: wide,
            result: _result,
            busy: _busy,
            onSign: _sign,
          );

          if (wide) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(width: 400, child: panel),
                Expanded(child: viewer),
              ],
            );
          }

          return Column(
            children: [
              panel,
              Expanded(child: viewer),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: _SignButton(
                    result: _result,
                    busy: _busy,
                    onSign: _sign,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _SidePanel extends StatelessWidget {
  const _SidePanel({
    required this.showSignButton,
    required this.result,
    required this.busy,
    required this.onSign,
  });

  final bool showSignButton;
  final SignosoftSignResult? result;
  final bool busy;
  final VoidCallback onSign;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 30,
                    backgroundColor: mediclyTeal.withValues(alpha: 0.12),
                    child: const Text(
                      'AN',
                      style: TextStyle(
                        color: mediclyDeep,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 20),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _patientName,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '$_patientDob · $_patientMrn',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Medical Report',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: _StatusChip(result: result),
                  ),
                  if (result case final Failed failed) ...[
                    const SizedBox(height: 10),
                    Text(
                      failed.message,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: const Color(0xFFB3261E),
                      ),
                    ),
                  ],
                  if (result case final Signed signed) ...[
                    const SizedBox(height: 10),
                    Text(
                      '${signed.signaturesSigned}/${signed.signaturesTotal} signatures '
                      '· ${signed.lastSignerFirstName} ${signed.lastSignerLastName}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                  const SizedBox(height: 20),
                  const _MetaRow(
                    icon: Icons.description_outlined,
                    label: 'mock-medical-report.pdf',
                  ),
                  const _MetaRow(
                    icon: Icons.edit_outlined,
                    label: '2 signature fields — typed + handwritten',
                  ),
                  const _MetaRow(
                    icon: Icons.verified_user_outlined,
                    label: 'Signing provider: Signosoft',
                  ),
                ],
              ),
            ),
          ),
          if (showSignButton) ...[
            const SizedBox(height: 20),
            _SignButton(result: result, busy: busy, onSign: onSign),
          ],
        ],
      ),
    );
  }
}

class _SignButton extends StatelessWidget {
  const _SignButton({
    required this.result,
    required this.busy,
    required this.onSign,
  });

  final SignosoftSignResult? result;
  final bool busy;
  final VoidCallback onSign;

  @override
  Widget build(BuildContext context) {
    final done = result is Signed;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: mediclyTeal,
            padding: const EdgeInsets.symmetric(vertical: 26),
          ),
          icon: busy
              ? const SizedBox(
                  width: 34,
                  height: 34,
                  child: CircularProgressIndicator(
                    strokeWidth: 3,
                    color: Colors.white,
                  ),
                )
              : Icon(done ? Icons.check : Icons.draw_outlined, size: 34),
          label: Text(done ? 'Signed' : 'Sign document'),
          onPressed: busy || done || !kIsConfigured ? null : onSign,
        ),
        if (!kIsConfigured) ...[
          const SizedBox(height: 12),
          Text(
            'Run with --dart-define=BIOID=<token> '
            '--dart-define=BASE_URL=<origin>. See README.md.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ],
    );
  }
}

class _DocumentViewer extends StatelessWidget {
  const _DocumentViewer({required this.signedPdfPath});

  /// Once the ceremony returns a signed copy, show that instead of the mock.
  final String? signedPdfPath;

  @override
  Widget build(BuildContext context) {
    final params = PdfViewerParams(
      margin: 12,
      backgroundColor: const Color(0xFFE6ECEE),
      // Default is fit-to-width; open a bit closer so the form is legible.
      onViewerReady: (_, controller) => controller.setZoom(
        Offset.zero,
        controller.viewSize.width / controller.documentSize.width * 1.3,
        duration: Duration.zero,
      ),
      loadingBannerBuilder: (_, _, _) =>
          const Center(child: CircularProgressIndicator()),
    );

    final path = signedPdfPath;
    return Container(
      color: const Color(0xFFE6ECEE),
      child: path == null
          ? PdfViewer.asset(kReportAsset, params: params)
          : PdfViewer.file(path, key: ValueKey(path), params: params),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.result});

  final SignosoftSignResult? result;

  @override
  Widget build(BuildContext context) {
    final (label, background, foreground) = switch (result) {
      Signed() => ('Signed', const Color(0xFFDDF3E4), const Color(0xFF1B5E36)),
      Rejected() => (
        'Rejected',
        const Color(0xFFFBE2E1),
        const Color(0xFFB3261E),
      ),
      Cancelled() => (
        'Signing cancelled',
        const Color(0xFFECEFF1),
        const Color(0xFF445055),
      ),
      Failed() => (
        'Signing failed',
        const Color(0xFFFBE2E1),
        const Color(0xFFB3261E),
      ),
      null => (
        'Awaiting signature',
        const Color(0xFFFFF2D9),
        const Color(0xFF8A5A00),
      ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: foreground,
        ),
      ),
    );
  }
}

class _MetaRow extends StatelessWidget {
  const _MetaRow({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 32, color: mediclyDeep.withValues(alpha: 0.7)),
          const SizedBox(width: 14),
          Expanded(
            child: Text(label, style: Theme.of(context).textTheme.bodySmall),
          ),
        ],
      ),
    );
  }
}

class _ClinicianChip extends StatelessWidget {
  const _ClinicianChip();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          'Dr. Petr Havel',
          style: TextStyle(fontSize: 14, color: mediclyDeep),
        ),
        const SizedBox(width: 14),
        CircleAvatar(
          radius: 26,
          backgroundColor: mediclyDeep.withValues(alpha: 0.1),
          child: const Icon(Icons.person_outline, size: 30, color: mediclyDeep),
        ),
      ],
    );
  }
}
