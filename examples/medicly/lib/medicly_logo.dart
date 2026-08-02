import 'package:flutter/material.dart';

const mediclyTeal = Color(0xFF0E8F87);
const mediclyDeep = Color(0xFF0B5F6B);

class MediclyLogo extends StatelessWidget {
  const MediclyLogo({super.key, this.size = 64, this.showWordmark = true});

  final double size;
  final bool showWordmark;

  @override
  Widget build(BuildContext context) {
    final mark = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.28),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [mediclyTeal, mediclyDeep],
        ),
      ),
      child: CustomPaint(painter: _CrossPulsePainter()),
    );

    if (!showWordmark) return mark;

    // Wordmark scales off `size`, so opt out of the app-wide text scaling.
    return MediaQuery.withNoTextScaling(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          mark,
          SizedBox(width: size * 0.32),
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Medicly',
                style: TextStyle(
                  fontSize: size * 0.55,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.4,
                  color: mediclyDeep,
                ),
              ),
              Text(
                'Patient Records',
                style: TextStyle(
                  fontSize: size * 0.3,
                  letterSpacing: 0.6,
                  color: mediclyDeep.withValues(alpha: 0.65),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// White medical cross with a heartbeat line cut through its waist.
class _CrossPulsePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final arm = w * 0.22;
    final len = w * 0.56;
    final c = Offset(w / 2, w / 2);
    final paint = Paint()..color = Colors.white;

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: c, width: arm, height: len),
        Radius.circular(arm * 0.3),
      ),
      paint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: c, width: len, height: arm),
        Radius.circular(arm * 0.3),
      ),
      paint,
    );

    final pulse = Path()
      ..moveTo(w * 0.2, c.dy)
      ..lineTo(w * 0.38, c.dy)
      ..lineTo(w * 0.45, c.dy - arm * 0.55)
      ..lineTo(w * 0.55, c.dy + arm * 0.55)
      ..lineTo(w * 0.62, c.dy)
      ..lineTo(w * 0.8, c.dy);

    canvas.drawPath(
      pulse,
      Paint()
        ..color = mediclyDeep
        ..style = PaintingStyle.stroke
        ..strokeWidth = w * 0.055
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
