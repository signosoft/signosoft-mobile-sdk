// What a client sees first is the demo on their own device. These tests are
// about that: the screen fits, and the button a person taps can be tapped.
//
// The signature ceremony itself is a platform channel and cannot run here, so
// nothing below drives it — the disabled Sign state is what a widget test can
// honestly check.
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medicly_demo/main.dart';
import 'package:medicly_demo/report_screen.dart';

const _iPhone = Size(393, 852);
const _iPad = Size(1024, 1366);

/// Renders the whole app at a physical screen size, as a device would.
Future<void> _pumpAt(WidgetTester tester, Size size) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(const MediclyApp());
  // Not pumpAndSettle: the PDF viewer shows an indeterminate spinner while it
  // loads, which never settles.
  await tester.pump(const Duration(seconds: 1));
}

/// True when a finger landing on the widget's centre would reach it — which is
/// what "reachable" means to the person holding the phone. A widget shoved off
/// the bottom of the screen is in the tree and fails this.
bool _isHittable(WidgetTester tester, Finder finder) {
  final box = tester.renderObject<RenderBox>(finder);
  final centre = box.localToGlobal(box.size.center(Offset.zero));
  final screen = tester.view.physicalSize / tester.view.devicePixelRatio;
  final onScreen =
      centre.dx >= 0 &&
      centre.dy >= 0 &&
      centre.dx <= screen.width &&
      centre.dy <= screen.height;
  if (!onScreen) return false;

  final result = HitTestResult();
  WidgetsBinding.instance.hitTestInView(result, centre, tester.view.viewId);
  return result.path.any((entry) => entry.target == box);
}

/// The Sign button by the words on it, not by where it sits in the tree.
final _signButton = find.ancestor(
  of: find.text('Sign document'),
  matching: find.byType(FilledButton),
);

void main() {
  testWidgets('lays out with no overflow at iPhone size', (tester) async {
    await _pumpAt(tester, _iPhone);

    // An overflow is reported as a Flutter error, so an empty error queue is
    // the assertion. Pixel counts are not: they pass while the screen is broken.
    expect(tester.takeException(), isNull);
  });

  testWidgets('lays out with no overflow at iPad size', (tester) async {
    await _pumpAt(tester, _iPad);

    expect(tester.takeException(), isNull);
  });

  testWidgets('the Sign button is reachable at phone width', (tester) async {
    await _pumpAt(tester, _iPhone);

    expect(_signButton, findsOneWidget);
    expect(
      _isHittable(tester, _signButton),
      isTrue,
      reason: 'the Sign button is in the tree but a finger cannot reach it',
    );
  });

  testWidgets('the Sign button explains itself when no BIOID was passed', (
    tester,
  ) async {
    // Tests run without --dart-define=BIOID, which is exactly the state a
    // client reaches on their first `flutter run`.
    await _pumpAt(tester, _iPhone);

    expect(tester.widget<FilledButton>(_signButton).onPressed, isNull);
    expect(
      find.textContaining('BIOID'),
      findsWidgets,
      reason: 'a dead button with no explanation reads as a broken SDK',
    );
  });

  testWidgets('the Sign button is reachable on a tablet too', (tester) async {
    await _pumpAt(tester, _iPad);

    expect(_signButton, findsOneWidget);
    expect(_isHittable(tester, _signButton), isTrue);
  });

  test('text scaling steps down with the width class', () {
    // The tablet at 2x is the reference and must not move.
    expect(demoTextScale(_iPad.width), 2.0);
    expect(demoTextScale(kExpandedWidth), 2.0);
    expect(demoTextScale(kCompactWidth), lessThan(2.0));
    expect(demoTextScale(_iPhone.width), lessThan(demoTextScale(700)));
  });
}
