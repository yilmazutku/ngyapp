import 'dart:ui' show ViewPadding;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

const String kPreviousPhotoTooltip = 'Önceki fotoğraf';
const String kNextPhotoTooltip = 'Sonraki fotoğraf';
const String kCloseLabel = 'Kapat';

class PhotoDialogProbe {
  PhotoDialogProbe(this.tester);

  final WidgetTester tester;

  static const double _epsilon = 0.01;

  Finder get dialog => find.byType(AlertDialog);

  Finder get material =>
      find.descendant(of: dialog, matching: find.byType(Material)).first;

  Finder get image => find
      .descendant(of: dialog, matching: find.byType(InteractiveViewer))
      .first;

  Finder get viewport =>
      find.descendant(of: dialog, matching: find.byType(Scrollable)).first;

  Finder _arrow(IconData icon) => find.ancestor(
        of: find.descendant(of: dialog, matching: find.byIcon(icon)),
        matching: find.byType(IconButton),
      );

  Finder get previous => _arrow(Icons.chevron_left);

  Finder get next => _arrow(Icons.chevron_right);

  Finder get counter => find.descendant(
        of: dialog,
        matching: find.textContaining(RegExp(r'^\d+ / \d+$')),
      );

  Finder get _titleStack =>
      find.descendant(of: dialog, matching: find.byType(IndexedStack)).first;

  Finder get _counterStack =>
      find.ancestor(of: counter, matching: find.byType(IndexedStack)).first;

  bool get isOpen => dialog.evaluate().isNotEmpty;

  bool get hasNavigation => find
      .descendant(of: dialog, matching: find.byIcon(Icons.chevron_left))
      .evaluate()
      .isNotEmpty;

  String get counterText => tester.widget<Text>(counter).data!;

  String get title => tester
      .widget<Text>(
        find.descendant(of: _titleStack, matching: find.byType(Text)),
      )
      .data!;

  double get imageScale => tester
      .widget<Transform>(
        find.descendant(of: image, matching: find.byType(Transform)).first,
      )
      .transform
      .getMaxScaleOnAxis();

  int get heroCount => find
      .descendant(of: dialog, matching: find.byType(Hero))
      .evaluate()
      .length;

  Size get screen => tester.view.physicalSize / tester.view.devicePixelRatio;

  bool isShown(Finder arrow) {
    final Visibility visibility = tester.widget<Visibility>(
      find.ancestor(of: arrow, matching: find.byType(Visibility)).first,
    );
    final bool hittable = arrow.hitTestable().evaluate().isNotEmpty;
    final bool enabled = tester.widget<IconButton>(arrow).onPressed != null;
    final String tooltip = tester.widget<IconButton>(arrow).tooltip!;
    final bool inSemantics = find.semantics
        .byPredicate((SemanticsNode node) => node.tooltip == tooltip)
        .evaluate()
        .isNotEmpty;
    expect(hittable, visibility.visible,
        reason: 'görünen ok dokunulabilir, gizli ok dokunulmaz olmalı');
    expect(enabled, visibility.visible,
        reason: 'gizli ok basılabilir kalmamalı');
    expect(inSemantics, visibility.visible,
        reason: 'gizli ok ekran okuyucuya söylenmemeli');
    return visibility.visible;
  }

  void expectArrows({required bool previousShown, required bool nextShown}) {
    expect(isShown(previous), previousShown,
        reason: previousShown
            ? 'solda fotoğraf varken sol ok görünmeli'
            : 'solda fotoğraf yokken sol ok çıkmamalı');
    expect(isShown(next), nextShown,
        reason: nextShown
            ? 'sağda fotoğraf varken sağ ok görünmeli'
            : 'sağda fotoğraf yokken sağ ok çıkmamalı');
  }

  Future<void> showNext() async {
    await tester.tap(next);
    await tester.pumpAndSettle();
  }

  Future<void> showPrevious() async {
    await tester.tap(previous);
    await tester.pumpAndSettle();
  }

  Map<String, Rect> layout() => {
        'diyalog': tester.getRect(material),
        'başlık': tester.getRect(_titleStack),
        'fotoğraf': tester.getRect(image),
        'sol ok': tester.getRect(previous),
        'sayaç': tester.getRect(_counterStack),
        'sağ ok': tester.getRect(next),
      };

  void expectSameLayout(Map<String, Rect> expected, String at) {
    final Map<String, Rect> actual = layout();
    for (final String part in [
      'başlık',
      'fotoğraf',
      'sol ok',
      'sayaç',
      'sağ ok'
    ]) {
      final Rect a = actual[part]!;
      final Rect e = expected[part]!;
      expect(
        (a.left - e.left).abs() < _epsilon &&
            (a.top - e.top).abs() < _epsilon &&
            (a.right - e.right).abs() < _epsilon &&
            (a.bottom - e.bottom).abs() < _epsilon,
        isTrue,
        reason: '$at: $part yerinden oynamamalı ($e -> $a)',
      );
    }
  }

  void expectPlacement(String at) {
    final Rect dialogRect = tester.getRect(material);
    final Rect imageRect = tester.getRect(image);
    final Rect previousRect = tester.getRect(previous);
    final Rect nextRect = tester.getRect(next);
    final Rect counterRect = tester.getRect(counter);
    final Rect viewportRect = tester.getRect(viewport);
    final Rect closeRect = tester.getRect(
      find.descendant(of: dialog, matching: find.text(kCloseLabel)),
    );
    const double tolerance = 0.5;

    expect(dialogRect.left, greaterThanOrEqualTo(-tolerance),
        reason: '$at: diyalog ekranın solundan taşmamalı');
    expect(dialogRect.top, greaterThanOrEqualTo(-tolerance),
        reason: '$at: diyalog ekranın üstünden taşmamalı');
    expect(dialogRect.right, lessThanOrEqualTo(screen.width + tolerance),
        reason: '$at: diyalog ekranın sağından taşmamalı');
    expect(dialogRect.bottom, lessThanOrEqualTo(screen.height + tolerance),
        reason: '$at: diyalog ekranın altından taşmamalı');

    expect(previousRect.top, greaterThanOrEqualTo(imageRect.bottom),
        reason: '$at: oklar fotoğrafın altında olmalı');
    expect(previousRect.top - imageRect.bottom, lessThan(24),
        reason: '$at: oklar fotoğrafın hemen altında olmalı');
    expect((previousRect.center.dy - nextRect.center.dy).abs(),
        lessThan(tolerance),
        reason: '$at: iki ok aynı satırda olmalı');
    expect((counterRect.center.dy - previousRect.center.dy).abs(),
        lessThan(tolerance),
        reason: '$at: sayaç okların hizasında olmalı');
    expect((counterRect.center.dx - imageRect.center.dx).abs(),
        lessThan(tolerance),
        reason: '$at: sayaç fotoğrafın tam ortasının altında olmalı');
    expect(
        ((previousRect.center.dx + nextRect.center.dx) / 2 -
                imageRect.center.dx)
            .abs(),
        lessThan(tolerance),
        reason: '$at: oklar fotoğrafın ortasına göre simetrik olmalı');
    expect(previousRect.right, lessThanOrEqualTo(counterRect.left + tolerance),
        reason: '$at: sol ok sayacın solunda, üstüne binmeden');
    expect(nextRect.left, greaterThanOrEqualTo(counterRect.right - tolerance),
        reason: '$at: sağ ok sayacın sağında, üstüne binmeden');
    expect(previousRect.left, greaterThanOrEqualTo(imageRect.left - tolerance),
        reason: '$at: sol ok fotoğrafın genişliği içinde');
    expect(nextRect.right, lessThanOrEqualTo(imageRect.right + tolerance),
        reason: '$at: sağ ok fotoğrafın genişliği içinde');

    expect(previousRect.top, greaterThanOrEqualTo(viewportRect.top - tolerance),
        reason: '$at: oklar kaydırmadan görünmeli');
    expect(nextRect.bottom, lessThanOrEqualTo(viewportRect.bottom + tolerance),
        reason: '$at: oklar kaydırmadan görünmeli (alt kenarda kesilmemeli)');
    expect(nextRect.bottom, lessThanOrEqualTo(closeRect.top),
        reason: '$at: oklar "Kapat"ın üstünde kalmalı');
  }

  Rect get safeArea {
    final double ratio = tester.view.devicePixelRatio;
    final ViewPadding padding = tester.view.padding;
    return Rect.fromLTRB(
      padding.left / ratio,
      padding.top / ratio,
      screen.width - padding.right / ratio,
      screen.height - padding.bottom / ratio,
    );
  }

  void expectCentered(String at) {
    final Rect dialogRect = tester.getRect(material);
    final Rect safe = safeArea;
    expect((dialogRect.center.dy - safe.center.dy).abs(), lessThan(0.5),
        reason: '$at: diyalog güvenli alanın dikey ortasında açılmalı');
    expect((dialogRect.center.dx - safe.center.dx).abs(), lessThan(0.5),
        reason: '$at: diyalog güvenli alanın yatay ortasında açılmalı');
    expect(dialogRect.top, greaterThanOrEqualTo(safe.top),
        reason: '$at: diyalog çentiğin altına girmemeli');
    expect(dialogRect.bottom, lessThanOrEqualTo(safe.bottom),
        reason: '$at: diyalog home çubuğunun altına girmemeli');
  }
}
