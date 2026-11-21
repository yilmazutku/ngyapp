import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const double stripHeight = 200.0;
  const double bottomPadding = 16.0;
  const double cardBottom = stripHeight - bottomPadding;
  const EdgeInsets safeArea = EdgeInsets.only(bottom: 34, left: 44, right: 44);

  Future<void> pumpStrip(
    WidgetTester tester, {
    required bool removeSafeArea,
  }) async {
    final ScrollController controller = ScrollController();
    addTearDown(controller.dispose);
    final Widget scrollbar = Scrollbar(
      controller: controller,
      thumbVisibility: true,
      child: ListView.separated(
        controller: controller,
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(12, 8, 12, bottomPadding),
        itemCount: 20,
        separatorBuilder: (context, index) => const SizedBox(width: 8),
        itemBuilder: (context, index) =>
            const SizedBox(width: 150, child: Placeholder()),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(size: Size(800, 600), padding: safeArea),
          child: Scaffold(
            body: Builder(
              builder: (context) => Column(
                children: [
                  SizedBox(
                    height: stripHeight,
                    child: removeSafeArea
                        ? MediaQuery.removePadding(
                            context: context,
                            removeLeft: true,
                            removeTop: true,
                            removeRight: true,
                            removeBottom: true,
                            child: scrollbar,
                          )
                        : scrollbar,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Rect thumbRect(WidgetTester tester) {
    Rect? thumb;
    expect(
      find.byWidgetPredicate((widget) => widget is RawScrollbar).first,
      paints
        ..something((Symbol method, List<dynamic> arguments) {
          if (method == #drawRRect) {
            thumb = (arguments.first as RRect).outerRect;
            return true;
          }
          if (method == #drawRect) {
            thumb = arguments.first as Rect;
            return true;
          }
          return false;
        }),
    );
    return thumb!;
  }

  testWidgets('güvenli alan kaldırılınca çubuk kartların altında',
      (tester) async {
    await pumpStrip(tester, removeSafeArea: true);
    final Rect thumb = thumbRect(tester);
    expect(thumb.top, greaterThanOrEqualTo(cardBottom));
    expect(thumb.bottom, lessThanOrEqualTo(stripHeight));
  }, variant: TargetPlatformVariant.all());

  testWidgets('güvenli alan kaldırılmazsa çubuk kartların üstüne biner',
      (tester) async {
    await pumpStrip(tester, removeSafeArea: false);
    expect(thumbRect(tester).bottom, lessThan(cardBottom));
  }, variant: TargetPlatformVariant.all());
}
