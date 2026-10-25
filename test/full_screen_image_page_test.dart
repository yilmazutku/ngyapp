import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ngy_app/widgets/full_screen_image_page.dart';

void main() {
  const String reactionsText = 'ifadeler';

  const String deleteText = 'Fotoğrafı Sil';
  const String deleteResult = 'sil';

  /// Sohbetteki gibi açar: admin'de altta ortalanmış ifade satırı, danışanda
  /// sağ üstte "Fotoğrafı Sil". Görüntüleyicinin sonucunu döner.
  Future<Future<String?>> openViewer(
    WidgetTester tester, {
    bool asClient = false,
  }) async {
    late BuildContext pageContext;
    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (context) {
        pageContext = context;
        return const Scaffold(body: Text('sohbet'));
      }),
    ));
    final Future<String?> result = showFullScreenImage<String>(
      pageContext,
      imageUrl: 'https://x/a.jpg',
      title: 'Öğle · 22 Ekim 2026 Perşembe 12:30',
      topActionBuilder: asClient
          ? (viewerContext) => FilledButton.icon(
                icon: const Icon(Icons.delete_outline),
                label: const Text(deleteText),
                onPressed: () =>
                    Navigator.of(viewerContext).pop(deleteResult),
              )
          : null,
      bottomBarBuilder: asClient
          ? null
          : (_) => const Padding(
                padding: EdgeInsets.all(8),
                child: Center(child: Text(reactionsText)),
              ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(FullScreenImagePage), findsOneWidget);
    return result;
  }

  Size screenOf(WidgetTester tester) =>
      tester.view.physicalSize / tester.view.devicePixelRatio;

  for (final bool asClient in [false, true]) {
    testWidgets(
        '${asClient ? 'danışan' : 'admin'}: sol üstteki çarpı '
        'görüntüleyiciyi kapatır, sohbete dönülür', (tester) async {
      final Future<String?> result =
          await openViewer(tester, asClient: asClient);

      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();

      expect(find.byType(FullScreenImagePage), findsNothing);
      expect(find.text('sohbet'), findsOneWidget);
      expect(await result, isNull);
    });
  }

  for (final bool asClient in [false, true]) {
    testWidgets(
        '${asClient ? 'danışan' : 'admin'}: başlık üstte, çarpıyla aynı '
        'satırda; fotoğrafı örtmez', (tester) async {
      await openViewer(tester, asClient: asClient);

      final Rect title = tester.getRect(find.textContaining('Perşembe'));
      final Rect close = tester.getRect(find.byIcon(Icons.close));
      expect(title.center.dy, closeTo(close.center.dy, 1));
      expect(title.left, greaterThan(close.right), reason: 'çarpının sağında');
    });
  }

  testWidgets(
      'danışan (telefon, 360 dp): "Fotoğrafı Sil" sağ üstte, başlıkla aynı '
      'satırda', (tester) async {
    tester.view.physicalSize = const Size(1080, 2220);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await openViewer(tester, asClient: true);
    final Size screen = screenOf(tester);

    final Rect delete = tester.getRect(find.byType(FilledButton));
    final Rect close = tester.getRect(find.byIcon(Icons.close));
    expect(delete.right, greaterThan(screen.width - 16), reason: 'sağda');
    expect(delete.center.dy, closeTo(close.center.dy, 1), reason: 'üstte');
    expect(tester.takeException(), isNull, reason: 'uzun başlık taşmaz');
  });

  testWidgets('danışan: "Fotoğrafı Sil"e basınca görüntüleyici kapanır, '
      'silme seçilir', (tester) async {
    final Future<String?> result = await openViewer(tester, asClient: true);

    await tester.tap(find.text(deleteText));
    await tester.pumpAndSettle();

    expect(find.byType(FullScreenImagePage), findsNothing);
    expect(await result, deleteResult);
  });

  for (final bool asClient in [false, true]) {
    testWidgets(
        '${asClient ? 'danışan' : 'admin'}: fotoğraf aşağı kaydırılınca '
        'görüntüleyici kapanır', (tester) async {
      await openViewer(tester, asClient: asClient);
      final Size screen = screenOf(tester);

      await tester.dragFrom(
        Offset(screen.width / 2, screen.height / 2),
        Offset(0, screen.height / 4),
      );
      await tester.pumpAndSettle();

      expect(find.byType(FullScreenImagePage), findsNothing);
    });
  }

  testWidgets('az kaydırılınca kapanmaz, fotoğraf yerine döner',
      (tester) async {
    await openViewer(tester);

    await tester.timedDragFrom(
      tester.getCenter(find.byType(FullScreenImagePage)),
      const Offset(0, 40),
      const Duration(milliseconds: 500),
    );
    await tester.pumpAndSettle();

    expect(find.byType(FullScreenImagePage), findsOneWidget);
  });

  testWidgets('alt çubuk fotoğrafın altında, yalnızca içeriği kadar',
      (tester) async {
    await openViewer(tester);
    final Size screen = screenOf(tester);

    final Rect reactions = tester.getRect(find.text(reactionsText));
    expect(reactions.center.dx, closeTo(screen.width / 2, 1),
        reason: 'yatayda ortada');
    expect(reactions.bottom, greaterThan(screen.height * 0.9),
        reason: 'ekranın altında, dikeyde ortada değil');
  });
}
