import 'package:flutter/material.dart';

import 'medicly_logo.dart';
import 'report_screen.dart';

void main() => runApp(const MediclyApp());

class MediclyApp extends StatelessWidget {
  const MediclyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Medicly',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: mediclyTeal),
        scaffoldBackgroundColor: const Color(0xFFF3F6F7),
        cardTheme: CardThemeData(
          elevation: 0,
          color: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: Colors.black.withValues(alpha: 0.06)),
          ),
        ),
      ),
      // Demo app viewed across a room — everything runs oversized. 2x is the
      // reference on a tablet; a phone has no room for it, so the fixed scale
      // steps down with the window's width class (see kCompactWidth /
      // kExpandedWidth in report_screen.dart).
      builder: (context, child) {
        final scale = demoTextScale(MediaQuery.sizeOf(context).width);
        return MediaQuery.withClampedTextScaling(
          minScaleFactor: scale,
          maxScaleFactor: scale,
          child: child!,
        );
      },
      home: const ReportScreen(),
    );
  }
}
