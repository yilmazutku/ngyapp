import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Sohbet listesinin kaydırma çubuğu yapısı (bkz. ChatPage._withScrollbar):
/// elle eklenen çubuk ve varsayılanı kapatan ScrollConfiguration.
void main() {
  final Finder scrollbars =
      find.byWidgetPredicate((widget) => widget is RawScrollbar);

  Future<void> pumpChatList(
    WidgetTester tester, {
    required bool hideDefaultScrollbar,
  }) async {
    final ScrollController controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              final Widget list = ListView.builder(
                controller: controller,
                reverse: true,
                itemCount: 100,
                itemBuilder: (_, i) => Text('mesaj $i'),
              );
              return Scrollbar(
                controller: controller,
                interactive: true,
                child: hideDefaultScrollbar
                    ? ScrollConfiguration(
                        behavior: ScrollConfiguration.of(context)
                            .copyWith(scrollbars: false),
                        child: list,
                      )
                    : list,
              );
            },
          ),
        ),
      ),
    );
  }

  testWidgets('her platformda tek kaydırma çubuğu', (tester) async {
    await pumpChatList(tester, hideDefaultScrollbar: true);
    expect(find.byType(Scrollbar), findsOneWidget);
    expect(scrollbars, findsOneWidget);
  }, variant: TargetPlatformVariant.all());

  testWidgets('varsayılan kapatılmazsa masaüstünde iki çubuk olur',
      (tester) async {
    await pumpChatList(tester, hideDefaultScrollbar: false);
    final bool desktop = TargetPlatformVariant.desktop()
        .values
        .contains(defaultTargetPlatform);
    expect(scrollbars, findsNWidgets(desktop ? 2 : 1));
  }, variant: TargetPlatformVariant.all());
}
