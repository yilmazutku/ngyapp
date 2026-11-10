import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ngy_app/services/in_app_banner_presenter.dart';

void main() {
  const Duration display = Duration(seconds: 4);

  Future<OverlayState> pumpOverlay(WidgetTester tester) async {
    final GlobalKey<NavigatorState> navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(MaterialApp(
      navigatorKey: navigator,
      home: const Scaffold(body: SizedBox.expand()),
    ));
    return navigator.currentState!.overlay!;
  }

  WidgetBuilder banner(String text) =>
      (_) => Positioned(top: 0, left: 0, child: Text(text));

  testWidgets('bant süresi dolunca kapanır', (tester) async {
    final OverlayState overlay = await pumpOverlay(tester);
    final InAppBannerPresenter presenter =
        InAppBannerPresenter(displayDuration: display);

    presenter.show(overlay, banner('A'));
    await tester.pump();
    expect(find.text('A'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 3900));
    expect(find.text('A'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('A'), findsNothing);
  });

  testWidgets('yeni bant önceki bandın zamanlayıcısıyla erken kapanmaz',
      (tester) async {
    final OverlayState overlay = await pumpOverlay(tester);
    final InAppBannerPresenter presenter =
        InAppBannerPresenter(displayDuration: display);

    presenter.show(overlay, banner('A'));
    await tester.pump(const Duration(seconds: 3));
    presenter.show(overlay, banner('B'));
    await tester.pump();
    expect(find.text('A'), findsNothing);
    expect(find.text('B'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 1500));
    expect(find.text('B'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 2400));
    expect(find.text('B'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('B'), findsNothing);
  });

  testWidgets('art arda gelen bantlarda ekranda hep son bant kalır',
      (tester) async {
    final OverlayState overlay = await pumpOverlay(tester);
    final InAppBannerPresenter presenter =
        InAppBannerPresenter(displayDuration: display);

    for (int i = 0; i < 10; i++) {
      presenter.show(overlay, banner('M$i'));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('M$i'), findsOneWidget);
      expect(find.textContaining('M'), findsOneWidget);
    }
    await tester.pump(const Duration(seconds: 3));
    expect(find.textContaining('M'), findsNothing);
  });

  testWidgets('elle kapatılan bant sonraki bandı etkilemez', (tester) async {
    final OverlayState overlay = await pumpOverlay(tester);
    final InAppBannerPresenter presenter =
        InAppBannerPresenter(displayDuration: display);

    presenter.show(overlay, banner('A'));
    await tester.pump(const Duration(seconds: 1));
    presenter.dismiss();
    presenter.dismiss();
    await tester.pump();
    expect(find.text('A'), findsNothing);

    await tester.pump(const Duration(seconds: 1));
    presenter.show(overlay, banner('B'));
    await tester.pump(const Duration(milliseconds: 3500));
    expect(find.text('B'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('B'), findsNothing);
  });
}
