import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:signosoft_signer/signosoft_signer.dart';

import 'config.dart';
import 'medicly_logo.dart';

const _patientName = 'Vojta Vlachovsky';
const _patientDob = '20 Apr 1967';
const _patientMrn = 'MRN 884-201-7';

/// Material's window width classes, which is all the responsiveness this demo
/// needs: below [kCompactWidth] is a phone, at or above [kExpandedWidth] is a
/// tablet in full screen, and in between is a tablet sharing the screen.
const kCompactWidth = 600.0;
const kExpandedWidth = 900.0;

/// The demo is meant to be legible from across a room, so text scaling is
/// pinned rather than left to the reader's setting. A phone cannot fit the
/// tablet's 2x, so the pin steps down with the width class.
double demoTextScale(double width) {
  if (width >= kExpandedWidth) return 2.0;
  if (width >= kCompactWidth) return 1.5;
  return 1.15;
}

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
      // Every bridge event the shell sends, in the Flutter console. The only
      // way to see why a ceremony hangs: no `ready` means the shell never
      // established the session.
      //
      // Debug builds only. `debugPrint` is not stripped from a release build,
      // and the payload carries the documentToken and the signer's name and
      // email straight into the device log.
      onDiagnostic: kDebugMode ? (d) => debugPrint('[signosoft] $d') : null,
    );

    if (!mounted) return;
    setState(() {
      _result = result;
      _busy = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    // A phone's toolbar cannot hold the tablet's logo next to the clinician's
    // full name, so on a compact width the logo shrinks and the chip keeps only
    // the avatar.
    final compact = MediaQuery.sizeOf(context).width < kCompactWidth;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        centerTitle: false,
        titleSpacing: compact ? 16 : 24,
        toolbarHeight: compact ? 72 : 104,
        title: MediclyLogo(size: compact ? 40 : 64),
        actions: [
          Padding(
            padding: EdgeInsets.only(right: compact ? 16 : 24),
            child: _ClinicianChip(showName: !compact),
          ),
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
          final wide = constraints.maxWidth >= kExpandedWidth;
          final viewer = _DocumentViewer(
            signedPdfPath: _signedPdfPath,
            // A phone has no width to spare: fit the page instead of opening
            // closer, or the form is cropped before it is read.
            zoom: compact ? 1.0 : 1.3,
          );
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

          // Stacked: the panel is content rather than a sidebar. It is a scroll
          // view, so in a Column it would happily size itself to its full
          // content and push the viewer and the Sign button off the bottom.
          // Cap it instead: it shrink-wraps when it is short and scrolls inside
          // its own box when it is not, the viewer takes whatever is left, and
          // the Sign button stays pinned where it cannot be scrolled away.
          return Column(
            children: [
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: constraints.maxHeight * 0.45,
                ),
                child: panel,
              ),
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
                      'VV',
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
                  // The second field is minted as `biometric`, which needs an
                  // external signature pad the signing shell cannot reach from
                  // this origin — so it opens and then cannot be completed.
                  // Say so here rather than let a demo viewer discover it by
                  // tapping. See docs/TODO.txt.
                  const _MetaRow(
                    icon: Icons.edit_outlined,
                    label: '2 signature fields — typed, and one pad-only',
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
            'Run with --dart-define=BIOID=<token>. See README.md.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ],
    );
  }
}

class _DocumentViewer extends StatelessWidget {
  const _DocumentViewer({required this.signedPdfPath, this.zoom = 1.3});

  /// Once the ceremony returns a signed copy, show that instead of the mock.
  final String? signedPdfPath;

  /// Multiple of fit-to-width the document opens at.
  final double zoom;

  @override
  Widget build(BuildContext context) {
    final params = PdfViewerParams(
      margin: 12,
      backgroundColor: const Color(0xFFE6ECEE),
      // Default is fit-to-width; open a bit closer so the form is legible.
      onViewerReady: (_, controller) => controller.setZoom(
        Offset.zero,
        controller.viewSize.width / controller.documentSize.width * zoom,
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
  const _ClinicianChip({this.showName = true});

  /// Dropped on a phone, where the name and the logo cannot both fit.
  final bool showName;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showName) ...[
          const Text(
            'Dr. Petr Sevecek',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 14, color: mediclyDeep),
          ),
          const SizedBox(width: 14),
        ],
        CircleAvatar(
          radius: showName ? 26 : 20,
          backgroundColor: mediclyDeep.withValues(alpha: 0.1),
          child: Icon(
            Icons.person_outline,
            size: showName ? 30 : 24,
            color: mediclyDeep,
          ),
        ),
      ],
    );
  }
}
