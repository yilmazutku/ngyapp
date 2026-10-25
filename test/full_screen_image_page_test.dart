import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ngy_app/widgets/full_screen_image_page.dart';

void main() {
  const String reactionsText = 'ifadeler';

  /// Sohbetteki gibi: alt çubukta ortalanmış bir satır (ifade satırı ya da
  /// "Fotoğrafı Sil").
  Future<void> openViewer(WidgetTester tester) async {
    late BuildContext pageContext;
    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (context) {
        pageContext = context;
        return const Scaffold(body: Text('sohbet'));
      }),
    ));
    showFullScreenImage<void>(
      pageContext,
      imageUrl: 'https://x/a.jpg',
      title: 'Öğle · 22 Ekim 2026 12:30',
      bottomBarBuilder: (_) => const Padding(
        padding: EdgeInsets.all(8),
        child: Center(child: Text(reactionsText)),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(FullScreenImagePage), findsOneWidget);
  }

  testWidgets('sol üstteki çarpı görüntüleyiciyi kapatır', (tester) async {
    await openViewer(tester);

    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();

    expect(find.byType(FullScreenImagePage), findsNothing);
  });

  testWidgets('fotoğraf aşağı kaydırılınca görüntüleyici kapanır',
      (tester) async {
    await openViewer(tester);
    final Size screen = tester.view.physicalSize / tester.view.devicePixelRatio;

    await tester.dragFrom(
      Offset(screen.width / 2, screen.height / 2),
      Offset(0, screen.height / 4),
    );
    await tester.pumpAndSettle();

    expect(find.byType(FullScreenImagePage), findsNothing);
  });

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
    final Size screen = tester.view.physicalSize / tester.view.devicePixelRatio;

    final Rect reactions = tester.getRect(find.text(reactionsText));
    expect(reactions.center.dx, closeTo(screen.width / 2, 1),
        reason: 'yatayda ortada');
    expect(reactions.bottom, greaterThan(screen.height * 0.9),
        reason: 'ekranın altında, dikeyde ortada değil');
  });
}
