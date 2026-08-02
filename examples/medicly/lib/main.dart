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
      // Demo app viewed across a room — everything runs at 2x.
      builder: (context, child) => MediaQuery.withClampedTextScaling(
        minScaleFactor: 2,
        maxScaleFactor: 2,
        child: child!,
      ),
      home: const ReportScreen(),
    );
  }
}
