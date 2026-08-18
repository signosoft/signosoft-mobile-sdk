// This is the app a client copies from, so these tests are about what a client
// sees: the page fits the device in their hands, the one button on it cannot be
// tapped into a guaranteed failure, and each of the four outcomes says
// something different.
//
// The ceremony itself is a platform channel and cannot run here, so nothing
// below drives it. The outcome rendering is exercised directly instead.
import 'dart:math';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:signosoft_signer/signosoft_signer.dart';
import 'package:signosoft_signer_example/main.dart';

const _iPhone = Size(393, 852);
const _iPad = Size(1024, 1366);

/// Renders the whole app at a physical screen size, as a device would.
Future<void> _pumpAt(WidgetTester tester, Size size) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(const ExampleApp());
  await tester.pumpAndSettle();
}

/// True when a finger landing on the widget's centre would reach it — which is
/// what "reachable" means to the person holding the device. A widget pushed off
/// the bottom of the screen is still in the tree and fails this.
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

/// The button by the words on it, not by where it sits in the tree.
final _openButton = find.ancestor(
  of: find.text('Sign document'),
  matching: find.byType(FilledButton),
);

final _tokenField = find.ancestor(
  of: find.text('bioid'),
  matching: find.byType(TextField),
);

/// Renders one outcome the way the page does, with nothing else on screen.
Future<void> _pumpOutcome(
  WidgetTester tester,
  SignosoftSignResult? result, {
  Size? at,
}) async {
  if (at != null) {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = at;
    addTearDown(tester.view.reset);
  }
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        // The same padding the page puts around it, so a long payload is
        // measured against the width it really gets.
        body: ListView(
          padding: const EdgeInsets.all(24),
          children: [OutcomeView(result: result)],
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Signed _signed({String? signedPdfPath}) => Signed(
  result: 'success',
  document: '4021',
  documentToken: 'a' * 64,
  lang: 'en',
  signaturesSigned: 2,
  signaturesTotal: 2,
  lastSignerFirstName: 'Vojta',
  lastSignerLastName: 'Vlachovsky',
  lastSignerEmail: 'vojta@example.com',
  signedPdfPath: signedPdfPath,
);

const _rejected = Rejected(
  result: 'rejected',
  document: '4021',
  documentToken: 'b',
  lang: 'en',
  signaturesSigned: 0,
  signaturesTotal: 2,
  lastSignerFirstName: 'Vojta',
  lastSignerLastName: 'Vlachovsky',
  lastSignerEmail: 'vojta@example.com',
);

void main() {
  testWidgets('lays out with no overflow at iPhone size', (tester) async {
    await _pumpAt(tester, _iPhone);

    // An overflow is reported as a Flutter error, so an empty error queue is
    // the assertion. Pixel counts are not: they pass while the screen is broken.
    expect(tester.takeException(), isNull);
    expect(_openButton, findsOneWidget);
    expect(
      _isHittable(tester, _openButton),
      isTrue,
      reason: 'the button is in the tree but a finger cannot reach it',
    );

    // The widest thing the page ever shows is a Signed payload with a
    // 64-character documentToken in it, and a phone is where it has least room.
    await _pumpOutcome(tester, _signed(), at: _iPhone);
    expect(tester.takeException(), isNull);
  });

  testWidgets('lays out with no overflow at iPad size', (tester) async {
    await _pumpAt(tester, _iPad);

    expect(tester.takeException(), isNull);
    expect(_openButton, findsOneWidget);
    expect(_isHittable(tester, _openButton), isTrue);

    await _pumpOutcome(tester, _signed(), at: _iPad);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the open button is disabled until a token is entered', (
    tester,
  ) async {
    await _pumpAt(tester, _iPhone);

    // A first run has an empty bioid. open() would answer invalidToken without
    // ever showing a ceremony, which reads as a broken SDK.
    expect(tester.widget<FilledButton>(_openButton).onPressed, isNull);
    expect(
      find.text('Paste a bioid above to enable signing.'),
      findsOneWidget,
      reason: 'a dead button with no explanation reads as a broken SDK',
    );

    // Whitespace is not a token.
    await tester.enterText(_tokenField, '   ');
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(_openButton).onPressed, isNull);

    await tester.enterText(_tokenField, 'a' * 64);
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(_openButton).onPressed, isNotNull);
    expect(find.text('Paste a bioid above to enable signing.'), findsNothing);
  });

  testWidgets('each of the four outcomes renders its own message', (
    tester,
  ) async {
    // Before anything is signed.
    await _pumpOutcome(tester, null);
    expect(find.text('No result yet'), findsOneWidget);

    await _pumpOutcome(tester, _signed());
    expect(find.text('Signed'), findsOneWidget);
    // The payload is on screen on purpose: showing it is this example's point.
    expect(find.textContaining('documentToken: ${'a' * 64}'), findsOneWidget);
    expect(find.textContaining('signatures: 2/2'), findsOneWidget);
    expect(
      find.textContaining('fetch it server-side'),
      findsOneWidget,
      reason: 'a missing local copy is not a failure and must not read as one',
    );

    await _pumpOutcome(tester, _signed(signedPdfPath: '/tmp/signed.pdf'));
    expect(find.textContaining('local copy: /tmp/signed.pdf'), findsOneWidget);

    await _pumpOutcome(tester, _rejected);
    expect(find.text('Rejected'), findsOneWidget);
    expect(find.textContaining('cannot be signed afterwards'), findsOneWidget);

    await _pumpOutcome(tester, const Cancelled());
    expect(find.text('Cancelled'), findsOneWidget);
    expect(find.textContaining('may open the same bioid again'), findsOneWidget);

    await _pumpOutcome(
      tester,
      const Failed(SignosoftErrorCode.sessionFailed, 'link already used'),
    );
    expect(find.text('Failed'), findsOneWidget);
    expect(find.textContaining('code: sessionFailed'), findsOneWidget);
    expect(find.textContaining('link already used'), findsOneWidget);
  });

  testWidgets('an outcome message stays readable against its own card', (
    tester,
  ) async {
    // An elevated Material paints through a physical-shape layer that drops the
    // alpha of its colour, so a translucent tint here becomes a solid slab with
    // same-coloured text on it — which is what shipped, and unreadable.
    for (final result in <SignosoftSignResult?>[
      null,
      _signed(),
      _rejected,
      const Cancelled(),
      const Failed(SignosoftErrorCode.loadFailed, 'no network'),
    ]) {
      await _pumpOutcome(tester, result);

      final card = tester.widget<Card>(find.byType(Card));
      final background = card.color!;
      final title = tester
          .widget<Text>(find.descendant(
            of: find.byType(Card),
            matching: find.byType(Text),
          ))
          .style!;

      expect(
        background.a,
        1.0,
        reason: 'a translucent card colour is painted opaque, not blended',
      );
      expect(
        _contrast(title.color!, background),
        greaterThan(4.5),
        reason: 'the $result title is unreadable on its own card',
      );
    }
  });
}

/// WCAG relative-luminance contrast ratio between two opaque colours.
double _contrast(Color foreground, Color background) {
  double luminance(Color c) {
    double channel(double v) =>
        v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4).toDouble();
    return 0.2126 * channel(c.r) +
        0.7152 * channel(c.g) +
        0.0722 * channel(c.b);
  }

  final a = luminance(foreground);
  final b = luminance(background);
  final lighter = a > b ? a : b;
  final darker = a > b ? b : a;
  return (lighter + 0.05) / (darker + 0.05);
}
